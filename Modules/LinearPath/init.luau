--!strict

local LinearPath = {}
LinearPath.__index = LinearPath

export type Class = typeof(setmetatable({} :: {
    Dists: { number },
    Points: { Vector3 },
    Normals: { Vector3 },
    Length: number,
}, LinearPath))

--- Creates a new LinearPath from a list of points.
function LinearPath.new(points: { Vector3 }): Class
    local length = 0
    local count = #points

    local dists = table.create(count)
    local normals = table.create(count)
    table.insert(dists, 0)

    for i = 2, count do
        local prev = points[i - 1]
        local curr = points[i]

        local offset = (curr - prev)
        local dist = offset.Magnitude
        local normal = offset / dist

        length += dist
        dists[i] = length
        normals[i - 1] = normal

        if i == count then
            normals[i] = normal
        end
    end

    local graph = {
        Dists = dists,
        Points = points,
        Length = length,
        Normals = normals,
    }

    return setmetatable(graph, LinearPath)
end

--- Creates a LinearPath from a Path instance.
function LinearPath.fromPath(path: Path): Class
    local waypoints: { PathWaypoint } = path:GetWaypoints()
    local points: { Vector3 } = table.create(#waypoints)

    for i, waypoint in waypoints do
        points[i] = waypoint.Position
    end

    return LinearPath.new(points)
end

--- Creates an empty LinearPath at the world origin.
function LinearPath.empty()
    return setmetatable({
        Dists = { 0 },
        Length = 0,

        Points = { Vector3.zero },
        Normals = { Vector3.xAxis },
    }, LinearPath)
end

--- Gets the position on the path at the given distance.
function LinearPath.GetPosition(self: Class, dist: number)
    local points = self.Points
    local dists = self.Dists

    if dist < 0 then
        return points[1]
    elseif dist > self.Length then
        return points[#points]
    end

    local L, R = 1, #dists
    local M: number

    while L <= R do
        M = (L + R) // 2

        if dists[M] < dist then
            L = M + 1
        elseif dists[M] > dist then
            R = M - 1
        else
            break
        end
    end

    -- Correct overshoot
    while dists[M] > dist do
        M -= 1
    end

    local p0, p1 = points[M], points[M + 1]
    local d0, d1 = dists[M], dists[M + 1]

    if p1 and d1 then
        if d0 > 0 then
            local alpha = (dist - d0) / (d1 - d0)
            return p0:Lerp(p1, alpha)
        else
            return p0:Lerp(p1, dist / d1)
        end
    else
        return p0 or Vector3.zero
    end
end

--- Finds the closest point on the path to the target point, returning the distance along the path.
function LinearPath.ClosestPoint(self: Class, target: Vector3): number
    local dists = self.Dists
    local points = self.Points

    local closestDist = math.huge
    local bestPoint = -1

    for i = 1, #points - 1 do
        local pointA = points[i]
        local pointB = points[i + 1]

        local offset = (pointB - pointA)
        local length = dists[i + 1] - dists[i]

        local dir = offset / length
        local dot = dir:Dot(target - pointA)

        local onGraph = pointA + (dir * dot)
        local dist = (target - onGraph).Magnitude

        if dist < closestDist then
            bestPoint = dists[i] + dot
            closestDist = dist
        end
    end

    return bestPoint
end

--- Gets the distance along the path at the given point index.
function LinearPath.GetDist(self: Class, index: number): number
    local dist = self.Dists[index // 1]

    if dist then
        return dist
    elseif index < 1 then
        return 0
    else
        return self.Length
    end
end

return LinearPath
