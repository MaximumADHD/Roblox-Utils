
local DraggerSchemaCore = script.Parent
local shouldSelectSubPart = require(DraggerSchemaCore.shouldSelectSubPart)
local getSelectableWithCache = require(DraggerSchemaCore.getSelectableWithCache)

local Packages = DraggerSchemaCore.Parent
local DraggerFramework = require(Packages.DraggerFramework)

type DraggerContext = DraggerFramework.DraggerContext
type Gizmo = DraggerFramework.Gizmo

type Target =
	| BasePart
	| Gizmo

return function(draggerContext: DraggerContext, mouseRay: Ray, currentSelection: { Instance }): (Instance?, Target?, number?)
	local shouldDrillSelection = shouldSelectSubPart(draggerContext)
	local hitResult = workspace:Raycast(mouseRay.Origin, mouseRay.Direction)
	
	-- Selection favoring: If there is a selected object and a non-selected
	-- object almost exactly coincident underneath the mouse, then we should
	-- favor the selected one, even if due to floating point error the non
	-- selected one comes out slightly closer.
	-- Without this case, if you duplicate objects and try to drag them, you
	-- may end up dragging only one of the objects because you clicked on the
	-- old non-selected copy, as opposed to the selected one you meant to.
	local hitPosition = mouseRay.Origin + mouseRay.Direction 
	local hitItem: (BasePart | Gizmo)?

	if hitResult then
		hitPosition = hitResult.Position
		hitItem = hitResult.Instance

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = currentSelection
		
		local hitSelected = workspace:Raycast(mouseRay.Origin, mouseRay.Direction, params)
		
		if hitSelected and hitSelected.Position:FuzzyEq(hitPosition) then
			hitItem = hitSelected.Instance
		end
	end

	local hitDistance = (mouseRay.Origin - hitPosition).Magnitude
	local hitResult = draggerContext:gizmoRaycast(mouseRay.Origin, mouseRay.Direction)

	if hitResult and
		(draggerContext:shouldDrawConstraintsOnTop() or (hitResult.Distance < hitDistance)) then
		hitDistance = hitResult.Distance
		hitItem = hitResult.Instance
	end

	if hitItem then
		local hitSelectable = getSelectableWithCache(hitItem, shouldDrillSelection, {})
		return hitSelectable, hitItem, hitDistance
	else
		return nil, nil, nil
	end
end