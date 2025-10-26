--!strict

local Shared = script.Parent.Parent
local Signal = require(Shared.Signal)

export type Signal<T...> = Signal.Signal<T...>
export type Validator<T...> = (...unknown) -> T...

export type EventOptions = {
    Name: string,
    Reliable: boolean?,
    Unreliable: boolean?,
}

return {
    Signal = Signal,
}