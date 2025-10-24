--!strict

local Client = {}
Client.__index = Client

local Network = script.Parent
local Types = require(Network.Types)
local Signal = Types.Signal

type Signal<T...> = Types.Signal<T...>
type EventOptions = Types.EventOptions
type Validator<T...> = Types.Validator<T...>

export type Class<T... = ...any> = typeof(setmetatable({} :: {
    Id: string,
    Validator: Validator<T...>,
    Dispatch: Signal<T...>,
    Receiver: (T...) -> ()?,
}, Client))

function Client.Fire<T...>(self: Class<T...>, ...: T...)
    self.Dispatch:Fire(...)
end

function Client.On<T...>(self: Class<T...>, callback: (T...) -> ())
    self.Receiver = function (...: any)
        if pcall(self.Validator, ...) then
            callback(...)
        end
    end
end

local function newClient<T...>(id: string, validate: Validator<T...>): Class<T...>
    return setmetatable({
        Id = id,
        Validator = validate,
        Dispatch = Signal.new() :: any,
    }, Client)
end

return table.freeze({
    new = newClient,
})