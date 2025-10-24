--!strict

local Server = {}
Server.__index = Server

local Network = script.Parent
local Players = game:GetService("Players")

local Types = require(Network.Types)
local Signal = Types.Signal

type Signal<T...> = Types.Signal<T...>
type EventOptions = Types.EventOptions
type Validator<T...> = Types.Validator<T...>

export type Class<T... = ...any> = typeof(setmetatable({} :: {
    Id: string,
    Validator: Validator<T...>,
    Dispatch: Signal<(Player, T...)>,
    Receiver: (Player, T...) -> ()?,
}, Server))

function Server.Fire<T...>(self: Class<T...>, player: Player, ...: T...)
    self.Dispatch:Fire(player, ...)
end

function Server.FireAll<T...>(self: Class<T...>, ...: T...)
    for _, player in Players:GetPlayers() do
        self.Dispatch:Fire(player, ...)
    end
end

function Server.FireAllExcept<T...>(self: Class<T...>, except: Player, ...: T...)
    for _, player in Players:GetPlayers() do
        if player ~= except then
            self.Dispatch:Fire(player, ...)
        end
    end
end

function Server.FireList<T...>(self: Class<T...>, list: { Player }, ...: T...)
    for _, player in list do
        self.Dispatch:Fire(player, ...)
    end
end

function Server.FireWithFilter<T...>(self: Class<T...>, filter: (Player) -> boolean, ...: T...)
    for _, player in Players:GetPlayers() do
        if filter(player) then
            self.Dispatch:Fire(player, ...)
        end
    end
end

function Server.On<T...>(self: Class<T...>, callback: (player: Player, T...) -> ())
    self.Receiver = function (player, ...: any)
        if pcall(self.Validator, ...) then
            callback(player, ...)
        end
    end
end

local function newServer<T...>(id: string, validate: Validator<T...>): Class<T...>
    return setmetatable({
        Id = id,
        Validator = validate,
        Dispatch = Signal.new() :: any,
    }, Server)
end

return table.freeze({
    new = newServer,
})