local DraggerSchemaCore = script.Parent
local Packages = DraggerSchemaCore.Parent

local DraggerFramework = require(Packages.DraggerFramework)
local Utility = DraggerFramework.Utility

local AttachmentMover = Utility.AttachmentMover
local DragHelper = Utility.DragHelper
local PartMover = Utility.PartMover

local FreeformDragger = {}
FreeformDragger.__index = FreeformDragger

type DraggerContext = DraggerFramework.DraggerContext
type DraggerToolModel = DraggerFramework.DraggerToolModel
type AttachmentMover = DraggerFramework.AttachmentMover
type DragTarget = DraggerFramework.DragTarget
type JointPairs = DraggerFramework.JointPairs
type PartMover = DraggerFramework.PartMover

type DragInfo = {
	clickPoint: Vector3?,
	basisPoint: Vector3,
	attachmentBeingDragged: Attachment?,
}

export type FreeformDragInfo = {
	basisPoint: Vector3,
	clickPoint: Vector3,
	clickedFaceInstance: Instance?,
	attachmentBeingDragged: Attachment?,
}

type FreeformDragger = {
	_draggerContext: DraggerContext,
	_draggerToolModel: DraggerToolModel,
	_dragInfo: FreeformDragInfo,

	_partMover: PartMover,
	_attachmentMover: AttachmentMover,

	_tiltRotate: CFrame,
	_lastAppliedTransform: CFrame,
	_jointPairs: JointPairs?,

	_lastDragTarget: DragTarget?,
	_raycastFilter: { BasePart },
}

type Proto = typeof(FreeformDragger)
export type Class = setmetatable<FreeformDragger, Proto>

function FreeformDragger.new(draggerContext: DraggerContext, draggerToolModel: DraggerToolModel, dragInfo: FreeformDragInfo)
	local self = setmetatable({
		_draggerContext = draggerContext,
		_draggerToolModel = draggerToolModel,
		_dragInfo = dragInfo,

		_partMover = PartMover.new(),
		_attachmentMover = AttachmentMover.new(),
		_tiltRotate = CFrame.identity,
		_lastAppliedTransform = CFrame.identity,

		_raycastFilter = {},
	}, FreeformDragger) :: Class

	self:_init()
	return self
end

function FreeformDragger._init(self: Class)
	self:_initIgnoreList(self._draggerToolModel._selectionInfo:getObjectsToTransform())
	self:_initMovers()
end

function FreeformDragger._initMovers(self: Class)
	local breakJointsToOutsiders = not self._draggerToolModel._draggerContext:areConstraintsEnabled()

	local partsToMove, attachmentsToMove, modelsToMove =
		self._draggerToolModel._selectionInfo:getObjectsToTransform()
	
	self._partMover:setDragged(
		partsToMove,
		self._draggerToolModel._selectionInfo:getOriginalCFrameMap(),
		breakJointsToOutsiders,
		self._draggerToolModel._selectionInfo:getBoundingBox().Position,
		self._draggerToolModel:getSelectionWrapper():get(),
		modelsToMove)
	
	self._attachmentMover:setDragged(attachmentsToMove)
end

function FreeformDragger._initIgnoreList(self: Class, parts: { BasePart })
	local filter = table.create<<BasePart>>(#parts + 1)

	for i, part in ipairs(parts) do
		filter[i] = part
	end

	local ignorePart = self._partMover:getIgnorePart()

	if ignorePart then
		table.insert(filter, ignorePart)
	end

	self._raycastFilter = filter
end

function FreeformDragger.render(self: Class)
	if self._draggerToolModel._draggerContext:shouldJoinSurfaces() and self._jointPairs then
		local cframe, offset = self._draggerToolModel._selectionInfo:getBoundingBox()
		local focus = cframe * offset
		return self._jointPairs:renderJoints(self._draggerToolModel._draggerContext:getHandleScale(focus))
	end
end

function FreeformDragger.rotate(self: Class, axis: Vector3)
	if self._draggerToolModel._draggerContext:areConstraintsEnabled() then
		return
	end

	local mainCFrame = self._draggerToolModel._selectionInfo:getLocalBoundingBox()
	local lastTargetMatrix = CFrame.identity

	if self._lastDragTarget then
		lastTargetMatrix = self._lastDragTarget.targetMatrix or CFrame.identity
	end

	self._tiltRotate = DragHelper.updateTiltRotate(
		workspace.CurrentCamera.CFrame,
		self._draggerToolModel._draggerContext:getMouseRay(),
		self._raycastFilter :: { Instance }, mainCFrame, lastTargetMatrix,
		self._tiltRotate, axis, self._draggerToolModel:shouldAlignDraggedObjects())
end

function FreeformDragger._updateGeometric(self: Class)
	local lastTargetMatrix = nil

	if self._lastDragTarget then
		lastTargetMatrix = self._lastDragTarget.targetMatrix
	end

	local function snapFunction(distance: number): number
		return self._draggerContext:snapToGridSize(distance)
	end

	local localBoundingBoxCFrame, localBoundingBoxOffset, localBoundingBoxSize =
		self._draggerToolModel._selectionInfo:getLocalBoundingBox()
	
	local dragTarget = DragHelper.getDragTarget(
		self._draggerToolModel._draggerContext:getMouseRay(),
		snapFunction,
		self._dragInfo.clickPoint,
		self._raycastFilter :: { Instance },
		localBoundingBoxCFrame,
		self._dragInfo.basisPoint,
		localBoundingBoxSize,
		localBoundingBoxOffset,
		self._tiltRotate,
		lastTargetMatrix or CFrame.identity,
		self._draggerToolModel:shouldAlignDraggedObjects(),
		localBoundingBoxSize
	)

	if dragTarget then
		self._lastDragTarget = dragTarget
		local originalCFrame = localBoundingBoxCFrame
		local newCFrame = dragTarget.mainCFrame
		local globalTransform = newCFrame * originalCFrame:Inverse()
		self._partMover:transformTo(globalTransform)
		self._attachmentMover:transformTo(globalTransform)
		self._lastAppliedTransform = globalTransform

		if self._draggerToolModel._draggerContext:shouldJoinSurfaces() then
			self._jointPairs = self._partMover:computeJointPairs(globalTransform)
		end
	end
end

function FreeformDragger._updatePhysical(self: Class)
	local localBoundingBoxCFrame =
		self._draggerToolModel._selectionInfo:getLocalBoundingBox()

	if not self._dragInfo.clickPoint then
		return
	end

	local dragTarget = DragHelper.getCameraPlaneDragTarget(
		self._draggerToolModel._draggerContext:getMouseRay(),
		workspace.CurrentCamera.CFrame.LookVector,
		localBoundingBoxCFrame:pointToWorldSpace(self._dragInfo.clickPoint))

	if dragTarget then
		local collisionsMode =
			self._draggerToolModel._draggerContext:areCollisionsEnabled() and
			Enum.IKCollisionsMode.IncludeContactedMechanisms or
			Enum.IKCollisionsMode.NoCollisions
		local actualGlobalTransformUsed =
			self._partMover:moveToWithIk(dragTarget.mainCFrame, collisionsMode)
		self._attachmentMover:transformTo(actualGlobalTransformUsed)
		self._lastAppliedTransform = actualGlobalTransformUsed
	end
end

function FreeformDragger.update(self: Class)
	if self._draggerToolModel._draggerContext:areConstraintsEnabled() then
		self:_updatePhysical()
	else
		self:_updateGeometric()
	end
end

function FreeformDragger.destroy(self: Class)
	local attachment = self._dragInfo.attachmentBeingDragged
	if attachment then
		-- Single attachment being dragged case -- In that case we need to
		-- potentially reparent the attachment to the part it was dragged onto.
		local mouseRay = self._draggerToolModel._draggerContext:getMouseRay()
		local worldResult = workspace:Raycast(mouseRay.Origin, mouseRay.Direction)

		if worldResult then
			local worldHit = worldResult.Instance
			local worldCFrame = attachment.WorldCFrame

			if attachment.Parent ~= worldHit then
				-- pcall as the dragged attachment may have been Destroyed.
				pcall(function()
					attachment.Parent = worldHit
				end)

				attachment.WorldCFrame = worldCFrame
			end
		else
			-- When there's no valid target, reset the AttachmentMover so we
			-- don't move the attachment.
			self._attachmentMover:transformTo(CFrame.identity)
		end
	end
	
	if self._draggerToolModel._draggerContext:shouldJoinSurfaces() and self._jointPairs then
		self._jointPairs:createJoints()
	end
	
	self._jointPairs = nil
	self._partMover:commit()
	self._attachmentMover:commit()

	-- Return an updated SelectionInfo to prevent the DraggerFramework from
	-- computing fresh one from scratch (it would do that by default if we
	-- did not return anything).
	-- The additional info we have lets us compute the new one more efficiently
	-- by deriving it from the old one based on the operation we did.
	return self._draggerToolModel._selectionInfo:getTransformedCopy(self._lastAppliedTransform)
end

return FreeformDragger