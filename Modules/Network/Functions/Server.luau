--!strict

local Server = {}
Server.__index = Server

local Network = script.Parent.Parent
local Types = require(Network.Types)

type Signal<T...> = Types.Signal<T...>
type Validator<T...> = Types.Validator<T...>

export type Class<Args... = ...any, Rets... = ...any> = typeof(setmetatable({} :: {
    Id: string,

    ValidateArgs: Validator<Args...>,
    ValidateReturns: Validator<Rets...>,

    Callback: ((Player, Args...) -> Rets...)?,
    OnInvoke: ((Player, Args...) -> (Rets...))?,
}, Server))

function Server.Invoke<Args..., Rets...>(self: Class<Args..., Rets...>, player: Player, ...: Args...): Rets...
    if self.OnInvoke then
        return self.OnInvoke(player, ...)
    end
    
    error("Server.Invoke called on server without an implementation defined!")
end

function Server.On<Args..., Rets...>(self: Class<Args..., Rets...>, callback: (Player, Args...) -> (Rets...))
    self.Callback = callback
end

function Server.Call<Args..., Rets...>(self: Class<Args..., Rets...>, player: Player, ...: Args...): Rets...
    local args: any = { self.ValidateArgs(...) }
    local callback = assert(self.Callback, `No server callback set for function {self.Id}!`)

    local success, results = xpcall(function ()
        return { callback(player, table.unpack(args)) }
    end, function (err)
        warn("Error invoking server callback:", err, debug.traceback())
    end)

    if success and results then
        return self.ValidateReturns(table.unpack(results))
    end

    error(`Function {self.Id} failed to process the invocation!`, 0)
end

local function newServer<Args..., Rets...>(id: string, validateArgs: Validator<Args...>, validateReturns: Validator<Rets...>): Class<Args..., Rets...>
    return setmetatable({
        Id = id,
        ValidateArgs = validateArgs,
        ValidateReturns = validateReturns,
        Callback = nil :: ((Player, Args...) -> Rets...)?,
        OnInvoke = nil :: ((Player, Args...) -> Rets...)?,
    }, Server)
end

return table.freeze({
    new = newServer,
})