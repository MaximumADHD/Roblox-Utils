--!strict
local Shared = script.Parent

local RunContext = require(Shared.RunContext)
local Players = game:GetService("Players")

local Events = script.Events
local Functions = script.Functions

local EventClient = require(Events.Client)
local EventServer = require(Events.Server)

local FunctionClient = require(Functions.Client)
local FunctionServer = require(Functions.Server)

local Types = require(script.Types)
type EventClient<T... = ...any> = EventClient.Class<T...>
type EventServer<T... = ...any> = EventServer.Class<T...>

type FunctionClient<Args... = ...any, Rets... = ...any> = FunctionClient.Class<Args..., Rets...>
type FunctionServer<Args... = ...any, Rets... = ...any> = FunctionServer.Class<Args..., Rets...>

type EventOptions = Types.EventOptions
type Validator<T...> = Types.Validator<T...>

local Remotes = require(script.Remotes)
local ReliableEvent = Remotes.ReliableEvent
local RemoteFunction = Remotes.RemoteFunction
local UnreliableEvent = Remotes.UnreliableEvent

local Event = {}
Event.__index = Event

local Function = {}
Function.__index = Function

export type Event<T... = ...any> = typeof(setmetatable({} :: {
    Id: string,
    Reliable: boolean,

    _server: EventServer<T...>?,
    _client: EventClient<T...>?,
}, Event))

export type Function<Args... = ...any, Rets... = ...any> = typeof(setmetatable({} :: {
    Id: string,
    _server: FunctionServer<Args..., Rets...>?,
    _client: FunctionClient<Args..., Rets...>?,
}, Function))

export type Class<T... = ...any> = Event<T...>

local EVENT_INDEX = {} :: {
    [string]: Event
}

local FUNC_INDEX = {} :: {
    [string]: Function
}

function Event.Server<T...>(self: Event<T...>): EventServer<T...>
    return assert(self._server, "Server events can only be accessed from the server!")
end

function Event.Client<T...>(self: Event<T...>): EventClient<T...>
    return assert(self._client, "Client events can only be accessed from the client!")
end

function Function.Server<Args..., Rets...>(self: Function<Args..., Rets...>): FunctionServer<Args..., Rets...>
    return assert(self._server, "Server functions can only be accessed from the server!")
end

function Function.Client<Args..., Rets...>(self: Function<Args..., Rets...>): FunctionClient<Args..., Rets...>
    return assert(self._client, "Client functions can only be accessed from the client!")
end

local noop: Validator<...any> = function (...: unknown): ...unknown
    return ...
end

local function newEventImpl<T...>(id: string | EventOptions, validate: Validator<T...>): Event<T...>
    local name, reliable

    if type(id) == "string" then
        name = id
        reliable = true
    else
        local flags = id :: {
            Reliable: boolean?,
            Unreliable: boolean?,
        }

        name = id.Name

        if flags.Reliable ~= nil then
            reliable = flags.Reliable
        elseif flags.Unreliable ~= nil then
            reliable = not flags.Unreliable
        else
            reliable = true
        end
    end

    assert(name, "Event name must be provided!")
    assert(validate, "Event validator must be provided!")

    local event: Event<T...> = setmetatable({
        Id = name,
        Reliable = reliable,

        _client = nil :: EventClient<T...>?,
        _server = nil :: EventServer<T...>?,
    }, Event)
    
    if EVENT_INDEX[name] then
        error(`Event with name {name} already exists!`)
    end
    
    EVENT_INDEX[name] = event :: Event?

    if RunContext.IsEdit then
        local server = EventServer.new(name, validate)
        local client = EventClient.new(name, validate)

        server.Dispatch:Connect(function (player: Player, ...: any)
            if pcall(validate, ...) then
                if client.Receiver then
                    client.Receiver(...)
                end
            end
        end)

        client.Dispatch:Connect(function (...: any)
            if pcall(validate, ...) then
                local player = Players.LocalPlayer

                if player and server.Receiver then
                    server.Receiver(player, ...)
                end
            end
        end)

        event._server = server
        event._client = client
    elseif RunContext.IsServer then
        local server = EventServer.new(name, validate)

        server.Dispatch:Connect(function (player: Player, ...: any)
            if pcall(validate, ...) then
                if reliable then
                    ReliableEvent:FireClient(player, name, ...)
                else
                    UnreliableEvent:FireClient(player, name, ...)
                end
            end
        end)
        
        event._server = server
    elseif RunContext.IsClient then
        local client = EventClient.new(name, validate)

        client.Dispatch:Connect(function (...: any)
            if pcall(validate, ...) then
                if reliable then
                    ReliableEvent:FireServer(name, ...)
                else
                    UnreliableEvent:FireServer(name, ...)
                end
            end
        end)

        event._client = client
    end

    return event
end

local function newFunction<Args..., Rets...>(id: string, validateArgs: Validator<Args...>, validateRets: Validator<Rets...>): Function<Args..., Rets...>
    local func: Function<Args..., Rets...> = setmetatable({
        Id = id,

        ValidateArgs = validateArgs,
        ValidateRets = validateRets,

        _client = nil :: FunctionClient<Args..., Rets...>?,
        _server = nil :: FunctionServer<Args..., Rets...>?,
    }, Function)

    FUNC_INDEX[id] = func :: Function?

    if RunContext.IsEdit then
        local server = FunctionServer.new(id, validateArgs, validateRets)
        local client = FunctionClient.new(id, validateArgs, validateRets)

        server.OnInvoke = function (player: Player, ...: Args...): Rets...
            local clientImpl = assert(client.Callback, "Client implementation not ready!")
            return clientImpl(...)
        end

        client.OnInvoke = function (...: Args...): Rets...
            local player = assert(Players.LocalPlayer, "No local player! Make sure this is running in Team Create!")
            local serverImpl = assert(server.Callback, "Server implementation not ready!")
            return serverImpl(player, ...)
        end

        func._server = server
        func._client = client
    elseif RunContext.IsServer then
        local server = FunctionServer.new(id, validateArgs, validateRets)

        server.OnInvoke = function (player: Player, ...: Args...): Rets...
            return validateRets(RemoteFunction:InvokeClient(player, id, validateArgs(...)))
        end

        func._server = server
    elseif RunContext.IsClient then
        local client = FunctionClient.new(id, validateArgs, validateRets)

        client.OnInvoke = function (...: Args...): Rets...
            return validateRets(RemoteFunction:InvokeServer(id, validateArgs(...)))
        end

        func._client = client
    end
    
    return func
end

local function newReliableEventImpl<T...>(name: string, maybeValidate: Validator<T...>?): Event<T...>
    local options = {
        Name = name,
        Reliable = true
    }
    
    return newEventImpl(
        options :: EventOptions,
        maybeValidate or noop :: Validator<T...>
    )
end

local function newUnreliableEventImpl<T...>(name: string, maybeValidate: Validator<T...>?): Event<T...>
    local options = {
        Name = name,
        Unreliable = true
    }
    
    return newEventImpl(
        options :: EventOptions,
        maybeValidate or noop :: Validator<T...>
    )
end

local function newFuncImpl<Args..., Rets...>(
    name: string, 
    maybeValidateArgs: Validator<Args...>?,
    maybeValidateRets: Validator<Rets...>?
): Function<Args..., Rets...>
    local validateArgs = maybeValidateArgs or noop :: Validator<Args...>
    local validateRets = maybeValidateRets or noop :: Validator<Rets...>
    return newFunction(name, validateArgs, validateRets)
end

local newEvent = newEventImpl ::
    & ((name: string) -> Event<...unknown>)
    & ((options: EventOptions) -> Event<...unknown>)
    & (<T...>(name: string, validate: Validator<T...>) -> Event<T...>)
    & (<T...>(options: EventOptions, validate: Validator<T...>) -> Event<T...>)

local newReliableEvent = newReliableEventImpl ::
    & ((name: string) -> Event<...unknown>)
    & (<T...>(name: string, validate: Validator<T...>) -> Event<T...>)

local newUnreliableEvent = newUnreliableEventImpl :: 
    & ((name: string) -> Event<...unknown>)
    & (<T...>(name: string, validate: Validator<T...>) -> Event<T...>)

local newFunc = newFuncImpl ::
    & ((name: string) -> Function<...unknown, ...unknown>)
    & (<Args...>(name: string, validateArgs: Validator<Args...>) -> Function<Args..., ...unknown>)
    & (<Rets...>(name: string, validateArgs: nil, validateRets: Validator<Rets...>) -> Function<(), Rets...>)
    & (<Args..., Rets...>(name: string, validateArgs: Validator<Args...>, validateRets: Validator<Rets...>) -> Function<Args..., Rets...>)

local function createEventReceiver<T...>(reliable: boolean, nameIndex: number, consumer: (Event, T...) -> ())
    return function (...)
        local args = { ... }
        local eventName = table.remove(args, nameIndex)
        local event = eventName and EVENT_INDEX[eventName]

        if event and event.Reliable == reliable then
            consumer(event, table.unpack(args))
        end
    end
end

if RunContext.IsServer then
    local function onServerReceive(event: Event, player: Player, ...: any)
        local server = event:Server()

        if server.Receiver then
            server.Receiver(player, ...)
        end
    end
    
    RemoteFunction.OnServerInvoke = function (player: Player, id: string, ...: any)
        local func = FUNC_INDEX[id]
        local server = func:Server()
        return server:Call(player,...)
    end

    UnreliableEvent.OnServerEvent:Connect(createEventReceiver(false, 2, onServerReceive))
    ReliableEvent.OnServerEvent:Connect(createEventReceiver(true, 2, onServerReceive))
elseif RunContext.IsClient then
    local function onClientReceive(event: Event, ...: any)
        local client = event:Client()

        if client.Receiver then
            client.Receiver(...)
        end
    end

    RemoteFunction.OnClientInvoke = function (id: string, ...: any)
        local func = FUNC_INDEX[id]
        local client = func:Client()
        return client:Call(...)
    end

    UnreliableEvent.OnClientEvent:Connect(createEventReceiver(false, 1, onClientReceive))
    ReliableEvent.OnClientEvent:Connect(createEventReceiver(true, 1, onClientReceive))
end

return table.freeze({
    Event = newEvent,
    Function = newFunc,
    ReliableEvent = newReliableEvent,
    UnreliableEvent = newUnreliableEvent,
})