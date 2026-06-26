--!strict
local EasyStore = {}
EasyStore.__index = EasyStore

local PlayerData = {}
PlayerData.__index = PlayerData

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Shared = script.Parent

local Trove = require(Shared.Trove)
local Signal = require(Shared.Signal)
local UserId = require(Shared.UserId)
local Network = require(Shared.Network)
local Promise = require(Shared.Promise)
local DeltaTable = require(Shared.DeltaTable)
local RunContext = require(Shared.RunContext)

export type Config = {
    MockDataStoreService: DataStoreService?,
    AutoSaveInterval: number?,
    AllowMockSave: boolean?,
}

--- Represents an EasyStore instance for managing player data.
--- Can exist on the server, client, or in edit mode.
--- Use `EasyStore.Create` to create a new instance.
export type Class<T = any> = typeof(setmetatable({} :: {
    Default: T,

    _dataCache: {
        [number]: any,
    },

    _viewCache: {
        [number]: any,
    },

    _maid: Trove?,
    _allowMockSave: boolean,
    _autoSaveInterval: number,

    _netInit: Network.Class<LazyTable>,
    _netPatch: Network.Class<LazyTable>,
    _netRequest: Network.Class<>,

    _dataStoreService: DataStoreService?,
    _dataStoreName: string,
}, EasyStore))

type Trove = Trove.Trove
type Promise = Promise.Class
type LazyTable = DeltaTable.LazyTable
type Signal<T...> = Signal.Signal<T...>
type NetEvent<T...> = Network.Class<T...>

export type Patch = {
    Path: string,
    Value: any,
}

--- Represents a player's data profile in EasyStore.
export type PlayerData<T = any> = typeof(setmetatable({} :: {
    --- The current state of the player's data. This is immutable and should only be modified through `PlayerData:Patch` on the server.
    CurrentData: T,

    --- The UserId who owns this profile.
    Owner: number,

    -- The player currently associated with this profile.
    -- They may not have the same UserId as the owner if they are a mock user.
    Player: Player?,

    -- Is the data profile a mock user?
    IsMock: boolean,

    _maid: Trove,
    _server: Class<T>,

    --- Flag indicating whether the player's data has finished loading.
    IsLoaded: boolean,
    Updated: Signal<Patch>,
    Loaded: Signal<boolean>,
    
    --- Flag indicating whether there are unsaved changes to the player's data and a save is pending.
    HasPendingChanges: boolean,
}, PlayerData))


local function getProfileKey(userId: number)
    return `{userId}`
end

local function free<T>(data: PlayerData<T>)
    if data._maid then
        data._maid:Clean()
    end
end

local function reconcileTable(target: LazyTable, template: LazyTable): ()
    for k, v in pairs(template) do
        if type(k) == "string" then -- Only string keys will be reconciled
            if target[k] == nil then
                if type(v) == "table" then
                    target[k] = DeltaTable.DeepCopy(v)
                else
                    target[k] = v
                end
            elseif type(target[k]) == "table" and type(v) == "table" then
                reconcileTable(target[k], v)
            end
        end
    end
end

---
--- ```luau
--- -----------------------------------------------------
---   PlayerData:Save<T>() -> Promise<(), string>
--- -----------------------------------------------------
--- ```
---
--- **[Server-Only]** Forces the player's data to be saved now.
--- * If the player's data is not loaded, the promise will reject.
--- * If the player's data is loaded, the promise will resolve when the data has been saved.
--- * If called on the client, the promise will reject.
--- @return A `Promise<(), string>` that resolves when the player's data has been saved and rejects with an error message if something went wrong.
function PlayerData.Save<T>(self: PlayerData<T>, force: boolean?): Promise
    return Promise.new(function (resolve, reject)
        if not self.IsLoaded then
            reject("PlayerData not loaded!")
            return
        end

        if not (RunContext.IsServer or RunContext.IsEdit) then
            reject("PlayerData.Save can only be called on the server")
            return
        end

        local owner = self.Owner

        if self.IsMock and not self._server._allowMockSave then
            reject(`Not saving mock PlayerData for userId {owner}`)
            return
        end

        if not self:IsActive() and not force then
            reject("PlayerData is read-only!")
            return
        end

        local dataStore = self._server:GetDataStore()
        local key = getProfileKey(owner)

        dataStore:UpdateAsync(key, function (oldData)
            return self.CurrentData
        end)

        resolve()
    end)
end

---
--- ```luau
--- -----------------------------------------------------
---   EasyStore:Get<T>(target: (Player | number)?) -> PlayerData<T>
--- -----------------------------------------------------
--- ```
---
--- Gets a `PlayerData` object for the specified player **immediately**.
--- * **It may not be immediately ready for use!** Use `PlayerData.Load` to wait for the data to be loaded through a `Promise`
---   * Check the `IsLoaded` property to see if the data is ready, and/or listen against the `Loaded` signal.
--- * The data is read-only on the client, and on the server when the player is not in-game.
---   * It *can* be modified on the server if the player is in-game, or in edit mode if it belongs to the studio user.
---   * Modifications from the server will be propagated over to the client.
--- * If called on the client or in edit mode, it will return the data for the local user (the `userId` is ignored)
--- * If called on the server, the `userId` argument is **required** and the data for the specified player will be returned.
--- @param target The player or userId of the player to get data for. Ignored on the client and in edit mode.
function EasyStore.Get<T>(self: Class<T>, target: (Player | number)?): PlayerData<T>
    if RunContext.IsClient or RunContext.IsEdit then
        target = nil
    elseif type(target) == "number" then
        target = Players:GetPlayerByUserId(target)
    end

    local default = self.Default
    local userId, isMock = UserId.Get(target)

    local realUserId = if isMock
        then UserId.Get(target, true)
        else userId

    if RunContext.IsServer or RunContext.IsEdit then
        local player =
            if RunContext.IsEdit
                then Players.LocalPlayer
            elseif RunContext.IsServer
                then Players:GetPlayerByUserId(realUserId)
            else nil

        local cache: { PlayerData<T> } = if player
            then self._dataCache
            else self._viewCache

        if not cache[userId] then
            local key = getProfileKey(userId)
            local maid = Trove.new()

            local data: PlayerData<T> = setmetatable({
                CurrentData = DeltaTable.DeepCopy(default),
                _server = self,

                HasPendingChanges = false,
                IsLoaded = false,

                Owner = userId,
                IsMock = isMock,
                Player = player,

                Updated = Signal.new(),
                Loaded = Signal.new(),
                
                _maid = maid,
            }, PlayerData)

            task.spawn(function ()
                local RETRY_COUNT = 5
                local store = self:GetDataStore()

                for retry = 1, RETRY_COUNT do
                    local success, currentData = xpcall(function ()
                        return store:GetAsync(key) :: any
                    end, function (err)
                        warn("!! Error while loading profile for player", userId, err, debug.traceback())
                    end)

                    if success then
                        if currentData == nil then
                            currentData = DeltaTable.DeepCopy(default)
                        end

                        if currentData.RobloxMetaData ~= nil and not rawget(default :: any, "RobloxMetaData") then
                            -- ProfileService holdover, use the Data key.
                            currentData = currentData.Data
                        end

                        if currentData then
                            reconcileTable(currentData, default :: any);
                            (data :: any).CurrentData = currentData
                            
                            data.IsLoaded = true
                            data.Loaded:Fire(true)

                            break
                        end
                    elseif retry < RETRY_COUNT then
                        task.wait(retry / 2)
                    end
                end

                local autoSave = task.spawn(function ()
                    while task.wait(self._autoSaveInterval) do
                        if data:IsActive() and data.HasPendingChanges then
                            data:Save():andThen(function ()
                                data.HasPendingChanges = false
                            end):catch(function (err)
                                warn("Failed to autosave profile for player", userId, err)
                            end)
                        end
                    end
                end)

                maid:Add(function ()
                    task.cancel(autoSave)
                end)
            end)

            maid:Add(function ()
                if userId and cache[userId] then
                    cache[userId] = nil
                end
                
                data.IsLoaded = false
                data.Loaded:DisconnectAll()
                data.Updated:DisconnectAll()
            end)

            cache[userId] = data
        end

        return cache[userId]
    else
        local data: PlayerData<T> = self._dataCache[userId]
        local player = Players.LocalPlayer or nil

        if not data then
            data = setmetatable({
                CurrentData = DeltaTable.DeepCopy(default),
                _server = self,
                
                HasPendingChanges = false,
                Updated = Signal.new(),

                Owner = userId,
                IsMock = isMock,
                Player = player,

                IsLoaded = false,
                Loaded = Signal.new(),

                _maid = Trove.new(),
            }, PlayerData)

            self._dataCache[userId] = data
        end

        return data
    end
end

--- ```luau
--- -------------------------------------------------------------------------
---   EasyStore:Load<T>(
---       userId: number?
---   ) -> Promise<PlayerData<T>, string>
--- -------------------------------------------------------------------------
--- ```
---
--- Returns a promise that resolves when the player's data has been loaded.
--- * See `PlayerData.Get` for more information about the PlayerData object.
--- * If the data is already loaded, the promise will resolve immediately.
--- * If the data is not loaded, the promise will resolve when the data is loaded.
--- @return `Promise<PlayerData<T>, string>` A promise that resolves when the player's data has been loaded.
function EasyStore.Load<T>(self: Class<T>, userId: number?): Promise
    local data = self:Get(userId)

    return Promise.new(function (resolve, reject)
        if data.IsLoaded then
            task.defer(resolve, data)
        else
            data.Loaded:Once(function ()
                if data.IsLoaded then
                    task.defer(resolve, data)
                elseif reject then
                    warn("DataStore:Load failed for player", userId)
                    reject(data)
                end
            end)
        end
    end)
end

---
--- ```luau
--- -----------------------------------------------------
--- PlayerData:Patch<T>(
---     patchFunc: (edit: T) -> ()
--- ) -> Promise<(), string>
--- -----------------------------------------------------
--- ```
---
--- **[!! Server Only !!]** Performs a patch operation on the player's data.
--- * The patch function will receive a copy of the player's data to make changes to.
--- * If the patch function executes successfully, those changes will be applied to the player's data.
--- * The changes will be replicated to the client and the `Updated` signal will be fired with each change made.
--- @param patch The function to execute on a snapshot of the player's data.
--- @return `Promise<(), string>` A promise that resolves when the patch operation is complete and rejects with an error message if something went wrong.
function PlayerData.Patch<T>(self: PlayerData<T>, patchFunc: (edit: T) -> ()): Promise
    return Promise.new(function (resolve, reject)
        if not (RunContext.IsServer or RunContext.IsEdit) then
            reject("PlayerData.Patch can only be called on the server")
            return
        end

        if not self.IsLoaded then
            reject("PlayerData not loaded!")
            return
        end

        local copy = DeltaTable.DeepCopy(self.CurrentData)
        patchFunc(copy)

        local changes, count = DeltaTable.Create(self.CurrentData, copy)
        local replicate = self._server._netPatch:Server()

        if count > 0 then
            if self.Player then
                replicate:Fire(self.Player, changes)
            end

            DeltaTable.Apply(self.CurrentData :: any, changes, function (path, value)
                self.Updated:Fire({
                    Path = table.concat(path, "/"),
                    Value = value,
                })
            end)

            self.HasPendingChanges = true
        end

        resolve()
    end)
end

---
--- ```luau
--- -------------------------------------------------
--- EasyStore:Read<Default>(userId: number?) -> Default?
--- -------------------------------------------------
--- ```
--- Fetches a view of the player's current data, but only if it has loaded.
--- * **The returned SaveData is immutable. Do not attempt to modify it.**
--- * !! Will return nil if the data is not loaded yet.
function EasyStore.Read<T>(self: Class<T>, userId: number?): T?
    if userId == nil or userId > 0 then
        local data = self:Get(userId)

        if data.IsLoaded then
            return data.CurrentData
        end
    end

    return nil
end

--- ```luau
--- -------------------------------------------------
--- EasyStore:PromiseRead<Default>(userId: number?) -> Promise<Default, string>
--- -------------------------------------------------
--- ```
--- Returns a promise that resolves with the player's data if it has loaded.
---
--- Will reject if the data fails to load for any reason.
function EasyStore.PromiseRead<T>(self: Class<T>, userId: number?): Promise
    return Promise.new(function (resolve, reject)
        local data = self:Get(userId)

        if data.IsLoaded then
            resolve(data.CurrentData)
        else
            data.Loaded:Once(function ()
                if data.IsLoaded then
                    resolve(data.CurrentData)
                else
                    reject("PlayerData not loaded!")
                end
            end)
        end
    end)
end

--- ```luau
--- -------------------------------------------------
--- PlayerData:Connect(path: string, callback: (value: any) -> ()) -> Signal.Connection
--- -------------------------------------------------
--- ```
--- Connects a callback to be invoked when a specific path in the player's data changes.
--- A path is a string of keys in the data table separated by slashes (`/`).
--- * For example, to listen for changes to `CurrentData.Inventory.Gold`, the path would be `"Inventory/Gold"`.
--- * The callback will be invoked with the new value at that path whenever it changes.
--- @param path The path to listen for changes on.
--- @param callback The function to invoke when the value at the specified path changes.
--- @return A `Signal.Connection` that can be used to disconnect the callback.
function PlayerData.Connect<T>(self: PlayerData<T>, path: string, callback: (value: any) -> ()): Signal.Connection
    local myPath = string.lower(path)

    local conn = self.Updated:Connect(function (patch)
        local path = patch.Path:lower()

        if path == myPath then
            callback(patch.Value)
        end
    end)

    local maid = self._maid
    maid:Add(conn)

    return conn
end

--- ```luau
--- -------------------------------------------------
--- PlayerData:IsActive() -> boolean
--- -------------------------------------------------
--- ```
--- Returns true if the player's data is available to be modified on the server.
function PlayerData.IsActive(self: PlayerData): boolean
    local owner = self.Owner
    
    if not self.IsMock then
        local player = Players:GetPlayerByUserId(owner)
        return player ~= nil or RunContext.IsEdit
    end

    return false
end

--- ```luau
--- -------------------------------------------------
--- PlayerData:GetOwner() -> Player?
--- -------------------------------------------------
--- ```
--- Returns the `Player` instance associated with this data profile, if they are in-game.
---
function PlayerData.GetOwner(self: PlayerData): Player?
    if RunContext.IsEdit then
        return Players.LocalPlayer
    else
        local owner = self.Owner

        if owner then
            return Players:GetPlayerByUserId(owner)
        end
    end

    return nil
end

--- ```luau
--- -------------------------------------------------
--- PlayerData:Release(force: boolean?) -> boolean
--- -------------------------------------------------
--- ```
--- Releases the player's data profile, saving it if necessary.
--- * If the player's data is active (the player is in-game), and `force` is not set to true, the release will fail and return false.
--- * If the player's data is not active, or `force` is true, the profile will be released and the function will return true.
--- @param force Whether to forcefully release the profile even if it is active. Defaults to false.
--- @return `boolean` Whether the profile was successfully released.
function PlayerData.Release(self: PlayerData, force: boolean?): boolean
    if self:IsActive() then
        local player = self.Player

        if player and player:IsDescendantOf(game) then
            if force then
                player:Kick("Your game session was deactivated. Please rejoin!")
            else
                warn("Cannot release active profile for player", player.UserId)
                return false
            end
        end
    end

    free(self)
    return true
end

--- ```luau
--- -------------------------------------------------
--- EasyStore:GetDataStore() -> DataStore
--- -------------------------------------------------
--- ```
--- **[!! Server Only !!]** Gets the DataStore object used by this EasyStore instance.
--- * Will error if called on the client.
--- @return `DataStore` The DataStore object used by this EasyStore instance.
function EasyStore.GetDataStore(self: Class): DataStore
    if RunContext.IsServer or RunContext.IsEdit then
        local dataStoreService = assert(self._dataStoreService)
        return dataStoreService:GetDataStore(self._dataStoreName)
    end

    error("DataStore is not available on the client!")
end

--- ```luau
--- -------------------------------------------------
--- EasyStore:Start() -> Trove
--- -------------------------------------------------
--- ```
--- Starts the DataStore. Sets up player added/removed handlers on the server, and network event handlers on the client.
--- Returns a `Trove` that can be used to clean up the DataStore if ever necessary.
--- @return `Trove` A maid that can be used to clean up the DataStore.
function EasyStore.Start<T>(self: Class<T>): Trove
    if self._maid then
        return self._maid
    end

    local maid = Trove.new()
    self._maid = maid

    if RunContext.IsServer then
        local init = self._netInit:Server()
        local request = self._netRequest:Server()

        local function sendInit(player: Player)
            EasyStore.Load(self, player.UserId):andThen(function (plrData: PlayerData<T>)
                local data = DeltaTable.DeepCopy(plrData.CurrentData)
                init:Fire(player, data)
            end)
        end

        request:On(function (player: Player)
            sendInit(player)
        end)

        local function onPlayerAdded(player: Player)
            sendInit(player)
        end

        local function onPlayerRemoving(player: Player)
            local userId = UserId.Get(player)
            local data: PlayerData<T> = self._dataCache[userId]

            if data then
                data:Save()
                free(data :: any)
            end
        end

        maid:Connect(Players.PlayerAdded, onPlayerAdded)
        maid:Connect(Players.PlayerRemoving, onPlayerRemoving)

        for i, player in Players:GetPlayers() do
            onPlayerAdded(player)
        end

        local dead = false

        maid:Add(function ()
            dead = true
        end)

        game:BindToClose(function ()
            if dead then
                return
            end

            local promises = {}

            for userId, data in pairs(self._dataCache) do
                local promise = data:Save(true)
                    :andThen(function ()
                        free(data)
                    end)

                table.insert(promises, promise)
            end

            local all = Promise.all(promises)
            all:expect()
        end)
    else
        local init = self._netInit:Client()
        local patch = self._netPatch:Client()
        local request = self._netRequest:Client()
        local myData = self:Get()

        init:On(function (data: LazyTable)
            myData.CurrentData = data :: any
            myData.Loaded:FireDeferred(true)
            myData.IsLoaded = true
        end)

        patch:On(function (patch: LazyTable)
            local myData = self:Get()

            DeltaTable.Apply(myData.CurrentData :: any, patch, function (path, value)
                myData.Updated:FireDeferred({
                    Path = table.concat(path, "/"),
                    Value = value,
                })
            end)
        end)

        task.spawn(function ()
            local attempts = 0
            local maxAttempts = 20

            while not myData.IsLoaded and attempts < maxAttempts do
                attempts += 1
                request:Fire()
                task.wait(0.5)
            end
        end)
    end

    return maid
end

--- ```luau
--- ------------------------------------------------
--- EasyStore.Create<Default>(
---     storeName: string, 
---     default: Default,
---     config: {
---         MockDataStoreService: DataStoreService?,
---         AutoSaveInterval: number?,
---         AllowMockSave: boolean?,
---     }?
--- ) -> Class<Default>
--- -------------------------------------------------
--- ```
--- Creates a new EasyStore instance using the specified `DataStore` name, provided default data structure, and optional configuration.
--- * Make sure to call `EasyStore:Start()` on the returned instance to initialize it!
--- @param storeName The name of the `DataStore` to use.
--- @param default A dictionary describing the default data structure for new players, and the general type shape of the data through Luau's type system.
--- @param config Optional configuration for the EasyStore instance.
--- @param config.MockDataStoreService An optional mock `DataStoreService` to use instead of the real one. Defaults to `game:GetService("DataStoreService")`.
--- @param config.AutoSaveInterval The interval in seconds, at which to autosave player data. Defaults to 15 seconds.
local function create<Default>(storeName: string, default: Default, config: Config?): Class<Default>
    local dataStoreService = (config and config.MockDataStoreService) or DataStoreService

    local netInit = Network.ReliableEvent(`DataStore_{storeName}_DataInit`, function (data: unknown): LazyTable
        assert(type(data) == "table")
        return data :: LazyTable
    end)

    local netPatch = Network.ReliableEvent(`DataStore_{storeName}_DataPatch`, function (patch: unknown): LazyTable
        assert(type(patch) == "table")
        return patch :: LazyTable
    end)

    local netRequest = Network.ReliableEvent(`DataStore_{storeName}_DataRequest`)

    local store = setmetatable({
        Default = default,

        _dataCache = {},
        _viewCache = {},

        _netInit = netInit,
        _netPatch = netPatch,
        _netRequest = netRequest,
        _allowMockSave = config and config.AllowMockSave or false,

        _dataStoreName = storeName,
        _dataStoreService = dataStoreService,
        _autoSaveInterval = (config and config.AutoSaveInterval) or 15,
    }, EasyStore) :: Class

    return store
end

return table.freeze({
    Create = create,
})