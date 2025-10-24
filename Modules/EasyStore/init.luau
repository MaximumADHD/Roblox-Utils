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

export type Class<T = any> = typeof(setmetatable({} :: {
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

export type PlayerData<T = any> = typeof(setmetatable({} :: {
    CurrentData: T,
    Server: Class<T>,

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

local function free(data: PlayerData)
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

--- **[Server-Only]** Forces the player's data to be saved now.
--- * If the player's data is not loaded, the promise will reject.
--- * If the player's data is loaded, the promise will resolve when the data has been saved.
--- * If called on the client, the promise will reject.
--- @return A `Promise` that resolves when the player's data has been saved and rejects with an error message if something went wrong.
function PlayerData.Save<T>(self: PlayerData<T>): Promise
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

--- Gets a `PlayerData` object for the specified player **immediately**.
--- * **It may not be immediately ready for use!** Use `PlayerData.Load` to wait for the data to be loaded through a `Promise`
---   * Check the `IsLoaded` property to see if the data is ready, and/or listen against the `Loaded` signal.
--- * The data is read-only on the client, and on the server when the player is not in-game.
---   * It *can* be modified on the server if the player is in-game, or in edit mode if it belongs to the studio user.
---   * Modifications from the server will be propagated over to the client.
--- * If called on the client or in edit mode, it will return the data for the local user (the `userId` is ignored)
--- * If called on the server, the `userId` argument is **required** and the data for the specified player will be returned.
--- @param userId The userId of the player to get data for. Has no effect on the client or in edit mode.
function EasyStore.Get<T>(self: Class<T>, userId: number?): PlayerData<T>
    local default = self.Default

    if RunContext.IsServer or RunContext.IsEdit then
        if RunContext.IsEdit and userId == nil then
            local StudioService = game:GetService("StudioService")
            userId = StudioService:GetUserId()
        end

        assert(userId, "EasyStore:Get must be called with a userId on the server")

        local player = (RunContext.IsServer or RunContext.IsEdit) and Players:GetPlayerByUserId(userId) or nil
        local cache: { PlayerData<T> } = if player then self._dataCache else self._viewCache

        if not cache[userId] then
            local key = getProfileKey(userId)
            local maid = Trove.new()

            local data: PlayerData<T> = setmetatable({
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

        local data: PlayerData<T> = self._dataCache[myUserId]

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

--- Returns a promise that resolves when the player's data has been loaded.
--- * See `PlayerData.Get` for more information about the PlayerData object.
--- * If the data is already loaded, the promise will resolve immediately.
--- * If the data is not loaded, the promise will resolve when the data is loaded.
--- @return `Promise<PlayerData>` A promise that resolves when the player's data has been loaded.
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

--- Returns a promise that resolves with the player's data if it has loaded.
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

--- Connects a callback to be invoked when a specific path in the player's data changes.
--- A path is a string of keys in the data table separated by slashes (`/`).
--- * For example, to listen for changes to `CurrentData.Inventory.Gold`, the path would be `"Inventory/Gold"`.
--- * The callback will be invoked with the new value at that path whenever it changes.
--- @param path The path to listen for changes on.
--- @param callback The function to invoke when the value at the specified path changes.
--- @return A `Signal.Connection` that can be used to disconnect the callback.
function PlayerData.Connect(self: PlayerData, path: string, callback: (value: any) -> ()): Signal.Connection
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

--- Returns true if the player's data is available to be modified on the server.
function PlayerData.IsActive(self: PlayerData): boolean
    return self.Owner ~= nil or RunContext.IsEdit
end

--- Releases the player's data profile, saving it if necessary.
--- * If the player's data is active (the player is in-game), and `force` is not set to true, the release will fail and return false.
--- * If the player's data is not active, or `force` is true, the profile will be released and the function will return true.
--- @param force Whether to forcefully release the profile even if it is active. Defaults to false.
--- @return `boolean` Whether the profile was successfully released.
function PlayerData.Release(self: PlayerData, force: boolean?): boolean
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

function EasyStore.GetDataStore(self: Class): DataStore
    if RunContext.IsServer or RunContext.IsEdit then
        local dataStoreService = assert(self._dataStoreService)
        return dataStoreService:GetDataStore(self._dataStoreName)
    end

    error("DataStore is not available on the client!")
end

--- Starts the DataStore. Sets up player added/removed handlers on the server, and network event handlers on the client.
--- Returns a `Trove` that can be used to clean up the DataStore if ever necessary.
--- @return `Trove` A `Trove` that can be used to clean up the DataStore.
function EasyStore.Start(self: Class): Trove
    if self._maid then
        return self._maid
    end

    local maid = Trove.new()
    self._maid = maid

    if RunContext.IsServer then
        local init = self._netInit:Server()

        local function onPlayerAdded(player: Player)
            self:Load(player.UserId):andThen(function (plrData: PlayerData)
                local data = DeltaTable.DeepCopy(plrData.CurrentData)
                init:Fire(player, data)
            end)
        end

        local function onPlayerRemoving(player: Player)
            local data = self._dataCache[player.UserId]

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
            myData.CurrentData = data

            myData.IsLoaded = true
            myData.Loaded:Fire(true)
        end)

        patch:On(function (patch: LazyTable)
            local myData = self:Get()

            DeltaTable.Apply(myData.CurrentData, patch, function (path, value)
                myData.Updated:Fire({
                    Path = table.concat(path, "/"),
                    Value = value,
                })
            end)
        end)
    end

    return maid
end

--- Creates a new EasyStore instance using the specified DataStore name, provided default data structure, and optional configuration.
--- * Make sure to call `EasyStore:Start()` on the returned instance to initialize it!
--- @param storeName The name of the DataStore to use.
--- @param default A dictionary describing the default data structure for new players, and the general type shape of the data through Luau's type system.
--- @param config Optional configuration for the EasyStore instance.
--- @param config.MockDataStoreService An optional mock DataStoreService to use instead of the real one. Defaults to `game:GetService("DataStoreService")`.
--- @param config.AutoSaveInterval The interval, in seconds, at which to autosave player data. Defaults to 15 seconds.
local function create<TEMPLATE>(storeName: string, default: TEMPLATE, config: Config?): Class<TEMPLATE>
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

return table.freeze({
    Create = create,
})