local function getBoundingBoxInternal(cframe: CFrame, size: Vector3, inverseBasis: CFrame?)
	local localCFrame = if inverseBasis then inverseBasis * cframe else cframe
	local sx, sy, sz = size.X, size.Y, size.Z

	local _, _, _,
		t00, t01, t02,
		t10, t11, t12,
		t20, t21, t22 = localCFrame:GetComponents()

	local hw = 0.5 * (math.abs(sx * t00) + math.abs(sy * t01) + math.abs(sz * t02))
	local hh = 0.5 * (math.abs(sx * t10) + math.abs(sy * t11) + math.abs(sz * t12))
	local hd = 0.5 * (math.abs(sx * t20) + math.abs(sy * t21) + math.abs(sz * t22))
	local x, y, z = localCFrame.X, localCFrame.Y, localCFrame.Z

	local min = Vector3.new(x - hw, y - hh, z - hd)
	local max = Vector3.new(x + hw, y + hh, z + hd)

	return min, max
end

local BoundingBox = {}

--[[
	Returns the bounding box that contains the specified objects.

	The bounding box is computed in the given coordinate space, or world space if
	no local basis is provided.

	Params:
		table objects: An array of BaseParts, Models, and Attachments.
		CFrame maybeBasisCFrame: Optional local basis.

	Returns:
		Tuple (Vector3 offset, Vector3 size).
]]
function BoundingBox.fromObjects(objects: { Instance }, maybeBasisCFrame: CFrame?)
	local basisCFrame = maybeBasisCFrame or CFrame.identity
	local inverseBasis = basisCFrame:Inverse()
	local terrain = workspace.Terrain

	local max = -Vector3.one * math.huge
	local min = Vector3.one * math.huge

	for _, object in ipairs(objects) do
		if object:IsA("PVInstance") and object ~= terrain then
			local cframe = CFrame.identity
			local size = Vector3.zero

			if object:IsA("Model") then
				cframe, size = object:GetBoundingBox()
			elseif object:IsA("BasePart") then
				cframe = object.CFrame
				size = object.Size
			end

			local min1, max1 = getBoundingBoxInternal(cframe, size, inverseBasis)
			min = Vector3.min(min, min1)
			max = Vector3.max(max, max1)
		elseif object:IsA("Attachment") then
			local localPosition = basisCFrame:PointToObjectSpace(object.WorldPosition)
			min = Vector3.min(min, localPosition)
			max = Vector3.max(max, localPosition)
		end
	end
	
	local offset = 0.5 * (min + max)
	local size = max - min

	return offset, size
end

--[[
	Returns the bounding box that contains the specified objects, as well as the
	bounding boxes for all BaseParts and Models.

	Bounding boxes are computed in the given coordinate space, or world space if
	no local basis is provided.

	Params:
		table objects: An array of BaseParts, Models, and Attachments.
		CFrame basisCFrame: Optional local basis.

	Returns:
		Tuple (Vector3 offset, Vector3 size, table boundingBoxes).
]]
function BoundingBox.fromObjectsComputeAll(objects: { Instance }, maybeBasisCFrame: CFrame?)
	local basisCFrame = maybeBasisCFrame or CFrame.identity
	local inverseBasis = basisCFrame:Inverse()

	local max = -Vector3.one * math.huge
	local min = Vector3.one * math.huge
	
	local terrain = workspace.Terrain
	local boundingBoxes = {}

	for _, object in ipairs(objects) do
		if object:IsA("PVInstance") and object ~= terrain then
			local cframe = CFrame.identity
			local size = Vector3.zero

			if object:IsA("Model") then
				cframe, size = object:GetBoundingBox()
			elseif object:IsA("BasePart") then
				cframe = object.CFrame
				size = object.Size
			end

			local min1, max1 = getBoundingBoxInternal(cframe, size, inverseBasis)
			min = Vector3.min(min, min1)
			max = Vector3.max(max, max1)
			
			boundingBoxes[object] = {
				offset = 0.5 * (min1 + max1),
				size = max1 - min1
			}
		elseif object:IsA("Attachment") then
			local localPosition = basisCFrame:PointToObjectSpace(object.WorldPosition)
			min = Vector3.min(min, localPosition)
			max = Vector3.max(max, localPosition)
		end
	end

	local offset = 0.5 * (min + max)
	local size = max - min

	return offset, size, boundingBoxes
end

--[[
	Calculate an oriented bounding box for the passed in parts and attachments,
	in the supplied basis.
]]
function BoundingBox.fromPartsAndAttachments(parts: { BasePart }, attachments: { Attachment }, maybeBasisCFrame: CFrame?)
	local basisCFrame = maybeBasisCFrame or CFrame.identity
	local inverseBasis = basisCFrame:Inverse()
	local terrain = workspace.Terrain

	local max = -Vector3.one * math.huge
	local min = Vector3.one * math.huge

	for _, part in ipairs(parts) do
		if part ~= terrain then
			local min1, max1 = getBoundingBoxInternal(part.CFrame, part.Size, inverseBasis)
			min = Vector3.min(min, min1)
			max = Vector3.max(max, max1)
		end
	end

	for _, attachment in ipairs(attachments) do
		local localPosition = basisCFrame:PointToObjectSpace(attachment.WorldPosition)
		min = Vector3.min(min, localPosition)
		max = Vector3.max(max, localPosition)
	end
	
	local offset = 0.5 * (min + max)
	local size = max - min

	return offset, size
end

--[[
	Micro-optimized code for computing a local space and the global space
	bounding box for a set of parts and attachments as fast as possible.
]]
function BoundingBox.computeTwoBoundingBoxes(parts: { BasePart }, attachments: { Attachment }, maybeBasisCFrame: CFrame?)
	local basisCFrame = maybeBasisCFrame or CFrame.identity
	local inverseBasis = basisCFrame:Inverse()
	local basisPos = basisCFrame.Position
	
	local min1, max1 = Vector3.one * math.huge, -Vector3.one * math.huge
	local min2, max2 = Vector3.one * math.huge, -Vector3.one * math.huge
	local terrain = workspace.Terrain

	for _, part in ipairs(parts) do
		if part == terrain then
			continue
		end

		local size = part.Size
		local cframe = part.CFrame
		local sx, sy, sz = size.X, size.Y, size.Z

		-- Calculation for bounding box in the space of basisCFrame
		local localCFrame1 = inverseBasis * cframe -- put cframe in our local basis

		local _, _, _,
			t00, t01, t02,
			t10, t11, t12,
			t20, t21, t22 = localCFrame1:components()
		
		local whd = Vector3.new(
			0.5 * (math.abs(sx * t00) + math.abs(sy * t01) + math.abs(sz * t02)),
			0.5 * (math.abs(sx * t10) + math.abs(sy * t11) + math.abs(sz * t12)),
			0.5 * (math.abs(sx * t20) + math.abs(sy * t21) + math.abs(sz * t22))
		)

		local hw = 0.5 * (math.abs(sx * t00) + math.abs(sy * t01) + math.abs(sz * t02))
		local hh = 0.5 * (math.abs(sx * t10) + math.abs(sy * t11) + math.abs(sz * t12))
		local hd = 0.5 * (math.abs(sx * t20) + math.abs(sy * t21) + math.abs(sz * t22))

		local pos1 = localCFrame1.Position
		min1 = Vector3.min(min1, pos1 - whd)
		max1 = Vector3.max(max1, pos1 + whd)

		-- Calculation for the bounding box in the global coordinate space
		_, _, _,
			t00, t01, t02,
			t10, t11, t12,
			t20, t21, t22 = cframe:components()
		
		hw = 0.5 * (math.abs(sx * t00) + math.abs(sy * t01) + math.abs(sz * t02))
		hh = 0.5 * (math.abs(sx * t10) + math.abs(sy * t11) + math.abs(sz * t12))
		hd = 0.5 * (math.abs(sx * t20) + math.abs(sy * t21) + math.abs(sz * t22))
		
		local pos2 = cframe.Position
		min2 = Vector3.min(min2, pos2 - Vector3.new(hw, hh, hd))
		max2 = Vector3.max(max2, pos2 + Vector3.new(hw, hh, hd))
	end

	for _, attachment in ipairs(attachments) do
		local worldPosition = attachment.WorldPosition
		min2 = Vector3.min(min2, worldPosition)
		max2 = Vector3.max(max2, worldPosition)

		local localPosition = inverseBasis * worldPosition
		min1 = Vector3.min(min1, localPosition)
		max1 = Vector3.max(max1, localPosition)
	end

	local localOffset = 0.5 * (min1 + max1)
	local localSize = max1 - min1

	local globalOffset = 0.5 * (min2 + max2) - basisPos
	local globalSize = max2 - min2

	return localOffset, localSize, globalOffset, globalSize
end

return BoundingBox
