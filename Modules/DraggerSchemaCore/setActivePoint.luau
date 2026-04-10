local DraggerSchemaCore = script.Parent
local SelectionInfo = require(DraggerSchemaCore.SelectionInfo)

local Packages = DraggerSchemaCore.Parent
local DraggerFramework = require(Packages.DraggerFramework)

type DraggerContext = DraggerFramework.DraggerContext
type SelectionInfo = SelectionInfo.Class

return function(draggerContext: DraggerContext, selectionInfo: SelectionInfo)
	if not selectionInfo:isEmpty() then
		local cframe, offset = selectionInfo:getBoundingBox()
		draggerContext:setInsertPoint(cframe * offset)
	end
end