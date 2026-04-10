-- For the core manipulators, just set the Studio Service hovered instance to
-- the instance which the mouse was directly hovered over (hoverItem).
local DraggerSchemaCore = script.Parent
local Packages = DraggerSchemaCore.Parent

local DraggerFramework = require(Packages.DraggerFramework)
type DraggerContext = DraggerFramework.DraggerContext

return function(draggerContext: DraggerContext, hoverSelectable: Instance?, hoverItem: Instance?)
	draggerContext:setHoverInstance(hoverItem)
end