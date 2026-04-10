local DraggerSchemaCore = script.Parent
local Packages = DraggerSchemaCore.Parent

local DraggerFramework = require(Packages.DraggerFramework)
type DraggerContext = DraggerFramework.DraggerContext

return function(draggerContext: DraggerContext, waypointIdentifier: string, waypointText: string)
	draggerContext:addUndoWaypoint(waypointIdentifier, waypointText)
end