local Math = {}

-- Insersect Ray(a + t*b) with plane (origin: o, normal: n), return t of the interesection
function Math.intersectRayPlane(a: Vector3, b: Vector3, o: Vector3, n: Vector3): number
	return (o - a):Dot(n) / b:Dot(n)
end

-- Intersect Ray(a + t*b) with plane (origin: o, normal :n), and return the intersection as Vector3
function Math.intersectRayPlanePoint(a: Vector3, b: Vector3, o: Vector3, n: Vector3): Vector3
	local t = Math.intersectRayPlane(a, b, o, n)
    return a + t * b;
end

--[[
	The return value `t` is a number such that `r1o + t * r1d` is the point of
	closest approach on the first ray between the two rays specified by the
	arguments.
]]
function Math.intersectRayRay(r1o: Vector3, r1d: Vector3, r2o: Vector3, r2d: Vector3): (boolean, number)
	local n =
		(r2o - r1o):Dot(r1d) * r2d:Dot(r2d) +
		(r1o - r2o):Dot(r2d) * r1d:Dot(r2d)
	local d =
		r1d:Dot(r1d) * r2d:Dot(r2d) -
		r1d:Dot(r2d) * r1d:Dot(r2d)
	if d == 0 then
		return false, 0
	else
		return true, n / d
	end
end

--[[
	Returns the point of closest approach on the first ray between the two rays 
	specified by the arguments.
]]
function Math.intersectRayRayPoint(r1o, r1d, r2o, r2d)
	local r1du = r1d.Unit
	local r2du = r2d.Unit
	local _, t = Math.intersectRayRay(r1o, r1du, r2o, r2du)
	return r1o + t * r1du
end

--[[
	Intersect a ray (origin + t * direction)
	  with
	A cylinder located at the origin with its axis aligned in the +x direction
	having a radius and a height
	Return t
]]
function Math.intersectRayCylinder(origin: Vector3, direction: Vector3, radius: number, height: number): (boolean, number)
	local p0 = origin

	local a = direction.Y * direction.Y + direction.Z * direction.Z
	local b = direction.Y * p0.Y + direction.Z * p0.Z
	local c = p0.Y * p0.Y + p0.Z * p0.Z - radius * radius

	local delta = b * b - a * c;
	if delta < 0 then
		return false, 0
	end

	local t1 = (-b - math.sqrt(delta)) / a
	local x1 = p0.X + t1 * direction.X
	if math.abs(x1) <= 0.5 * height then
		return true, t1
	end

	local t2 = (-b + math.sqrt(delta)) / a
	local x2 = p0.X + t2 * direction.X
	if math.abs(x2) <= 0.5 * height then
		return true, t2
	end

	return false, 0
end

--[[
	Returns the closest point of intersection along a ray with a sphere.

	For line-sphere intersection, there are three possible results: no intersection,
	one point intersection (tangent), and two point intersection. Since a ray has an
	origin and direction, we only need to consider the smaller (and positive) of the
	two intersections.
]]
function Math.intersectRaySphere(rayOrigin: Vector3, rayDirection: Vector3, sphereOrigin: Vector3, radius: number): (boolean, number)
	local oc = rayOrigin - sphereOrigin

	local a = rayDirection:Dot(rayDirection)
	local b = 2 * oc:Dot(rayDirection)
	local c = oc:Dot(oc) - radius * radius

	local discriminant = b * b - 4 * a * c

	if discriminant >= 0 then
		local numerator = -b - math.sqrt(discriminant)

		if numerator > 0 then
			return true, numerator / 2 * a
		end
	end

	return false, 0
end

function Math.regionFromParts(parts: { PVInstance }): Region3
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

	for _, part in ipairs(parts) do
		local min, max

		if part:IsA("BasePart") then
			min = part.CFrame.Position - part.Size
			max = part.CFrame.Position + part.Size
		elseif part:IsA("Model") then
			local orientation, size = part:GetBoundingBox()
			min = orientation - size
			max = orientation + size
		end

		if min ~= nil and max ~= nil then
			minX = math.min(minX, min.X)
			minY = math.min(minY, min.Y)
			minZ = math.min(minZ, min.Z)
			maxX = math.max(maxX, max.X)
			maxY = math.max(maxY, max.Y)
			maxZ = math.max(maxZ, max.Z)
		end
	end

	return Region3.new(
		Vector3.new(minX, minY, minZ),
		Vector3.new(maxX, maxY, maxZ)
	)
end


-- Convert a subset of {X: bool, Y: bool, Z: bool} to a vector with corresponding axes set to 1
function Math.setToVector3(set: { X: any, Y: any, Z: any }?): Vector3
	return set and Vector3.new(not set.X and 0 or 1, not set.Y and 0 or 1, not set.Z and 0 or 1)
				or Vector3.new(0, 0, 0)
end

-- Convert vector into array so that its components could be indexed
function Math.vectorToArray(vec: Vector3): {number}
	return {vec.X, vec.Y, vec.Z}
end

-- Largest component of a vector
function Math.maxComponent(vec: Vector3): number
	return math.max(vec.X, vec.Y, vec.Z)
end

-- Smallest component of a vector
function Math.minComponent(vec: Vector3): number
	return math.min(vec.X, vec.Y, vec.Z)
end

return Math
