
local Utility = script.Parent
local BoundingBox = require(Utility.BoundingBox)
local shouldDragAsFace = require(Utility.shouldDragAsFace)

local DraggerFramework = Utility.Parent
local Implementation = DraggerFramework.Implementation

local DraggerContext = require(Implementation.DraggerContext)
type DraggerContext = DraggerContext.Class

type SelectionInfo = {
	basisCFrame: CFrame,
	basisObject: PVInstance?,
	boundingBoxSize: Vector3,
	boundingBoxOffset: Vector3,
	localBasisCFrame: CFrame,
	localBoundingBoxSize: Vector3,
	localBoundingBoxOffset: Vector3,
	parts: { BasePart },
	partSet: { [BasePart]: true },
	attachments: { Attachment },
	models: { Model },
	allAttachments: { Attachment },
	originalCFrameMap: { [BasePart]: CFrame },
	hasPhysics: boolean,
	instancesWithConfigurableFace: { Instance },
}

--[[
	Find all of the "roots" bones in a list of Bones. One of the bones in the
	list is a root iff it is not a descendant of any of the other root bones.
]]
local function markBoneRecursive(bone: Bone, movedSet: { [Bone]: true }, rootBoneMap: { [Bone]: BasePart })
	if movedSet[bone] then
		rootBoneMap[bone] = nil
	else
		movedSet[bone] = true

		for _, ch in ipairs(bone:GetChildren()) do
			if ch:IsA("Bone") then
				markBoneRecursive(ch, movedSet, rootBoneMap)
			end
		end
	end
end

local function findRootBoneMap(boneList: { Bone })
	local rootBoneMap = {}
	local movedSet = {}

	for _, bone in ipairs(boneList) do
		if not movedSet[bone] then
			local part = bone:FindFirstAncestorWhichIsA("BasePart")

			if part then
				rootBoneMap[bone] = part
			end
			
			markBoneRecursive(bone, movedSet, rootBoneMap)
		end
	end
	
	return rootBoneMap
end

local function computeInfo(draggerContext: DraggerContext, selectedObjects: { Instance }): SelectionInfo
	local isSimulating = draggerContext:isSimulating()
	local useLocalSpace = draggerContext:shouldUseLocalSpace()
	
	local allParts = table.create<<BasePart>>(64)
	local allPartSet = {} :: { [BasePart]: true }

	local allAttachments = {} :: { Attachment }
	local allBones = {} :: { Bone }
	local allModels = {} :: { Model }

	local allInstancesWithConfigurableFace = {} :: { Instance }
	local basisObject = nil

	local terrain = workspace.Terrain
	local selectedPVInstanceCount = 0

	for _, instance in ipairs(selectedObjects) do
		if instance:IsA("Model") then
			selectedPVInstanceCount += 1
			table.insert(allModels, instance)
			basisObject = instance
		elseif instance:IsA("BasePart") then
			selectedPVInstanceCount += 1
			if not allPartSet[instance] and instance ~= terrain then
				table.insert(allParts, instance)
				allPartSet[instance] = true
				basisObject = instance
			end
		elseif shouldDragAsFace(instance) then
			table.insert(allInstancesWithConfigurableFace, instance)
		elseif instance:IsA("Attachment") then
			if instance:IsA("Bone") then
				table.insert(allBones, instance)
			else
				table.insert(allAttachments, instance)
			end
		end
		-- It is possible to place parts inside of other parts, so this isn't an else on the prior if.
		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") and not allPartSet[descendant] and descendant ~= terrain then
				table.insert(allParts, descendant)
				allPartSet[descendant] = true
				-- Note: This is a helpful feature to still allow people to drag
				-- non-Model objects that still typically have parts inside of
				-- them like Folders and Tools.
				basisObject = basisObject or descendant
			elseif descendant:IsA("Model") then
				basisObject = basisObject or descendant
				table.insert(allModels, descendant)
			end
		end
	end

	-- Build a table of only the "interesting" attachments, that is, those
	-- which aren't underneath one of the selected parts.
	local interestingAttachments = {}

	for _, attachment in ipairs(allAttachments) do
		local parent = attachment:FindFirstAncestorWhichIsA("BasePart")

		if parent and parent:IsA("BasePart") and not allPartSet[parent] then
			table.insert(interestingAttachments, attachment)
		end
	end

	-- Figure out what bones in the list of bones are "roots" that are not
	-- relative to another bone we are already moving. Then add those bones to
	-- the above list of "interesting"a attachments.
	local rootBoneMap = findRootBoneMap(allBones)

	for attachment, ancestorPart in pairs(rootBoneMap) do
		if not allPartSet[ancestorPart] then
			table.insert(interestingAttachments, attachment)
		end
	end
	
	-- Look for a pivot:
	-- * If there are any PVInstances in the selection, use the pivot of the
	--   last one in the selection (the most recently selected one)
	-- * As a fallback when no PVInstances are selected, try to use the 
	--   WorldCFrame of an Attachment in the selection.
	local isMultiSelection
	local basisCFrame = nil

	if basisObject then
		basisCFrame = basisObject:GetPivot()
		isMultiSelection = selectedPVInstanceCount ~= 1
	elseif #interestingAttachments > 0 then
		basisCFrame = interestingAttachments[1].WorldCFrame

		-- We use interestingAttachments here because if you box selected
		-- to select multiple bones here, if there's only one effective
		-- root bone to be moved, you still want to use that bone as the
		-- pivot, but if multiple root bones were selected then we have to
		-- fall back to pivoting around the center of the bounding box.
		-- (Setting isMultiSelection = true causes the pivot to be the
		-- center of the bounding box)
		if #interestingAttachments > 1 then
			isMultiSelection = true
		end
	else
		basisCFrame = CFrame.identity
		isMultiSelection = false
	end

	-- Store original CFrames so while moving parts we don't run into floating
	-- point error problems by using relative moves.
	local originalCFrameMap = {}

	for _, part in ipairs(allParts) do
		originalCFrameMap[part] = part.CFrame
	end

	-- Figure out if any of the objects in the selection are physically free
	-- moving parts. If there are, we will need to update the selection info
	-- every frame because those parts may have moved.
	local selectionHasPhysics = false

	if isSimulating then
		for _, part in ipairs(allParts) do
			if not part:IsGrounded() then
				selectionHasPhysics = true
				break
			end
		end
		if not selectionHasPhysics then
			for _, attachment in ipairs(allAttachments) do
				local parentPart = attachment:FindFirstAncestorWhichIsA("BasePart")
				
				if parentPart and not parentPart:IsGrounded() then
					selectionHasPhysics = true
					break
				end
			end
			for attachment, ancestorPart in pairs(rootBoneMap) do
				if not ancestorPart:IsGrounded() then
					selectionHasPhysics = true
				end
			end
		end
	end

	-- Finally add all the bones to the list of all attachments, because we want
	-- to pass back a list of all the selected things that inherit Attachment.
	-- We don't do this earlier because for the preceeding code we want to
	-- treat Bones and non-Bone Attachments slightily differently.
	-- We re-use the allAttachments table for this purpose to avoid allocating
	-- another table of both attachments and bones.
	for _, bone in ipairs(allBones) do
		table.insert(allAttachments, bone)
	end

	-- Build the basisCFrame aligned bounding box.
	-- Local = always the local space. Needed because freeform dragging always
	-- uses the local space bounding box.
	local localBasisCFrame = basisCFrame
	local localBoundingBoxOffset, localBoundingBoxSize

	-- Chosen = local or global depending on the UseLocalSpace setting
	local chosenBasisCFrame
	local chosenBoundingBoxOffset, chosenBoundingBoxSize

	if useLocalSpace then
		localBoundingBoxOffset, localBoundingBoxSize =
			BoundingBox.fromPartsAndAttachments(allParts, allAttachments, localBasisCFrame)

		chosenBasisCFrame = localBasisCFrame
		chosenBoundingBoxOffset, chosenBoundingBoxSize =
			localBoundingBoxOffset, localBoundingBoxSize
	else
		localBoundingBoxOffset, localBoundingBoxSize,
			chosenBoundingBoxOffset, chosenBoundingBoxSize =
				BoundingBox.computeTwoBoundingBoxes(allParts, allAttachments, localBasisCFrame)

		chosenBasisCFrame = CFrame.new(basisCFrame.Position)
	end

	-- If we have a multi-selection, the pivot should be moved to the center
	-- of the bounding box.
	if isMultiSelection then
		localBasisCFrame *= CFrame.new(localBoundingBoxOffset)
		localBoundingBoxOffset = Vector3.new()
		chosenBasisCFrame *= CFrame.new(chosenBoundingBoxOffset)
		chosenBoundingBoxOffset = Vector3.new()
	end

	return {
		-- basisCFrame is the CFrame which the selection will be transformed
		-- relative to when transforming it.
		basisCFrame = chosenBasisCFrame,

		-- If a PVInstance is selected, the PVInstance that the pivot was
		-- read from.
		basisObject = basisObject,

		-- boundingBoxSize is the size of the bounding box, as oriented around
		-- the basisCFrame.
		boundingBoxSize = chosenBoundingBoxSize,

		-- boundingBoxOffset is the offset of the center of the bounding box
		-- from the basisCFrame's position. basisCFrame will always be
		-- somewhere in the bounding box, but not necessarily at the center.
		boundingBoxOffset = chosenBoundingBoxOffset,

		-- This is a local space variant of the above set of properties. If the
		-- user is working in local space, then basisCFrame = localBasisCFrame,
		-- but they will differ if they have chosen a different frame of
		-- reference to work in.
		localBasisCFrame = localBasisCFrame,
		localBoundingBoxSize = localBoundingBoxSize,
		localBoundingBoxOffset = localBoundingBoxOffset,

		-- Parts and Attachments are the arrays of parts and attachments that
		-- need to be updated when transforming the selection.
		parts = allParts,
		partSet = allPartSet,
		attachments = interestingAttachments,
		models = allModels,

		-- All the attachments, including ones under parts in the list of parts
		-- to move. We still need these for some edge case behavior.
		allAttachments = allAttachments,

		-- OriginalCFrameMap stores the cframes of the parts before any
		-- transformation was applied to the selection.
		originalCFrameMap = originalCFrameMap,

		-- Are any of the parts in the selection physically free moving
		hasPhysics = selectionHasPhysics,

		-- Instances with configurable faces
		instancesWithConfigurableFace = allInstancesWithConfigurableFace,
	}
end

local SelectionInfo = {}
SelectionInfo.__index = SelectionInfo

export type Class = setmetatable<SelectionInfo, typeof(SelectionInfo)>

function SelectionInfo.new(draggerContext: DraggerContext, selection: { Instance }): Class
	return setmetatable(computeInfo(draggerContext, selection), SelectionInfo)
end

--[[
	Core schema specific
	Used to optimize dragger performance, returns a new SelectionInfo which
	is the same as this SelectionInfo, but transformed by a world transform.
]]
function SelectionInfo.getTransformedCopy(self: Class, globalTransform: CFrame)
	local transformedOriginalCFrames = {}
	local copy = table.clone(self)

	copy.basisCFrame = globalTransform * copy.basisCFrame
	copy.localBasisCFrame = globalTransform * copy.localBasisCFrame
	
	for k, cframe in pairs(copy.originalCFrameMap) do
		transformedOriginalCFrames[k] = globalTransform * cframe
	end

	copy.originalCFrameMap = transformedOriginalCFrames
	return setmetatable(copy, SelectionInfo)
end

function SelectionInfo.isEmpty(self: Class)
	return #self.parts == 0 and #self.attachments == 0
end

function SelectionInfo.getBoundingBox(self: Class)
	return self.basisCFrame, self.boundingBoxOffset, self.boundingBoxSize
end

function SelectionInfo.doesContainItem(self: Class, item: BasePart?)
	return (item and self.partSet[item]) ~= nil
end

function SelectionInfo.isDynamic(self: Class)
	return self.hasPhysics
end

--[[
	Core schema specific
	Returns: A map of where selected parts originally were before we started
	moving them.
]]
function SelectionInfo.getOriginalCFrameMap(self: Class)
	return self.originalCFrameMap
end

--[[
	Core schema specific
	Returns: The local space bounding box even when Use Local Space is false.
]]
function SelectionInfo.getLocalBoundingBox(self: Class)
	return self.localBasisCFrame, self.localBoundingBoxOffset, self.localBoundingBoxSize
end

-- Core schema specific
function SelectionInfo.getObjectsToTransform(self: Class)
	return self.parts, self.attachments, self.models
end

-- Core schema specific
function SelectionInfo.getBasisObject(self: Class)
	return self.basisObject
end

--[[
	Core schema specific
	The attachments returned by getObjectsToTransform only includes the
	attachments which are not underneath one of the parts to transform. This
	method on the other hand, returns all of the selected attachments regardless
	of parent.
]]
function SelectionInfo.getAllAttachments(self: Class)
	return self.allAttachments
end

return SelectionInfo