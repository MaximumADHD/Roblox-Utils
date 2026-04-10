local DraggerSchemaCore = script.Parent
local Packages = DraggerSchemaCore.Parent

local DraggerFramework = require(Packages.DraggerFramework)
type DraggerContext = DraggerFramework.DraggerContext

local getSelectableWithCache = require(DraggerSchemaCore.getSelectableWithCache)
local shouldSelectSubPart = require(DraggerSchemaCore.shouldSelectSubPart)

type ISelectable = 
	| PVInstance
	| Attachment

type DragCandidate = {
	Center: Vector3,
	Selectable: ISelectable,
}

return function(draggerContext: DraggerContext)
	local dragCandidates = {} :: { DragCandidate }

	local areConstraintDetailsShown = draggerContext:areConstraintDetailsShown()
	local shouldSelectIndividually = shouldSelectSubPart(draggerContext)

	local getSelectableCache = {}
	local alreadyAddedSet = {} :: { [Instance]: true }

	local descendants = workspace:GetDescendants()

	for _, object in ipairs(descendants) do
		-- TODO: Refactor this to not look through every BasePart
		-- unless shouldSelectIndividually is true
		-- (though it still has to look through every Attachment)
		if object:IsA("BasePart") then
			if not object.Locked then
				local selectable = getSelectableWithCache(object, shouldSelectIndividually, getSelectableCache)

				if selectable and not alreadyAddedSet[selectable] then
					local center = Vector3.zero
					local iselectable: ISelectable?

					if selectable:IsA("Model") then
						if selectable:IsA("Tool") then
							center = object.Position
							iselectable = selectable
						else
							center = selectable:GetBoundingBox().Position
							iselectable = selectable
						end
					elseif selectable:IsA("BasePart") then
						center = selectable.Position
						iselectable = selectable
					end

					alreadyAddedSet[selectable] = true

					if iselectable then
						table.insert(dragCandidates, {
							Center = center,
							Selectable = iselectable,
						})
					end
				end
			end
		elseif object:IsA("Attachment") then
			if object.Visible or areConstraintDetailsShown then
				table.insert(dragCandidates, {
					Center = object.WorldPosition,
					Selectable = object,
				})
			end
		end
	end

	return dragCandidates
end