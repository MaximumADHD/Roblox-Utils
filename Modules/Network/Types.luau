--!strict

local Shared = script.Parent.Parent
local Signal = require(Shared.Signal)

export type Signal<T...> = Signal.Signal<T...>
export type Validator<T...> = (...unknown) -> T...

type Named = {
    Name: string
}

type Reliable = {
    Reliable: boolean?
}

type Unreliable = {
    Unreliable: boolean?
}

export type EventOptions = Named & (Reliable | Unreliable)

return table.freeze({
    Signal = Signal,
})