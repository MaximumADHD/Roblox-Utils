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
local Network = require(Shared.Network)
local Promise = require(Shared.Promise)
local DeltaTable = require(Shared.DeltaTable)
local RunContext = require(Shared.RunContext)

export type Config = {
    MockDataStoreService: DataStoreService?,
    AutoSaveInterval: number?,
}

type ClassInternal<T = any> = typeof(setmetatable({} :: {
    Default: T,

    _dataCache: {
        [number]: any,
    },

    _viewCache: {
        [number]: any,
    },

    _maid: Trove?,
    _autoSaveInterval: number,

    _netInit: Network.Class<LazyTable>,
    _netPatch: Network.Class<LazyTable>,

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

type PlayerDataInternal<T = any> = typeof(setmetatable({} :: {
    CurrentData: T,
    Server: ClassInternal<T>,

    Owner: Player?,
    Maid: Trove,

    IsLoaded: boolean,
    Updated: Signal<Patch>,
    Loaded: Signal<boolean>,
    HasPendingChanges: boolean,
}, PlayerData))


local function getProfileKey(userId: number)
    return `{userId}`
end

local function free(data: PlayerDataInternal)
    if data.Maid then
        data.Maid:Clean()
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

function PlayerData.Save<T>(self: PlayerDataInternal<T>): Promise
    return Promise.new(function (resolve, reject)
        if not self.IsLoaded then
            reject("PlayerData not loaded!")
            return
        end

        if not (RunContext.IsServer or RunContext.IsEdit) then
            reject("PlayerData.Save can only be called on the server")
            return
        end

        if not self:IsActive() then
            reject("PlayerData is read-only!")
            return
        end

        local owner = self.Owner

        if not owner then
            if RunContext.IsEdit then
                local StudioService = game:GetService("StudioService")

                owner = {
                    UserId = StudioService:GetUserId(),
                } :: any
            else
                reject("PlayerData has no owner!")
                return
            end
        end
        
        local dataStore = self.Server:GetDataStore()
        local key = getProfileKey(assert(owner).UserId)
        
        dataStore:UpdateAsync(key, function (oldData)
            return self.CurrentData
        end)
        
        resolve()
    end)
end

function EasyStore.Get<T>(self: ClassInternal<T>, userId: number?): PlayerDataInternal<T>
    local default = self.Default

    if RunContext.IsServer or RunContext.IsEdit then
        if RunContext.IsEdit and userId == nil then
            local StudioService = game:GetService("StudioService")
            userId = StudioService:GetUserId()
        end

        assert(userId, "EasyStore:Get must be called with a userId on the server")

        local player = (RunContext.IsServer or RunContext.IsEdit) and Players:GetPlayerByUserId(userId) or nil
        local cache: { PlayerDataInternal<T> } = if player then self._dataCache else self._viewCache

        if not cache[userId] then
            local key = getProfileKey(userId)
            local maid = Trove.new()

            local data: PlayerDataInternal<T> = setmetatable({
                CurrentData = DeltaTable.DeepCopy(default),
                Server = self,

                HasPendingChanges = false,
                IsLoaded = false,
                Owner = player,

                Updated = Signal.new(),
                Loaded = Signal.new(),
                Maid = maid,
            }, PlayerData)

            task.spawn(function ()
                local RETRY_COUNT = 5
                local store = self:GetDataStore()

                for retry = 1, RETRY_COUNT do
                    local success, currentData = xpcall(function ()
                        return store:GetAsync(key)
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
                            reconcileTable(currentData, default :: any)
                            data.CurrentData = currentData
                            
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
                cache[userId] = nil
                data.IsLoaded = false

                data.Loaded:DisconnectAll()
                data.Updated:DisconnectAll()
            end)

            cache[userId] = data
        end

        return cache[userId]
    else
        local myPlayer
        local myUserId

        if RunContext.IsEdit then
            local StudioService = game:GetService("StudioService")
            myUserId = StudioService:GetUserId()
        else
            myPlayer = assert(Players.LocalPlayer)
            myUserId = myPlayer.UserId
        end

        local data: PlayerDataInternal<T> = self._dataCache[myUserId]

        if not data then
            data = setmetatable({
                CurrentData = DeltaTable.DeepCopy(default),
                Server = self,
                
                HasPendingChanges = false,
                Updated = Signal.new(),
                Owner = myPlayer,

                IsLoaded = false,
                Loaded = Signal.new(),

                Maid = Trove.new(),
            }, PlayerData)

            self._dataCache[myUserId] = data
        end

        return data
    end
end

function EasyStore.Load<T>(self: ClassInternal<T>, userId: number?): Promise
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

function PlayerData.Patch<T>(self: PlayerDataInternal<T>, patchFunc: (edit: T) -> ()): Promise
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
        local replicate = self.Server._netPatch:Server()

        if count > 0 then
            if self.Owner then
                replicate:Fire(self.Owner, changes)
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

function EasyStore.Read<T>(self: ClassInternal<T>, userId: number?): T?
    if userId == nil or userId > 0 then
        local data = self:Get(userId)

        if data.IsLoaded then
            return data.CurrentData
        end
    end

    return nil
end

function EasyStore.PromiseRead<T>(self: ClassInternal<T>, userId: number?): Promise
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

function PlayerData.Connect(self: PlayerDataInternal, path: string, callback: (value: any) -> ()): Signal.Connection
    local myPath = path:lower()

    local conn = self.Updated:Connect(function (patch)
        local path = patch.Path:lower()

        if path == myPath then
            callback(patch.Value)
        end
    end)

    local maid = self.Maid
    maid:Add(conn)

    return conn
end

function PlayerData.IsActive(self: PlayerDataInternal): boolean
    return self.Owner ~= nil or RunContext.IsEdit
end

function PlayerData.Release(self: PlayerDataInternal, force: boolean?): boolean
    if self:IsActive() then
        local owner = self.Owner

        if owner and owner:IsDescendantOf(game) then
            if force then
                owner:Kick("Your game session was deactivated. Please rejoin!")
            else
                warn("Cannot release active profile for player", owner.UserId)
                return false
            end
        end
    end

    free(self)
    return true
end

function EasyStore.GetDataStore(self: ClassInternal): DataStore
    if RunContext.IsServer or RunContext.IsEdit then
        local dataStoreService = assert(self._dataStoreService)
        return dataStoreService:GetDataStore(self._dataStoreName)
    end

    error("DataStore is not available on the client!")
end

function EasyStore.Start<T>(self: ClassInternal<T>): Trove
    if self._maid then
        return self._maid
    end

    local maid = Trove.new()
    self._maid = maid

    if RunContext.IsServer then
        local init = self._netInit:Server()

        local function onPlayerAdded(player: Player)
            EasyStore.Load(self, player.UserId):andThen(function (plrData: PlayerDataInternal<T>)
                local data = DeltaTable.DeepCopy(plrData.CurrentData)
                init:Fire(player, data)
            end)

            self:Load(player.UserId)
        end

        local function onPlayerRemoving(player: Player)
            local data: PlayerDataInternal<T> = self._dataCache[player.UserId]

            if data then
                data:Save()
                free(data)
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
                local promise = data:Save()
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

        init:On(function (data: LazyTable)
            local myData = self:Get()
            myData.CurrentData = data :: any

            myData.IsLoaded = true
            myData.Loaded:Fire(true)
        end)

        patch:On(function (patch: LazyTable)
            local myData = self:Get()

            DeltaTable.Apply(myData.CurrentData :: any, patch, function (path, value)
                myData.Updated:Fire({
                    Path = table.concat(path, "/"),
                    Value = value,
                })
            end)
        end)
    end

    return maid
end

local function create<TEMPLATE>(storeName: string, default: TEMPLATE, config: Config?): ClassInternal<TEMPLATE>
    local dataStoreService = (config and config.MockDataStoreService) or DataStoreService

    local netInit = Network.Event(`DataStore_{storeName}_DataInit`, function (data: unknown): LazyTable
        assert(type(data) == "table")
        return data :: LazyTable
    end)

    local netPatch = Network.Event(`DataStore_{storeName}_DataPatch`, function (patch: unknown): LazyTable
        assert(type(patch) == "table")
        return patch :: LazyTable
    end)

    local store = setmetatable({
        Default = default,

        _dataCache = {},
        _viewCache = {},

        _netInit = netInit :: any,
        _netPatch = netPatch :: any,

        _dataStoreName = storeName,
        _dataStoreService = dataStoreService,
        _autoSaveInterval = (config and config.AutoSaveInterval) or 15,
    }, EasyStore)

    return store
end

--------------------------------------------------------------------------------------------------------------------------------------------
-- PUBLIC EXPORTS
-- !! FIXME: Use proper metatable types when Luau is more stable with generics.
--------------------------------------------------------------------------------------------------------------------------------------------

--- Represents a player's data profile in EasyStore.
export type PlayerData<SaveData = any> = {
    --- The current state of the player's data. This is immutable and should only be modified through `PlayerData:Patch` on the server.
    CurrentData: SaveData,

    --- The `Player` who owns this data profile.
    Owner: Player?,

    --- Flag indicating whether the player's data has finished loading.
    IsLoaded: boolean,

    --- Flag indicating whether there are unsaved changes to the player's data and a save is pending.
    HasPendingChanges: boolean,

    --- **[Server-Only]** Forces the player's data to be saved now.
    --- * If the player's data is not loaded, the promise will reject.
    --- * If the player's data is loaded, the promise will resolve when the data has been saved.
    --- * If called on the client, the promise will reject.
    --- @return A `Promise` that resolves when the player's data has been saved and rejects with an error message if something went wrong.
    Save: (self: PlayerData<SaveData>) -> Promise,

    --- **[!! Server Only !!]** Performs a patch operation on the player's data.
    --- * The patch function will receive a copy of the player's data to make changes to.
    --- * If the patch function executes successfully, those changes will be applied to the player's data.
    --- * The changes will be replicated to the client and the `Updated` signal will be fired with each change made.
    --- @param patch The function to execute on a snapshot of the player's data.
    --- @return `Promise<(), string>` A promise that resolves when the patch operation is complete and rejects with an error message if something went wrong.
    Patch: (self: PlayerData<SaveData>, patchFunc: (edit: SaveData) -> ()) -> Promise,

    --- Connects a callback to be invoked when a specific path in the player's data changes.
    --- A path is a string of keys in the data table separated by slashes (`/`).
    --- * For example, to listen for changes to `CurrentData.Inventory.Gold`, the path would be `"Inventory/Gold"`.
    --- * The callback will be invoked with the new value at that path whenever it changes.
    --- @param path The path to listen for changes on.
    --- @param callback The function to invoke when the value at the specified path changes.
    --- @return A `Signal.Connection` that can be used to disconnect the callback.
    Connect: (self: PlayerData<SaveData>, path: string, callback: (value: any) -> ()) -> Signal.Connection,
    
    --- Returns true if the player's data is available to be modified on the server.
    IsActive: (self: PlayerData<SaveData>) -> boolean,

    --- Releases the player's data profile, saving it if necessary.
    --- * If the player's data is active (the player is in-game), and `force` is not set to true, the release will fail and return false.
    --- * If the player's data is not active, or `force` is true, the profile will be released and the function will return true.
    --- @param force Whether to forcefully release the profile even if it is active. Defaults to false.
    --- @return `boolean` Whether the profile was successfully released.
    Release: (self: PlayerData<SaveData>, force: boolean?) -> boolean,
}

--- Represents an EasyStore instance for managing player data.
--- Can exist on the server, client, or in edit mode.
--- Use `EasyStore.Create` to create a new instance.
export type Class<SaveData = any> = {
    --- Gets a `PlayerData` object for the specified player **immediately**.
    --- * **It may not be immediately ready for use!** Use `PlayerData.Load` to wait for the data to be loaded through a `Promise`
    ---   * Check the `IsLoaded` property to see if the data is ready, and/or listen against the `Loaded` signal.
    --- * The data is read-only on the client, and on the server when the player is not in-game.
    ---   * It *can* be modified on the server if the player is in-game, or in edit mode if it belongs to the studio user.
    ---   * Modifications from the server will be propagated over to the client.
    --- * If called on the client or in edit mode, it will return the data for the local user (the `userId` is ignored)
    --- * If called on the server, the `userId` argument is **required** and the data for the specified player will be returned.
    --- @param userId The userId of the player to get data for. Ignored on the client and in edit mode.
    Get: (self: Class<SaveData>, userId: number?) -> PlayerData<SaveData>,

    --- Returns a promise that resolves when the player's data has been loaded.
    --- * See `PlayerData.Get` for more information about the PlayerData object.
    --- * If the data is already loaded, the promise will resolve immediately.
    --- * If the data is not loaded, the promise will resolve when the data is loaded.
    --- @return `Promise<PlayerData>` A promise that resolves when the player's data has been loaded.
    Load: (self: Class<SaveData>, userId: number?) -> Promise,

    --- Fetches a view of the player's current data, but only if it has loaded.
    --- * **The returned SaveData is immutable. Do not attempt to modify it.**
    --- * !! Will return nil if the data is not loaded yet.
    Read: (self: Class<SaveData>, userId: number?) -> SaveData?,

    --- Returns a promise that resolves with the player's data if it has loaded.
    --- Will reject if the data fails to load for any reason.
    PromiseRead: (self: Class<SaveData>, userId: number?) -> Promise,

    --- **[!! Server Only !!]** Gets the DataStore object used by this EasyStore instance.
    --- * Will error if called on the client.
    --- @return `DataStore` The DataStore object used by this EasyStore instance.
    GetDataStore: (self: Class<SaveData>) -> DataStore,
    
    --- Starts the DataStore. Sets up player added/removed handlers on the server, and network event handlers on the client.
    --- Returns a `Trove` that can be used to clean up the DataStore if ever necessary.
    --- @return `Trove` A maid that can be used to clean up the DataStore.
    Start: (self: Class<SaveData>) -> Trove,

    --- The default data structure used for new players.
    Default: SaveData,
}

--- Main EasyStore module for managing player data with Roblox DataStores.
export type EasyStore = {
    --- Creates a new EasyStore instance using the specified DataStore name, provided default data structure, and optional configuration.
    --- * Make sure to call `EasyStore:Start()` on the returned instance to initialize it!
    --- @param storeName The name of the DataStore to use.
    --- @param default A dictionary describing the default data structure for new players, and the general type shape of the data through Luau's type system.
    --- @param config Optional configuration for the EasyStore instance.
    --- @param config.MockDataStoreService An optional mock DataStoreService to use instead of the real one. Defaults to `game:GetService("DataStoreService")`.
    --- @param config.AutoSaveInterval The interval, in seconds, at which to autosave player data. Defaults to 15 seconds.
    Create: <TEMPLATE>(storeName: string, default: TEMPLATE, config: Config?) -> Class<TEMPLATE>,
}

--------------------------------------------------------------------------------------------------------------------------------------------

local result: EasyStore = table.freeze({
    Create = create,
}) :: any

return result