--!strict
local Shared = script.Parent

local Signal = require(Shared.Signal)
local Network = require(Shared.Network)
local Promise = require(Shared.Promise)
local RunContext = require(Shared.RunContext)

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

type Promise = Promise.Class
type Signal<T...> = Signal.Signal<T...>

type OwnershipRecord = {
    Promise: Promise?,
    Changed: Signal<boolean>?,
}

local ownership = {} :: {
    [Player]: {
        [string]: OwnershipRecord,
    },
}

local productInfo = {} :: {
    [string]: Promise,
}

local mockPurchaseChecks = {} :: {
    [string]: () -> boolean,
}

local function addMockPurchaseCheck(id: string, check: () -> boolean)
    assert(RunContext.IsServer, "Mock purchase checks can only be added from the server!")
    mockPurchaseChecks[id] = check
end

local function removeMockPurchaseCheck(id: string)
    assert(RunContext.IsServer, "Mock purchase checks can only be removed from the server!")
    mockPurchaseChecks[id] = nil
end

local function canMockPurchase()
    for i, check in mockPurchaseChecks do
        if not check() then
            return false
        end
    end

    return true
end

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

local playerOwnsItem = Promise.promisify(function(player: Player, itemId: any, infoType: Enum.InfoType?)
    local userId = player.UserId

    if userId < 1 then
        return RunContext.IsStudio
    end

    if infoType == Enum.InfoType.Subscription then
        local status = MarketplaceService:GetUserSubscriptionStatusAsync(player, itemId)
        return status.IsSubscribed
    elseif infoType == Enum.InfoType.GamePass then
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, itemId)
    elseif infoType == Enum.InfoType.Bundle then
        return MarketplaceService:PlayerOwnsBundleAsync(player, itemId)
    elseif infoType == Enum.InfoType.Product then
        return false
    else
        return MarketplaceService:PlayerOwnsAssetAsync(player, itemId)
    end
end)

local getProductInfo = Promise.promisify(function(id: number, infoType: Enum.InfoType?)
    return MarketplaceService:GetProductInfoAsync(id, infoType)
end)

local GRANT_PURCHASE = Network.Event("Marketplace_GrantPurchase", function (player, id, infoType)
    assert(typeof(player) == "Instance" and player:IsA("Player"))
    assert(id ~= nil)
    
    if infoType == nil then
        return player, id, Enum.InfoType.Asset
    end

    assert(typeof(infoType) == "EnumItem" and infoType:IsA("InfoType"))
    return player, id, infoType
end)

local PROMPT_PURCHASE = Network.Event("Marketplace_PromptPurchase", function (id, infoType)
    assert(id ~= nil)
    
    if infoType == nil then
        return id, Enum.InfoType.Asset
    end

    assert(typeof(infoType) == "EnumItem" and infoType:IsA("InfoType"))
    return id, infoType
end)

local promptPurchaseFinished = Signal.new() :: Signal<Player, any, Enum.InfoType>

local function getOwnershipRecord<T>(player: Player, id: T, infoType: Enum.InfoType?): OwnershipRecord
    local infoType = infoType or Enum.InfoType.Asset

    local ownershipTable = ownership[player]
        or (function()
            ownership[player] = {}
            return ownership[player]
        end)()

    local key = `{infoType.Name}:{id}`

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
        local new = Promise.retryWithDelay(playerOwnsItem, 5, 2, player, id, infoType)
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

local function promiseProductInfo(id: number, infoType: Enum.InfoType?): Promise
    local infoType = infoType or Enum.InfoType.Asset
    local key = `{infoType.Name}:{id}`
    local promise = productInfo[key]

    if not promise then
        local new = Promise.retry(getProductInfo, 5, id, infoType)
        productInfo[key] = new

        new:catch(function()
            if productInfo[key] == new then
                productInfo[key] = nil
            end
        end)

        promise = new
    end

    return promise
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

local function grantPurchase<T>(player: Player, id: T, infoType: Enum.InfoType)
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

    data.Promise = Promise.resolve(true)
    promptPurchaseFinished:Fire(player, id, infoType)
end

local function promptPurchase(id: number, infoType: Enum.InfoType?, player: Player?)
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

    local canMock = canMockPurchase()

    if canMock or RunContext.IsEdit then
        local success, owned = promiseOwnership(player, id, infoType):await()

        if not (success and owned) then
            if canMock then
                warn("MOCKING PURCHASE", id, infoType, "FOR PLAYER", player)
            elseif RunContext.IsEdit then
                warn("MOCKING PURCHASE IN EDIT MODE", id, infoType, "FOR PLAYER", player)
            end

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

if RunContext.IsServer or RunContext.IsEdit then
    local promptServer = PROMPT_PURCHASE:Server()

    promptServer:On(function (player, id, infoType)
        promptPurchase(id :: any, infoType, player)
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
    local client = GRANT_PURCHASE:Client()
    client:On(grantPurchase)
end

return table.freeze({
    GetOwnership = promiseOwnership,
    PromptPurchase = promptPurchase,
    GetProductInfo = promiseProductInfo,
    BulkResolveOwnership = bulkResolveOwnership,
    GetOwnershipChangedSignal = getOwnershipChangedSignal,

    AddMockPurchaseCheck = addMockPurchaseCheck,
    RemoveMockPurchaseCheck = removeMockPurchaseCheck,
    
    PromptPurchaseFinished = promptPurchaseFinished,
})
