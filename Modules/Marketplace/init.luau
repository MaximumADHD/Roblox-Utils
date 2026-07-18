--!strict
local Shared = script.Parent

local Signal = require(Shared.Signal)
local UserId = require(Shared.UserId)
local Network = require(Shared.Network)
local Promise = require(Shared.Promise)
local RunContext = require(Shared.RunContext)

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")

type Promise = Promise.Class
type Signal<T...> = Signal.Signal<T...>

export type Ownership = {
    Id: number,
    InfoType: Enum.InfoType,
}

export type VapidOwnership = {
    Id: number?,
    InfoType: Enum.InfoType?,
}

export type ProductInfo = {
    AssetId: number,
    AssetTypeId: number,

    Creator: {
        Id: number,
        Name: string,
        CreatorType: "User" | "Group",
        CreatorTargetId: number,
        HasVerifiedBadge: boolean,
    },

    Description: string,
    IconImageAssetId: number,
    IsForSale: boolean,
    IsPublicDomain: boolean,
    Name: string,
    PriceInRobux: number,
    ProductId: number,
    ProductType: string,
    Created: string,
    Updated: string,
    TargetId: number,
}

type OwnershipRecord = {
    Promise: Promise?,
    Changed: Signal<boolean>?,
}

type PendingRequest = {
    Resolve: (any) -> (),
    Reject: (any) -> (),
}

export type ReceiptInfo = {
    PurchaseId: string,
    PlayerId: number,
    PlaceIdWherePurchased: number,
    ReceiptType: Enum.ReceiptType,
    CurrencySpent: number,

    -- Only present for Enum.ReceiptType.DeveloperProduct receipts.
    CurrencyType: Enum.CurrencyType?,
    ProductId: number?,

    -- Only present for Robux transfer receipts.
    TransferRequestId: string?,
}

local ownership = {} :: {
    [Player]: {
        [string]: OwnershipRecord,
    },
}

local productInfo = {} :: {
    [string]: Promise,
}

-- Client-side requests awaiting a response from the server.
local pendingOwnershipRequests = {} :: {
    [string]: PendingRequest
}

local pendingProductInfoRequests = {} :: {
    [string]: PendingRequest
}

local PRODUCT_INFO_RATE = 300 -- requests per minute
local PRODUCT_INFO_INTERVAL = 60 / PRODUCT_INFO_RATE
local PRODUCT_INFO_MAX_RETRIES = 5
local PRODUCT_INFO_RETRY_DELAY = 2

type ProductInfoQueueEntry = {
    Id: number,
    Attempts: number,
    InfoType: Enum.InfoType,
    
    Resolve: (any) -> (),
    Reject: (any) -> (),
}

local productInfoQueue = {} :: { ProductInfoQueueEntry }

local productInfoQueued = {} :: {
    [string]: ProductInfoQueueEntry
}

local mockEconomyChecks = {} :: {
    [string]: () -> boolean,
}

local purchaseValidators = {} :: {
    [string]: (player: Player, id: any, infoType: Enum.InfoType) -> boolean,
}

local productOwnershipCheckers = {} :: {
    [number]: (player: Player, productId: number) -> boolean,
}


local receiptHandlers = {} :: {
    [number]: {
        Callback: (info: ReceiptInfo) -> Enum.ReceiptDecision,
        Connection: RBXScriptConnection,
    }
}

local grantPurchase: (
    player: Player,
    id: any,
    infoType: Enum.InfoType
) -> ()

local function setMockEconomyCheck(id: string, check: (() -> boolean)?)
    if check then
        mockEconomyChecks[id] = check
    else
        mockEconomyChecks[id] = nil
    end
end

local function setPurchaseValidator(id: string, validator: ((player: Player, id: any, infoType: Enum.InfoType) -> boolean)?)
    assert(RunContext.IsServer, "Purchase validators can only be added from the server!")

    if validator then
        purchaseValidators[id] = validator
    else
        purchaseValidators[id] = nil
    end
end

local function setProductOwnershipChecker(productId: number, checker: ((player: Player, productId: number) -> boolean)?)
    assert(RunContext.IsServer, "Product ownership checker can only be set from the server!")
    
    if checker then
        productOwnershipCheckers[productId] = checker
    else
        productOwnershipCheckers[productId] = nil
    end
end

local function canMockEconomy()
    if next(mockEconomyChecks) == nil then
        return false
    end

    for i, check in mockEconomyChecks do
        if not check() then
            return false
        end
    end

    return true
end

local playerOwnsItem = Promise.promisify(function(player: Player, itemId: any, infoType: Enum.InfoType?)
    local userId = UserId.Get(player)

    if infoType == Enum.InfoType.Subscription then
        local status = MarketplaceService:GetUserSubscriptionStatusAsync(player, itemId)
        return status.IsSubscribed
    elseif infoType == Enum.InfoType.GamePass then
        return MarketplaceService:UserOwnsGamePassAsync(userId, itemId)
    elseif infoType == Enum.InfoType.Bundle then
        return MarketplaceService:PlayerOwnsBundleAsync(player, itemId)
    elseif infoType == Enum.InfoType.Product then
        -- Lazy "ownership" check for developer products. They aren't owned, but in events where the developer wants to
        -- for example, check if a player has purchased a gifting product, they can register a custom checker for that id.
        local checker = productOwnershipCheckers[itemId]

        if checker then
            return checker(player, itemId)
        end

        return false
    else
        return MarketplaceService:PlayerOwnsAssetAsync(player, itemId)
    end
end)

local function enqueueProductInfoFetch(entry: ProductInfoQueueEntry, priority: boolean)
    local key = `{entry.InfoType.Name}_{entry.Id}`
    local existing = productInfoQueued[key]

    if existing then
        if priority then
            local index = table.find(productInfoQueue, existing)

            if index then
                table.remove(productInfoQueue, index)
                table.insert(productInfoQueue, 1, existing)
            end
        end

        return
    end

    productInfoQueued[key] = entry

    if priority then
        table.insert(productInfoQueue, 1, entry)
    else
        table.insert(productInfoQueue, entry)
    end
end

task.spawn(function ()
    if RunContext.IsClient and not RunContext.IsEdit then
        -- Pure clients never call GetProductInfoAsync directly;
        -- they request product info from the server instead.
        return
    end

    while task.wait(PRODUCT_INFO_INTERVAL) do
        local entry = table.remove(productInfoQueue, 1)

        if not entry then
            continue
        end

        local cacheKey = `{entry.InfoType.Name}_{entry.Id}`

        local ok, result = pcall(function ()
            return MarketplaceService:GetProductInfoAsync(entry.Id, entry.InfoType)
        end)

        productInfoQueued[cacheKey] = nil

        if ok then
            entry.Resolve(result)
        else
            entry.Attempts += 1

            if entry.Attempts < PRODUCT_INFO_MAX_RETRIES then
                task.delay(PRODUCT_INFO_RETRY_DELAY, function ()
                    enqueueProductInfoFetch(entry, false)
                end)
            else
                entry.Reject(result)
            end
        end
    end
end)

local GRANT_PURCHASE = Network.ReliableEvent("Marketplace_GrantPurchase", function (player: unknown, id: unknown, infoType: unknown)
    assert(typeof(player) == "Instance" and player:IsA("Player"))
    assert(id ~= nil)

    if infoType == nil then
        return player, id, Enum.InfoType.Asset
    end

    assert(typeof(infoType) == "EnumItem" and infoType:IsA("InfoType"))
    return player, id, infoType
end)

local PROMPT_PURCHASE = Network.ReliableEvent("Marketplace_PromptPurchase", function (id: unknown, infoType: unknown)
    assert(id ~= nil)
    
    if infoType == nil then
        return id, Enum.InfoType.Asset
    end

    assert(typeof(infoType) == "EnumItem" and infoType:IsA("InfoType"))
    return id, infoType
end)

local REQUEST_PRODUCT_INFO = Network.ReliableEvent("Marketplace_RequestProductInfo", function (id: unknown, infoType: unknown)
    assert(type(id) == "number")
    assert(typeof(infoType) == "EnumItem" and infoType:IsA("InfoType"))
    return id, infoType :: Enum.InfoType
end)

local PRODUCT_INFO_RESULT = Network.ReliableEvent("Marketplace_ProductInfoResult", function (id: unknown, infoType: unknown, ok: unknown, result: unknown)
    assert(type(id) == "number")
    assert(typeof(infoType) == "EnumItem" and infoType:IsA("InfoType"))
    assert(type(ok) == "boolean")
    return id, infoType :: Enum.InfoType, ok, result
end)

local REQUEST_OWNERSHIP = Network.ReliableEvent("Marketplace_RequestOwnership", function (userId: unknown, id: unknown, infoType: unknown)
    assert(type(userId) == "number")
    assert(id ~= nil)
    assert(typeof(infoType) == "EnumItem" and infoType:IsA("InfoType"))
    return userId, id, infoType :: Enum.InfoType
end)

local OWNERSHIP_RESULT = Network.ReliableEvent("Marketplace_OwnershipResult", function (userId: unknown, id: unknown, infoType: unknown, ok: unknown, owned: unknown)
    assert(type(userId) == "number")
    assert(id ~= nil)
    assert(typeof(infoType) == "EnumItem" and infoType:IsA("InfoType"))
    assert(type(ok) == "boolean")
    return userId, id, infoType :: Enum.InfoType, ok, owned
end)

local promptPurchaseFinished = Signal.new() :: Signal<Player, any, Enum.InfoType>
local productGranted = Signal.new() :: Signal<Player, number, ReceiptInfo>

local function getOwnershipRecord<T>(player: Player, id: T, infoType: Enum.InfoType?): OwnershipRecord
    local infoType = infoType or Enum.InfoType.Asset

    local ownershipTable = ownership[player]
        or (function()
            ownership[player] = {}
            return ownership[player]
        end)()

    local key = `{infoType.Name}_{id}`

    local data = ownershipTable[key]
        or (function()
            ownershipTable[key] = {
                Promise = nil,
                Changed = Signal.new(),
            }

            return ownershipTable[key]
        end)()

    return data
end

local function promiseOwnership(player: Player, id: number, infoType: Enum.InfoType?): Promise
    local data = getOwnershipRecord(player, id, infoType)

    if not data.Promise then
        if canMockEconomy() then
            data.Promise = Promise.resolve(false)
            return assert(data.Promise)
        end

        local resolvedInfoType = infoType or Enum.InfoType.Asset
        local userId = UserId.Get(player)
        local new: Promise

        if RunContext.IsClient and not RunContext.IsEdit then
            -- Ask the server, which dedupes requests through its own ownership cache.
            local key = `{userId}_{resolvedInfoType.Name}_{id}`

            new = Promise.new(function (resolve, reject, onCancel)
                local pending: PendingRequest = {
                    Resolve = resolve,
                    Reject = reject
                }

                pendingOwnershipRequests[key] = pending

                onCancel(function ()
                    if pendingOwnershipRequests[key] == pending then
                        pendingOwnershipRequests[key] = nil
                    end
                end)

                local client = REQUEST_OWNERSHIP:Client()
                client:Fire(userId, id, resolvedInfoType)
            end)
        else
            new = Promise.retryWithDelay(playerOwnsItem, 5, 2, player, id, infoType)

            if RunContext.IsServer and not RunContext.IsEdit then
                -- Propagate successful server queries to the client so it never repeats them.
                new:andThen(function (owned: boolean)
                    local server = OWNERSHIP_RESULT:Server()
                    server:Fire(player, userId, id, resolvedInfoType, true, owned)
                end)
            end
        end

        data.Promise = new

        new:catch(function(err)
            if data.Promise == new then
                data.Promise = nil
            end
        end)
    end

    return assert(data.Promise)
end

local function getOwnershipChangedSignal(player: Player, id: number, infoType: Enum.InfoType?): Signal<boolean>
    local data = getOwnershipRecord(player, id, infoType)

    if not data.Changed then
        data.Changed = Signal.new()
    end

    return assert(data.Changed)
end

local function promiseProductInfo(id: number, infoType: Enum.InfoType?, priority: boolean?): Promise
    if id <= 0 then
        return Promise.reject(`Invalid product id: {id}`)
    end

    local resolvedInfoType = infoType or Enum.InfoType.Asset
    local key = `{resolvedInfoType.Name}_{id}`
    local existing = productInfo[key]

    if existing then
        if priority ~= false then
            local queueEntry = productInfoQueued[key]

            if queueEntry then
                for i = 1, #productInfoQueue do
                    if productInfoQueue[i] == queueEntry then
                        table.remove(productInfoQueue, i)
                        table.insert(productInfoQueue, 1, queueEntry)
                        break
                    end
                end
            end
        end

        return existing
    end

    local new = Promise.new(function(resolve, reject, onCancel)
        if RunContext.IsClient and not RunContext.IsEdit then
            -- Ask the server, which owns the GetProductInfoAsync queue. This joins any
            -- in-flight server request instead of starting a duplicate query from the client.
            local pending: PendingRequest = { Resolve = resolve, Reject = reject }
            pendingProductInfoRequests[key] = pending

            onCancel(function ()
                if pendingProductInfoRequests[key] == pending then
                    pendingProductInfoRequests[key] = nil
                end
            end)

            local client = REQUEST_PRODUCT_INFO:Client()
            client:Fire(id, resolvedInfoType)

            return
        end

        enqueueProductInfoFetch({
            Id = id,
            InfoType = resolvedInfoType,
            Attempts = 0,
            Resolve = resolve,
            Reject = reject,
        }, priority ~= false)
    end)

    productInfo[key] = new

    new:catch(function ()
        if productInfo[key] == new then
            productInfo[key] = nil
        end
    end)

    return new
end

local function prefetchProductInfo(id: number, infoType: Enum.InfoType?): Promise
    return promiseProductInfo(id, infoType, false)
end

local function setReceiptHandler(productId: number, handler: ((info: ReceiptInfo) -> Enum.ReceiptDecision)?)
    assert(RunContext.IsServer, "Receipt handlers can only be set from the server!")
    local activeHandler = receiptHandlers[productId]

    if activeHandler then
        activeHandler.Connection:Disconnect()
    end

    if not handler then
        receiptHandlers[productId] = nil
        return
    end

    -- Wrap the handler so successful receipts notify the rest of the module
    -- (ProductGranted, PromptPurchaseFinished, client replication).
    local function onHandleReceipt(info: ReceiptInfo): Enum.ReceiptDecision
        local decision = handler(info)

        if decision == Enum.ReceiptDecision.Processed then
            local player = Players:GetPlayerByUserId(info.PlayerId)

            if player then
                productGranted:Fire(player, productId, info)
            end
        end

        return decision
    end

    receiptHandlers[productId] = {
        Callback = onHandleReceipt,

        Connection = MarketplaceService:BindReceiptHandler(
            Enum.ReceiptType.DeveloperProduct,
            onHandleReceipt,
            { productId }
        )
    }
end

-- Simulates a developer product receipt when the economy is mocked (or in edit mode),
-- routing it through the registered receipt handler like a real purchase would be.
local function processMockReceiptAsync(player: Player, productId: number)
    local activeHandler = receiptHandlers[productId]

    local info: ReceiptInfo = {
        PurchaseId = `MOCK_` .. HttpService:GenerateGUID(false),
        PlayerId = player.UserId,
        PlaceIdWherePurchased = game.PlaceId,
        ReceiptType = Enum.ReceiptType.DeveloperProduct,
        CurrencySpent = 0,
        ProductId = productId,
        CurrencyType = Enum.CurrencyType.Robux,
    }

    if activeHandler then
        -- Wrapped callback has productGranted and grantPurchase calls, so we just need to check the decision.
        local ok, decision = xpcall(activeHandler.Callback, function (err)
            warn("ERROR PROCESSING MOCK RECEIPT FOR PRODUCT:", productId, "-", err, debug.traceback())
        end, info)

        if ok and decision ~= Enum.ReceiptDecision.Processed then
            warn("MOCK RECEIPT NOT YET PROCESSED FOR PRODUCT:", productId)
        end
    else
        -- No receipt handler registered; grant directly.
        productGranted:Fire(player, productId, info)
        grantPurchase(player, productId, Enum.InfoType.Product)
    end
end

local function bulkResolveOwnership(player: Player, ownershipList: { VapidOwnership }): Promise
    local n = #ownershipList
    local promises = table.create(n) :: { Promise }

    for i = 1, n do
        local rec = ownershipList[i]

        if rec.Id == nil or rec.Id <= 0 then
            promises[i] = Promise.resolve(false)
            continue
        end

        promises[i] = promiseOwnership(player, rec.Id, rec.InfoType)
    end

    return Promise.allSettled(promises):andThen(function()
        local results = table.create(n)

        for i = 1, n do
            local p = promises[i]
            local ok, val = p:await()
            results[i] = (ok and val) or false
        end

        return results
    end)
end

function grantPurchase(player: Player, id: any, infoType: Enum.InfoType)
    local data = getOwnershipRecord(player, id, infoType)

    if data.Changed then
        data.Changed:FireDeferred(true)
    end

    if data.Promise then
        data.Promise:cancel()
    end

    if RunContext.IsServer then
        local server = GRANT_PURCHASE:Server()
        server:FireAll(player, id, infoType)
    end

    -- Developer products are consumable and never owned, so don't cache ownership.
    data.Promise = if infoType ~= Enum.InfoType.Product 
        then Promise.resolve(true)
        else nil

    promptPurchaseFinished:Fire(player, id, infoType)
end

local function promptPurchase(id: any, infoType: Enum.InfoType?, player: Player?)
    if RunContext.IsClient and not RunContext.IsEdit then
        local client = PROMPT_PURCHASE:Client()
        client:Fire(id, infoType or Enum.InfoType.Asset)
        return
    end

    if RunContext.IsEdit then
        player = Players.LocalPlayer
    end

    if not player then
        return
    end

    local canMock = canMockEconomy()

    if canMock or RunContext.IsEdit then
        if canMock then
            warn("MOCKING PURCHASE", id, infoType, "FOR PLAYER", player)
        elseif RunContext.IsEdit then
            warn("MOCKING PURCHASE IN EDIT MODE", id, infoType, "FOR PLAYER", player)
        end

        if infoType == Enum.InfoType.Product then
            task.spawn(processMockReceiptAsync, player, id)
        else
            grantPurchase(player, id, infoType or Enum.InfoType.Asset)
        end

        return
    end
    
    if infoType == Enum.InfoType.GamePass then
        MarketplaceService:PromptGamePassPurchase(player, id)
    elseif infoType == Enum.InfoType.Bundle then
        MarketplaceService:PromptBundlePurchase(player, id)
    elseif infoType == Enum.InfoType.Product then
        MarketplaceService:PromptProductPurchase(player, id)
    else
        MarketplaceService:PromptPurchase(player, id)
    end
end

if RunContext.IsEdit then
    local mockEconomy = workspace:GetAttribute("EditModeMockEconomy")

    if mockEconomy then
        setMockEconomyCheck("__EditMode", function ()
            return true
        end)
    end
end

if RunContext.IsServer or RunContext.IsEdit then
    local promptServer = PROMPT_PURCHASE:Server()

    promptServer:On(function (player, id, infoType)
        for key, validator in purchaseValidators do
            if not validator(player, id, infoType) then
                warn("Purchase blocked by validator", key, "for player", player, "id", id, "infoType", infoType)
                return
            end
        end

        promptPurchase(id, infoType, player)
    end)

    local productInfoServer = REQUEST_PRODUCT_INFO:Server()

    productInfoServer:On(function (player: Player, id: number, infoType: Enum.InfoType)
        local resultServer = PRODUCT_INFO_RESULT:Server()

        promiseProductInfo(id, infoType, true):andThen(function (result)
            resultServer:Fire(player, id, infoType, true, result)
        end):catch(function (err)
            resultServer:Fire(player, id, infoType, false, tostring(err))
        end)
    end)

    local ownershipServer = REQUEST_OWNERSHIP:Server()

    ownershipServer:On(function (player: Player, userId: number, id: any, infoType: Enum.InfoType)
        local resultServer = OWNERSHIP_RESULT:Server()
        local target = Players:GetPlayerByUserId(userId)

        if not target then
            resultServer:Fire(player, userId, id, infoType, false, "Player not found")
            return
        end

        promiseOwnership(target, id, infoType):andThen(function (owned)
            resultServer:Fire(player, userId, id, infoType, true, owned)
        end):catch(function (err)
            resultServer:Fire(player, userId, id, infoType, false, tostring(err))
        end)
    end)

    local function createPurchaseFinishedCallback(infoType: Enum.InfoType)
        return function <T>(player: Instance, id: T, purchased: boolean)
            if not player:IsA("Player") then
                return
            end

            if not purchased then
                return
            end

            grantPurchase(player, id, infoType)
        end
    end

    MarketplaceService.PromptPurchaseFinished:Connect(createPurchaseFinishedCallback(Enum.InfoType.Asset))
    MarketplaceService.PromptBundlePurchaseFinished:Connect(createPurchaseFinishedCallback(Enum.InfoType.Bundle))
    MarketplaceService.PromptGamePassPurchaseFinished:Connect(createPurchaseFinishedCallback(Enum.InfoType.GamePass))
    MarketplaceService.PromptSubscriptionPurchaseFinished:Connect(createPurchaseFinishedCallback(Enum.InfoType.Subscription))

    local function onPlayerRemoving(player: Player)
        local ownershipTable = ownership[player]

        if ownershipTable then
            for i, data in ownershipTable do
                if data.Changed then
                    data.Changed:Destroy()
                end

                if data.Promise then
                    data.Promise:cancel()
                end
            end

            ownership[player] = nil
        end
    end

    Players.PlayerRemoving:Connect(onPlayerRemoving)
elseif not RunContext.IsEdit then
    local productInfoClient = PRODUCT_INFO_RESULT:Client()
    local grantPurchaseClient = GRANT_PURCHASE:Client()
    local ownershipClient = OWNERSHIP_RESULT:Client()

    productInfoClient:On(function (id: number, infoType: Enum.InfoType, ok: boolean, result: any)
        local key = `{infoType.Name}_{id}`

        local pending = pendingProductInfoRequests[key]
        pendingProductInfoRequests[key] = nil

        if pending then
            if ok then
                pending.Resolve(result)
            else
                pending.Reject(result)
            end
        end
    end)

    ownershipClient:On(function (userId: number, id: any, infoType: Enum.InfoType, ok: boolean, owned: any)
        local key = `{userId}_{infoType.Name}_{id}`

        local pending = pendingOwnershipRequests[key]
        pendingOwnershipRequests[key] = nil

        if pending then
            if ok then
                pending.Resolve(owned == true)
            else
                pending.Reject(owned)
            end

            return
        end

        -- Result pushed from a server-side query the client never asked for; warm the local cache.
        if ok then
            local player = Players:GetPlayerByUserId(userId)

            if player then
                local data = getOwnershipRecord(player, id, infoType)

                if not data.Promise then
                    data.Promise = Promise.resolve(owned == true)
                end
            end
        end
    end)

    grantPurchaseClient:On(grantPurchase)
end

local function remover<Key, Func>(setter: (key: Key, callback: Func?) -> ())
    return function (key: Key)
        setter(key, nil :: Func?)
    end
end

return table.freeze({
    GetOwnership = promiseOwnership,
    GetProductInfo = promiseProductInfo,
    PrefetchProductInfo = prefetchProductInfo,

    PromptPurchase = promptPurchase,
    BulkResolveOwnership = bulkResolveOwnership,
    GetOwnershipChangedSignal = getOwnershipChangedSignal,

    SetReceiptHandler = setReceiptHandler,
    SetMockEconomyCheck = setMockEconomyCheck,
    SetPurchaseValidator = setPurchaseValidator,
    SetProductOwnershipChecker = setProductOwnershipChecker,

    AddReceiptHandler = setReceiptHandler,
    AddMockEconomyCheck = setMockEconomyCheck,
    AddPurchaseValidator = setPurchaseValidator,
    AddProductOwnershipChecker = setProductOwnershipChecker,

    RemoveReceiptHandler = remover(setReceiptHandler),
    RemoveMockEconomyCheck = remover(setMockEconomyCheck),
    RemovePurchaseValidator = remover(setPurchaseValidator),
    RemoveProductOwnershipChecker = remover(setProductOwnershipChecker),

    PromptPurchaseFinished = promptPurchaseFinished,
    ProductGranted = productGranted,
})
