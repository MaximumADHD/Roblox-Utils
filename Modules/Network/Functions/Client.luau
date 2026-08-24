--!strict

local Client = {}
Client.__index = Client

local Network = script.Parent.Parent
local Types = require(Network.Types)

type Signal<T...> = Types.Signal<T...>
type Validator<T...> = Types.Validator<T...>

export type Class<Args... = ...any, Rets... = ...any> = typeof(setmetatable({} :: {
    Id: string,

    ValidateArgs: Validator<Args...>,
    ValidateReturns: Validator<Rets...>,

    Callback: ((Args...) -> (Rets...))?,
    OnInvoke: ((Args...) -> (Rets...))?,
}, Client))

function Client.Invoke<Args..., Rets...>(self: Class<Args..., Rets...>, ...: Args...): Rets...
    if self.OnInvoke then
        return self.OnInvoke(...)
    end
    
    error("Client.Invoke called on client without an implementation!")
end

function Client.On<Args..., Rets...>(self: Class<Args..., Rets...>, callback: (Args...) -> (Rets...))
    self.Callback = callback
end

function Client.Call<Args..., Rets...>(self: Class<Args..., Rets...>, ...: Args...): Rets...
    local args: any = { self.ValidateArgs(...) }
    local callback = assert(self.Callback, `No client callback set for function {self.Id}!`)

    local success, results = xpcall(function ()
        return { callback(table.unpack(args)) }
    end, function (err)
        warn("Error invoking client callback:", err, debug.traceback())
    end)

    if success and results then
        return self.ValidateReturns(table.unpack(results))
    end

    error(`Function {self.Id} failed to process the invocation!`, 0)
end

local function newClient<Args..., Rets...>(id: string, validateArgs: Validator<Args...>, validateReturns: Validator<Rets...>): Class<Args..., Rets...>
    return setmetatable({
        Id = id,
        ValidateArgs = validateArgs,
        ValidateReturns = validateReturns,

        Callback = nil :: ((Args...) -> Rets...)?,
        OnInvoke = nil :: ((Args...) -> Rets...)?,
    }, Client)
end

return table.freeze({
    new = newClient,
})