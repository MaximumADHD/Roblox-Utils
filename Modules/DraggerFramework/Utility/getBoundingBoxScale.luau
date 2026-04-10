local BoundingBoxCorners = {
	Vector3.new(0.5, 0.5, 0.5),
	Vector3.new(-0.5, 0.5, 0.5),
	Vector3.new(0.5, -0.5, 0.5),
	Vector3.new(-0.5, -0.5, 0.5),
	Vector3.new(0.5, 0.5, -0.5),
	Vector3.new(-0.5, 0.5, -0.5),
	Vector3.new(0.5, -0.5, -0.5),
	Vector3.new(-0.5, -0.5, -0.5),
}

local DraggerFramework = script.Parent.Parent
local Implementation = DraggerFramework.Implementation

local DraggerContext = require(Implementation.DraggerContext)
type DraggerContext = DraggerContext.Class

local function getBoundingBoxScale(draggerContext: DraggerContext, cframe: CFrame, size: Vector3)
	local minScale = math.huge

	for _, relativeCorner in ipairs(BoundingBoxCorners) do
		local globalCorner = cframe:PointToWorldSpace(size * relativeCorner)
		minScale = math.min(minScale, draggerContext:getHandleScale(globalCorner))
	end

	return minScale
end

return getBoundingBoxScale
