
-- Attachments like to be exclusively selected unless we're trying to multiple
-- select them.
local Packages = script.Parent.Parent

local DraggerFramework = require(Packages.DraggerFramework)
type DraggerContext = DraggerFramework.DraggerContext

return function(draggerContext: DraggerContext, selectable: Instance?, item: Instance)
	return item:IsA("Attachment") and not draggerContext:shouldExtendSelection()
end