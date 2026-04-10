
local SelectionService = game:GetService("Selection")

local Packages = script.Parent.Parent
local DraggerFramework = require(Packages.DraggerFramework)
local isProtectedInstance = DraggerFramework.Utility.isProtectedInstance

local Selection = {}
Selection.__index = Selection

export type Class = setmetatable<{
	SelectionChanged: RBXScriptSignal,
}, typeof(Selection)>

export type Hint = {
	Added: { Instance },
	Removed: { Instance },
}

function Selection.new(): Class
	local self = setmetatable({}, Selection)
	self.SelectionChanged = SelectionService.SelectionChanged
	return self
end

--[[
	Note: The fact that the processing of hint _first_ removes and _then_ adds
	items to the selection is important, all Selection implementations should
	handle things this way.
]]
function Selection.Set(self: Class, objects: { Instance }, hint: Hint?)
	if hint then
		SelectionService:Remove(hint.Removed)
		SelectionService:Add(hint.Added)
	else
		SelectionService:Set(objects)
	end
end

function Selection.Get(self: Class): { Instance }
	local unsafeSelection = SelectionService:Get()
	local safeSelection = {}

	for _, unsafeInstance in ipairs(unsafeSelection) do
		if not isProtectedInstance(unsafeInstance) then
			table.insert(safeSelection, unsafeInstance)
		end
	end

	return safeSelection
end

function Selection.GetActiveInstance(self: Class): Instance?
	local success, activeInstance = pcall(function()
		return (SelectionService :: any).ActiveInstance
	end)
	
	if success then
		return activeInstance
	else
		return nil
	end
end

return Selection
