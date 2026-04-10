local PrimaryDirections = {
	Vector3.xAxis
	-Vector3.xAxis,

	Vector3.yAxis,
	-Vector3.yAxis,

	Vector3.zAxis,
	-Vector3.zAxis,
}

local function largestComponent(vector: Vector3)
	return math.max(math.abs(vector.X), math.abs(vector.Y), math.abs(vector.Z))
end

local function snapVectorToPrimaryDirection(direction: Vector3)
	local largestDot = -math.huge
	local closestDirection = direction

	for _, target in ipairs(PrimaryDirections) do
		local dot = direction:Dot(target)
		if dot > largestDot then
			largestDot = dot
			closestDirection = target
		end
	end

	return closestDirection
end

return function(cframe: CFrame)
	local right = cframe.RightVector
	local top = cframe.UpVector
	local front = -cframe.LookVector

	local largestRight = largestComponent(right)
	local largestTop = largestComponent(top)
	local largestFront = largestComponent(front)

	if largestRight > largestTop and largestRight > largestFront then
		-- Most aligned axis is X, the right, preserve that
		right = snapVectorToPrimaryDirection(right)

		if largestTop > largestFront then
			top = snapVectorToPrimaryDirection(top)
		else
			local front = snapVectorToPrimaryDirection(front)
			top = front:Cross(right).Unit
		end
	elseif largestTop > largestFront then
		-- Most aligned axis is Y, the top, preserve that
		top = snapVectorToPrimaryDirection(top)

		if largestRight > largestFront then
			right = snapVectorToPrimaryDirection(right)
		else
			local front = snapVectorToPrimaryDirection(front)
			right = top:Cross(front).Unit
		end
	else
		-- Most aligned axis is Z, the front, preserve that
		local front = snapVectorToPrimaryDirection(front)

		if largestRight > largestTop then
			right = snapVectorToPrimaryDirection(right)
			top = front:Cross(right).Unit
		else
			top = snapVectorToPrimaryDirection(top)
			right = top:Cross(front).Unit
		end
	end
	
	return CFrame.fromMatrix(Vector3.zero, right, top)
end