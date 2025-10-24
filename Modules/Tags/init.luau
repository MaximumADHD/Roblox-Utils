------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Tags
-- MaximumADHD
-- December 22nd, 2020
------------------------------------------------------------------------------------------------------------------------------------------------------------------
--!native
--!strict

local Tags = {}
local Shared = script.Parent
local CollectionService = game:GetService("CollectionService")

local Trove = require(Shared.Trove)
type Trove = Trove.Trove

local Signal = require(Shared.Signal)
type Signal<T...> = Signal.Signal<T...>

local RunContext = require(Shared.RunContext)
local coreMaid = Trove.new()

if RunContext.IsEdit then
    local oldMaid = shared[script]

    if oldMaid then
        oldMaid:Clean()
    end

    shared[script] = coreMaid
end

function Tags.GetTagged(tag: string): { Instance }
    return CollectionService:GetTagged(tag)
end

function Tags.GetInstanceAddedSignal(tag: string): RBXScriptSignal
    return CollectionService:GetInstanceAddedSignal(tag)
end

function Tags.GetInstanceRemovedSignal(tag: string): RBXScriptSignal
    return CollectionService:GetInstanceRemovedSignal(tag)
end

function Tags.FindFirstTagged(tag: string): Instance?
    local tagged = CollectionService:GetTagged(tag)

    if #tagged > 0 then
        return tagged[1]
    end

    return nil
end

function Tags.Bind(tag: string, onAdded: (Instance) -> ()?, onRemoved: (Instance) -> ()?): Trove
    local maid = coreMaid:Extend()

    if onRemoved then
        maid:Connect(Tags.GetInstanceRemovedSignal(tag), onRemoved)
    end

    if onAdded then
        maid:Connect(Tags.GetInstanceAddedSignal(tag), onAdded)

        for i, tagged in CollectionService:GetTagged(tag) do
            task.spawn(onAdded, tagged)
        end
    end

    return maid
end

function Tags.BindWithMaid(tag: string, onAdded: (Instance, Trove) -> (), onRemoved: (Instance) -> ()?): Trove
    local tagMaids = {} :: {
        [Instance]: Trove,
    }

    local bindMaid = Tags.Bind(tag, function(inst)
        local baseMaid = Trove.new()
        tagMaids[inst] = baseMaid

        baseMaid:Add(function()
            if onRemoved then
                onRemoved(inst)
            end
        end)

        onAdded(inst, baseMaid)
    end, function(inst)
        local maid = tagMaids[inst]

        if maid then
            maid:Destroy()
            tagMaids[inst] = nil
        end
    end)

    return bindMaid
end

return Tags
