--!strict

local Shared = script.Parent.Parent
local RunContext = require(Shared.RunContext)

local reliableEvent = script:FindFirstChildOfClass("RemoteEvent")
local remoteFunction = script:FindFirstChildOfClass("RemoteFunction")
local unreliableEvent = script:FindFirstChildOfClass("UnreliableRemoteEvent")

if not (reliableEvent and unreliableEvent and remoteFunction) then
    if RunContext.IsServer or RunContext.IsEdit then
        if not reliableEvent then
            local newReliable = Instance.new("RemoteEvent")
            newReliable.Name = "Reliable"
            newReliable.Parent = script
            reliableEvent = newReliable
        end

        if not unreliableEvent then
            local newUnreliable = Instance.new("UnreliableRemoteEvent")
            newUnreliable.Name = "Unreliable"
            newUnreliable.Parent = script
            unreliableEvent = newUnreliable
        end

        if not remoteFunction then
            local newRemoteFunction = Instance.new("RemoteFunction")
            newRemoteFunction.Name = "RemoteFunction"
            newRemoteFunction.Parent = script
            remoteFunction = newRemoteFunction
        end
    else
        local newReliable = script:WaitForChild("Reliable")
        assert(newReliable and newReliable:IsA("RemoteEvent"), "RemoteEvent not found!")

        local newUnreliable = script:WaitForChild("Unreliable")
        assert(newUnreliable and newUnreliable:IsA("UnreliableRemoteEvent"), "UnreliableRemoteEvent not found!")

        local newFunction = script:WaitForChild("RemoteFunction")
        assert(newFunction and newFunction:IsA("RemoteFunction"), "RemoteFunction not found!")

        reliableEvent = newReliable
        remoteFunction = newFunction
        unreliableEvent = newUnreliable
    end
end

return table.freeze({
    ReliableEvent = assert(reliableEvent),
    RemoteFunction = assert(remoteFunction),
    UnreliableEvent = assert(unreliableEvent),
})