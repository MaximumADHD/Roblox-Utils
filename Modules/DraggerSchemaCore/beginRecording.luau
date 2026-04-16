local DraggerSchemaCore = script.Parent
local Packages = DraggerSchemaCore.Parent

local DraggerFramework = require(Packages.DraggerFramework)
type DraggerContext = DraggerFramework.DraggerContext

return function(draggerContext: DraggerContext, waypointName: string)
	draggerContext:beginRecording(waypointName)
end
