--!strict
local Shared = script.Parent

local RunContext = require(Shared.RunContext)
local Players = game:GetService("Players")

local Client = require(script.Client)
local Server = require(script.Server)
local Types = require(script.Types)

type Client<T...> = Client.Class<T...>
type Server<T...> = Server.Class<T...>

type EventOptions = Types.EventOptions
type Validator<T...> = Types.Validator<T...>

local Remotes = require(script.Remotes)
local Unreliable = Remotes.Unreliable
local Reliable = Remotes.Reliable

local Event = {}
Event.__index = Event

export type Class<T... = ...any> = typeof(setmetatable({} :: {
    Id: string,
    Reliable: boolean,

    _server: Server<T...>?,
    _client: Client<T...>?,
}, Event))

function Event.Server<T...>(self: Class<T...>): Server<T...>
    return assert(self._server, "Server events can only be accessed from the server!")
end

function Event.Client<T...>(self: Class<T...>): Client<T...>
    return assert(self._client, "Client events can only be accessed from the client!")
end

local eventIndex = {} :: {
    [string]: Class
}

local function newEvent<T...>(id: string | EventOptions, validate: Validator<T...>): Class<T...>
    local name, reliable

    if type(id) == "string" then
        name = id
        reliable = true
    else
        name = id.Name

        if id.Reliable ~= nil then
            reliable = id.Reliable
        elseif id.Unreliable ~= nil then
            reliable = not id.Unreliable
        else
            reliable = true
        end
    end

    assert(name, "Event name must be provided!")
    assert(validate, "Event validator must be provided!")

    local event: Class<T...> = setmetatable({
        Id = name,
        Reliable = reliable,

        _client = nil :: Client<T...>?,
        _server = nil :: Server<T...>?,
    }, Event)
    
    if eventIndex[name] then
        error(`Event with name {name} already exists!`)
    end
    
    eventIndex[name] = event :: any

    if RunContext.IsEdit then
        local server = Server.new(name, validate)
        local client = Client.new(name, validate)

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
        local server = Server.new(name, validate)

        server.Dispatch:Connect(function (player: Player, ...: any)
            if pcall(validate, ...) then
                if reliable then
                    Reliable:FireClient(player, name, ...)
                else
                    Unreliable:FireClient(player, name, ...)
                end
            end
        end)
        
        event._server = server
    elseif RunContext.IsClient then
        local client = Client.new(name, validate)

        client.Dispatch:Connect(function (...: any)
            if pcall(validate, ...) then
                if reliable then
                    Reliable:FireServer(name, ...)
                else
                    Unreliable:FireServer(name, ...)
                end
            end
        end)

        event._client = client
    end

    return event
end

local function newReliableEvent<T...>(name: string, validate: Validator<T...>): Class<T...>
    local options: EventOptions | string = {
        Name = name,
        Reliable = true
    }
    
    return newEvent(options, validate)
end

local function newUnreliableEvent<T...>(name: string, validate: Validator<T...>): Class<T...>
    local options: EventOptions | string = {
        Name = name,
        Unreliable = true
    }
    
    return newEvent(options, validate)
end

local function createEventReceiver<T...>(reliable: boolean, nameIndex: number, consumer: (Class, T...) -> ())
    return function (...)
        local args = { ... }
        local eventName = table.remove(args, nameIndex)
        local event = eventName and eventIndex[eventName]

        if event and event.Reliable == reliable then
            consumer(event, table.unpack(args))
        end
    end
end

if RunContext.IsServer then
    local function onServerReceive(event: Class, player: Player, ...: any)
        local server = event:Server()

        if server.Receiver then
            server.Receiver(player, ...)
        end
    end

    Unreliable.OnServerEvent:Connect(createEventReceiver(false, 2, onServerReceive))
    Reliable.OnServerEvent:Connect(createEventReceiver(true, 2, onServerReceive))
elseif RunContext.IsClient then
    local function onClientReceive(event: Class, ...: any)
        local client = event:Client()

        if client.Receiver then
            client.Receiver(...)
        end
    end

    Unreliable.OnClientEvent:Connect(createEventReceiver(false, 1, onClientReceive))
    Reliable.OnClientEvent:Connect(createEventReceiver(true, 1, onClientReceive))
end

return table.freeze({
    Event = newEvent,
    ReliableEvent = newReliableEvent,
    UnreliableEvent = newUnreliableEvent,
})