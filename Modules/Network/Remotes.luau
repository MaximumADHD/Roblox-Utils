--!strict

local Shared = script.Parent.Parent
local RunContext = require(Shared.RunContext)

local reliable = script:FindFirstChildOfClass("RemoteEvent")
local unreliable = script:FindFirstChildOfClass("UnreliableRemoteEvent")

if not (reliable and unreliable) then
    if RunContext.IsServer or RunContext.IsEdit then
        if not reliable then
            local newReliable = Instance.new("RemoteEvent")
            newReliable.Name = "Reliable"
            newReliable.Parent = script
            reliable = newReliable
        end

        if not unreliable then
            local newUnreliable = Instance.new("UnreliableRemoteEvent")
            newUnreliable.Name = "Unreliable"
            newUnreliable.Parent = script
            unreliable = newUnreliable
        end
    else
        local newReliable = script:WaitForChild("Reliable")
        assert(newReliable and newReliable:IsA("RemoteEvent"), "RemoteEvent not found!")

        local newUnreliable = script:WaitForChild("Unreliable")
        assert(newUnreliable and newUnreliable:IsA("UnreliableRemoteEvent"), "UnreliableRemoteEvent not found!")

        reliable = newReliable
        unreliable = newUnreliable
    end
end

return table.freeze({
    Reliable = assert(reliable),
    Unreliable = assert(unreliable),
})