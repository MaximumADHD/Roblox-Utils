local DraggerSchemaCore = script.Parent
local Packages = DraggerSchemaCore.Parent

local dispatchWorldClick = require(DraggerSchemaCore.dispatchWorldClick)
type FreeformDragInfo = dispatchWorldClick.FreeformDragInfo

local DraggerFramework = require(Packages.DraggerFramework)
type DraggerContext = DraggerFramework.DraggerContext

return function(draggerContext: DraggerContext, currentSelection: { Instance }, dragInfo: FreeformDragInfo?, isDoubleClick: boolean): { Instance }?
	-- dragInfo will be nil when we didn't start a potential freeform drag
	if dragInfo and dragInfo.clickedFaceInstance then
		return { dragInfo.clickedFaceInstance }
	end

	return nil
end