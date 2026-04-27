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

export type Class<T = any> = setmetatable<{
    Default: T,

    _dataCache: {
        [number]: PlayerData<T>,
    },

    _viewCache: {
        [number]: PlayerData<T>,
    },

    _maid: Trove?,
    _autoSaveInterval: number,

    _netInit: Network.Class<LazyTable>,
    _netPatch: Network.Class<LazyTable>,

    _dataStoreService: DataStoreService?,
    _dataStoreName: string,
}, typeof(EasyStore)>

type Trove = Trove.Trove
type Promise = Promise.Class
type LazyTable = DeltaTable.LazyTable
type Signal<T...> = Signal.Signal<T...>
type NetEvent<T...> = Network.Class<T...>

export type Patch = {
    Path: string,
    Value: any,
}

type PlayerData<T = any> = setmetatable<{
    CurrentData: T,
    Server: Class<T>,

    Owner: Player?,
    Maid: Trove,

    IsLoaded: boolean,
    Updated: Signal<Patch>,
    Loaded: Signal<boolean>,
    HasPendingChanges: boolean,
}, typeof(PlayerData)>

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

function EasyStore.Get<T>(self: Class<T>, userId: number?): PlayerData<T>
    local default = self.Default

    if RunContext.IsServer or RunContext.IsEdit then
        if RunContext.IsEdit and userId == nil then
            local StudioService = game:GetService("StudioService")
            userId = StudioService:GetUserId()
        end

        assert(userId, "EasyStore:Get must be called with a userId on the server")

        local player = (RunContext.IsServer or RunContext.IsEdit) and Players:GetPlayerByUserId(userId) or nil
        local cache = if player then self._dataCache else self._viewCache

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
                    local success, currentData: any = xpcall(function ()
                        return store:GetAsync(key)
                    end, function (err)
                        warn("!! Error while loading profile for player", userId, err, debug.traceback())
                    end)

                    if success then
                        if currentData == nil then
                            currentData = DeltaTable.DeepCopy(default)
                        end

                        if rawget(currentData, "RobloxMetaData") ~= nil and not rawget(default, "RobloxMetaData") then
                            -- ProfileService holdover, use the Data key.
                            currentData = rawget(currentData, "Data")
                        end

                        if currentData then
                            reconcileTable(currentData, default)
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
                if userId then
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
        local myPlayer
        local myUserId

        if RunContext.IsEdit then
            local StudioService = game:GetService("StudioService")
            myUserId = StudioService:GetUserId()
        else
            myPlayer = assert(Players.LocalPlayer)
            myUserId = myPlayer.UserId
        end

        local data = self._dataCache[myUserId]

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

            DeltaTable.Apply(self.CurrentData, changes, function (path, value)
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

function EasyStore.Read<T>(self: Class<T>, userId: number?): T?
    if userId == nil or userId > 0 then
        local data = self:Get(userId)

        if data.IsLoaded then
            return data.CurrentData
        end
    end

    return nil
end

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

function PlayerData.IsActive(self: PlayerData): boolean
    return self.Owner ~= nil or RunContext.IsEdit
end

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

function EasyStore.Start<T>(self: Class<T>): Trove
    if self._maid then
        return self._maid
    end

    local maid = Trove.new()
    self._maid = maid

    if RunContext.IsServer then
        local init = self._netInit:Server()

        local function onPlayerAdded(player: Player)
            EasyStore.Load(self, player.UserId):andThen(function (plrData: PlayerData<T>)
                local data = DeltaTable.DeepCopy(plrData.CurrentData)
                init:Fire(player, data)
            end)

            self:Load(player.UserId)
        end

        local function onPlayerRemoving(player: Player)
            local data: PlayerData<T> = self._dataCache[player.UserId]

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

local function create<TEMPLATE>(storeName: string, default: TEMPLATE, config: Config?): Class<TEMPLATE>
    local dataStoreService = (config and config.MockDataStoreService) or DataStoreService

    local netInit = Network.ReliableEvent(`DataStore_{storeName}_DataInit`, function (data: unknown): LazyTable
        assert(type(data) == "table")
        return data :: LazyTable
    end)

    local netPatch = Network.ReliableEvent(`DataStore_{storeName}_DataPatch`, function (patch: unknown): LazyTable
        assert(type(patch) == "table")
        return patch :: LazyTable
    end)

    local store = setmetatable({
        Default = default,

        _dataCache = {},
        _viewCache = {},

        _netInit = netInit,
        _netPatch = netPatch,

        _dataStoreName = storeName,
        _dataStoreService = dataStoreService,
        _autoSaveInterval = (config and config.AutoSaveInterval) or 15,
    }, EasyStore)

    return store :: Class<TEMPLATE>
end

--------------------------------------------------------------------------------------------------------------------------------------------

return table.freeze({
    Create = create,
})