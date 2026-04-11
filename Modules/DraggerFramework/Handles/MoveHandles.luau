
-- Libraries
local DraggerFramework = script.Parent.Parent
local Utility = DraggerFramework.Utility

local Shared = DraggerFramework.Parent
local React = require(Shared.React)

local Colors = require(Utility.Colors)
local SelectionInfo = require(Utility.SelectionInfo)
local computeDraggedDistance = require(Utility.computeDraggedDistance)

local Components = DraggerFramework.Components
local MoveHandleView = require(Components.MoveHandleView)
local StandaloneSelectionBox = require(Components.StandaloneSelectionBox)

local Implementation = DraggerFramework.Implementation
local DraggerContext = require(Implementation.DraggerContext)
local DraggerToolModel = require(Implementation.DraggerToolModel)

local ALWAYS_ON_TOP = true

local MoveHandles = {}
MoveHandles.__index = MoveHandles

type MoveHandleDef = {
	HideWhenTempPart: boolean?,
	Offset: CFrame,
	Color: Color3,
}

type HandleProps = MoveHandleView.Props
type SelectionInfo = SelectionInfo.Class
type DraggerContext = DraggerContext.Class
type DraggerToolModel = DraggerToolModel.Class

local MoveHandleDefinitions: { [string]: MoveHandleDef } = {
	MinusZ = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.new(1, 0, 0), Vector3.new(0, 1, 0)),
		Color = Colors.Z_AXIS,
	},
	PlusZ = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.new(1, 0, 0), Vector3.new(0, -1, 0)),
		Color = Colors.Z_AXIS,
	},
	MinusY = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.new(1, 0, 0)),
		Color = Colors.Y_AXIS,
		HideWhenTempPart = true,
	},
	PlusY = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0)),
		Color = Colors.Y_AXIS,
		HideWhenTempPart = true,
	},
	MinusX = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(0, 0, 1)),
		Color = Colors.X_AXIS,
	},
	PlusX = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(0, 0, -1)),
		Color = Colors.X_AXIS,
	},
}

type Props = {
	Outset: number?,
	Summonable: boolean?,
	ShowBoundingBox: boolean?,
}

type MoveHandles = {
	_handles: {
		[string]: HandleProps
	},

	_draggingHandleId: string?,
	_draggingOriginalBoundingBoxCFrame: CFrame?,
	_lastGlobalTransformForRender: CFrame?,
	_draggingHandleFrac: number?,
	_startDistance: number,
	_axis: Vector3,

	_boundingBox: {
		CFrame: CFrame,
		Size: Vector3,
	},

	_basisOffset: CFrame?,
	_summonBasisOffset: CFrame?,

	_schema: any,
	_selectionWrapper: any,
	_selectionInfo: SelectionInfo?,
	_implementation: Implementation,

	_props: Props,
	_draggerContext: DraggerContext,
}

type Proto = typeof(MoveHandles)
export type Class = setmetatable<MoveHandles, Proto>

export type Implementation = {
	beginDrag: (self: any, selection: { [number]: Instance }, selectionInfo: any) -> (),
	updateDrag: (self: any, globalTransform: CFrame) -> CFrame,
	endDrag: (self: any) -> any?,
	render: (self: any, handleCFrame: CFrame) -> React.ReactElement<any>,
	getSnapPoints: (self: any) -> {CFrame}?,
}

function MoveHandles.new(
	draggerContext: DraggerContext,
	props: Props,
	implementation: any
): Class
	local self: MoveHandles = {
		_handles = {},

		_props = props or {
			Summonable = true,
		},

		_draggerContext = draggerContext,
		_implementation = implementation,
		_tabKeyDown = false,
		_selectionInfo = nil,

		_boundingBox = {
			CFrame = CFrame.identity,
			Size = Vector3.one,
		},

		_axis = Vector3.zero,
		_startDistance = 0,
	}

	return setmetatable(self, MoveHandles) :: Class
end

function MoveHandles.update(self: Class, draggerToolModel: DraggerToolModel, selectionInfo: SelectionInfo)
	if not self._draggingHandleId then
		-- Don't clobber these fields while we're dragging because we're
		-- updating the bounding box in a smart way given how we're moving the
		-- parts.
		local cframe, offset, size = selectionInfo:getBoundingBox()
		self._basisOffset = CFrame.new(-offset) -- negative since relative to bounding box
		self._boundingBox = {
			Size = size,
			CFrame = cframe * CFrame.new(offset),
		}
		self._schema = draggerToolModel:getSchema()
		self._selectionWrapper = draggerToolModel:getSelectionWrapper()
		self._selectionInfo = selectionInfo
	end

	self:_updateHandles()
end

function MoveHandles._getBasisOffset(self: Class)
	return self._summonBasisOffset or self._basisOffset or CFrame.identity
end

function MoveHandles.shouldBiasTowardsObjects(self: Class)
	return false
end

function MoveHandles.hitTest(self: Class, mouseRay, ignoreExtraThreshold)
	local closestHandleId, closestHandleDistance = nil, math.huge

	for handleId, handleProps in pairs(self._handles) do
		local distance = MoveHandleView.hitTest(handleProps, mouseRay)

		if distance and distance < closestHandleDistance then
			closestHandleDistance = distance
			closestHandleId = handleId
		end
	end

	return closestHandleId, closestHandleDistance, ALWAYS_ON_TOP
end

function MoveHandles.render(self: Class, hoveredHandleId: string?)
	local children = {} :: {
		[string]: React.Node
	}

	if self._draggingHandleId and self._handles[self._draggingHandleId] then
		local handleProps = self._handles[self._draggingHandleId]

		children[self._draggingHandleId] = React.createElement<<any>>(MoveHandleView.render, {
			GuiParent = self._draggerContext:getGuiParent(),
			Axis = handleProps.Axis,
			Outset = handleProps.Outset,
			Color = handleProps.Color,
			Scale = handleProps.Scale,
			AlwaysOnTop = ALWAYS_ON_TOP,
			Hovered = false,
		}) :: React.Node

		for otherHandleId, otherHandleProps in pairs(self._handles) do
			if otherHandleId ~= self._draggingHandleId then
				children[otherHandleId] = React.createElement<<any>>(MoveHandleView.render, {
					GuiParent = self._draggerContext:getGuiParent(),
					Color = otherHandleProps.Color,
					Axis = otherHandleProps.Axis,
					Outset = handleProps.Outset,
					Scale = otherHandleProps.Scale,
					AlwaysOnTop = ALWAYS_ON_TOP,
					Thin = true,
				}) :: React.Node
			end
		end

		children.ImplementationRendered = self._implementation:render(self._boundingBox.CFrame * self:_getBasisOffset())
	else
		for handleId, handleProps in pairs(self._handles) do
			local color = handleProps.Color
			local hovered = (handleId == hoveredHandleId)
			local shading = hovered and Enum.AdornShading.XRay or Enum.AdornShading.XRayShaded

			children[handleId] = React.createElement<<any>>(MoveHandleView.render, {
				GuiParent = self._draggerContext:getGuiParent(),
				Axis = handleProps.Axis,
				Outset = handleProps.Outset,
				Color = color,
				Scale = handleProps.Scale,
				Shading = shading,
				Hovered = hovered,
			}) :: React.Node
		end
	end

	if self._props.ShowBoundingBox and #self._selectionWrapper:get() > 1 then
		children.SelectionBoundingBox = React.createElement<<any>>(StandaloneSelectionBox, {
			CFrame = self._boundingBox.CFrame,
			Size = self._boundingBox.Size,
			Color = self._draggerContext:getSelectionBoxColor(),
			LineThickness = self._draggerContext:getHoverLineThickness(),
			Container = self._draggerContext:getGuiParent(),
		}) :: React.Node
	end

	return React.createElement("Folder", {}, children)
end

function MoveHandles.mouseDown(self: Class, mouseRay: Ray, handleId: string)
	local boundingBox = self._boundingBox
	self._draggingHandleId = handleId

	if boundingBox then
		self._draggingOriginalBoundingBoxCFrame = boundingBox.CFrame
	else
		self._draggingOriginalBoundingBoxCFrame = nil
	end

	-- Calculate fraction of the way along the handle to "stick" the cursor to
	if self._handles[handleId] then
		self:_setupMoveAtCurrentBoundingBox(mouseRay)

		local handleProps = self._handles[handleId]
		local handleOffset, handleLength =
			MoveHandleView.getHandleDimensionForScale(handleProps.Scale)
		
		local startDist = self._startDistance or 0
		self._draggingHandleFrac = (startDist - handleOffset) / handleLength
	end

	self._implementation:beginDrag(self._selectionWrapper:get(), self._selectionInfo)
end

function MoveHandles._setupMoveAtCurrentBoundingBox(self: Class, mouseRay: Ray)
	local boundingBox = self._boundingBox
	local draggingHandleId = self._draggingHandleId
	local offset = draggingHandleId and MoveHandleDefinitions[draggingHandleId].Offset

	if boundingBox and offset then
		local axis = (boundingBox.CFrame * offset).LookVector
		self._axis = axis

		local hasDistance, distance = self:_getDistanceAlongAxis(mouseRay)
		self._startDistance = hasDistance and distance or 0.0
		self._lastGlobalTransformForRender = CFrame.identity
	end
end

function MoveHandles._setMidMoveBoundingBox(self: Class, newBoundingBoxCFrame: CFrame)
	self._boundingBox.CFrame = newBoundingBoxCFrame
end

--[[
	Returns the distance the mouse cursor was dragged along handle axis
]]
function MoveHandles._getDistanceAlongAxis(self: Class, mouseRay: Ray): (boolean, number)
	local draggedFrame = self._draggingOriginalBoundingBoxCFrame or CFrame.identity
	local dragStartPosition = draggedFrame.Position
	local dragDirection = self._axis.Unit
	return computeDraggedDistance(dragStartPosition, dragDirection, mouseRay)
end


--[[
	We want to keep the mouse cursor snapped to a point a constant fraction of
	the way down the handle length over the whole duration of a move. This is
	non-trivial, as the distance along the handle depends on the scale of the
	handle, but the scale of the handle depends on how far it has been moved
	relative to the camera.

	We must solve a non-linear equation satisfying the constraint:
		fraction of distance along handle at new location
		equals
		fraction of distance along handle at start location

	Do this using a binary search over the potential solution space.
]]
function MoveHandles._solveForAdjustedDistance(self: Class, unadjustedDistance: number): number
	local draggingHandleId = self._draggingHandleId

	if not draggingHandleId or not self._handles[draggingHandleId] then
		return unadjustedDistance
	end
	
	local handleRotation = MoveHandleDefinitions[draggingHandleId].Offset

	local function getScaleForDistance(distance: number)
		local bboxCFrame = self._draggingOriginalBoundingBoxCFrame or CFrame.identity
		local startDist = self._startDistance or 0
		local axis = self._axis

		local boundingBoxAtDistance = bboxCFrame + (axis * (distance - startDist))
		local baseCFrameAtDistance = boundingBoxAtDistance * handleRotation
		
		return self._draggerContext:getHandleScale(baseCFrameAtDistance.Position)
	end

	local function getHandleFracForDistance(distance: number)
		local scale = getScaleForDistance(distance)
		local startDist = self._startDistance or 0

		local handleOffset, handleLength = MoveHandleView.getHandleDimensionForScale(scale)
		local intoDist = unadjustedDistance - distance + startDist

		return (intoDist - handleOffset) / handleLength
	end

	local function getHandleLengthForDistance(distance: number)
		local _, handleLength = MoveHandleView.getHandleDimensionForScale(getScaleForDistance(distance))
		return handleLength
	end

	-- Establish the bounds on the binary search for a good distance. Using
	-- max(originalLength, newLength) is a bit of a hack.
	-- abs(originalLength - newLength) is the more mathematically appropriate
	-- expression for how much unadjustedDistance might be off by, but it's too
	-- "sharp", and slightly misses including the solution we're looking for
	-- sometimes. Using the larger interval with max works too, it's just doing
	-- slightly more work than it should really have to.
	local originalHandleLength = getHandleLengthForDistance(0)
	local currentHandleLength = getHandleLengthForDistance(unadjustedDistance)
	local handleSizeDifference = math.max(originalHandleLength, currentHandleLength)
	local minPossibleDistance = unadjustedDistance - handleSizeDifference
	local maxPossibleDistance = unadjustedDistance + handleSizeDifference
	local fracAtMin = getHandleFracForDistance(minPossibleDistance)
	local fracAtMax = getHandleFracForDistance(maxPossibleDistance)

	-- Do the binary search
	local iterationCount = 0

	while math.abs(minPossibleDistance - maxPossibleDistance) > 0.0001 and iterationCount < 32 do
		local mid = 0.5 * (minPossibleDistance + maxPossibleDistance)
		local fracAtMid = getHandleFracForDistance(mid)
		local handleFrac = self._draggingHandleFrac or 0

		if (handleFrac - fracAtMid) * (fracAtMax - fracAtMin) > 0 then
			minPossibleDistance = mid
			fracAtMin = fracAtMid
		else
			maxPossibleDistance = mid
			fracAtMax = fracAtMid
		end
	end

	return minPossibleDistance
end

function MoveHandles._getSnappedDelta(self: Class, delta: number)
	local snapPoints

	if self._implementation.getSnapPoints then
		snapPoints = self._implementation:getSnapPoints()
	end

	if snapPoints then
		-- We deliberately don't use self:_getBasisOffset() here, because we want to snap
		-- the actual basis point of the selection to the snap points, not the position the
		-- handles are visually at.
		local bboxCFrame = self._draggingOriginalBoundingBoxCFrame or CFrame.identity
		local basisOffset = self._basisOffset or CFrame.identity

		local basePoint = (bboxCFrame * basisOffset).Position
		local axis = self._axis or Vector3.zero

		local maxDistanceAlongAxis = -math.huge
		local minDistanceAlongAxis = math.huge

		local closenessToDelta = math.huge
		local bestDistanceAlongAxis = math.huge

		for _, point in ipairs(snapPoints) do
			local dist = (point.Position - basePoint):Dot(axis)
			maxDistanceAlongAxis = math.max(maxDistanceAlongAxis, dist)
			minDistanceAlongAxis = math.min(minDistanceAlongAxis, dist)

			local absDist = math.abs(dist - delta)
			if absDist < closenessToDelta then
				closenessToDelta = absDist
				bestDistanceAlongAxis = dist
			end
		end

		if delta > maxDistanceAlongAxis or delta < minDistanceAlongAxis then
			-- Point is outside of the bounds of the snap points, use the grid
			-- snap instead if it is closer than the snap point.
			local gridSnappedDelta = self._draggerContext:snapToGridSize(delta)
			local closenessToGrid = math.abs(gridSnappedDelta - delta)

			if closenessToDelta < closenessToGrid then
				return bestDistanceAlongAxis
			else
				return gridSnappedDelta
			end
		else
			-- Point is within the bounds of the snap points, use the distance
			-- to the closest snap point.
			return bestDistanceAlongAxis
		end
	else
		return self._draggerContext:snapToGridSize(delta)
	end
end

function MoveHandles.mouseDrag(self: Class, mouseRay: Ray)
	local hasDistance, distance = self:_getDistanceAlongAxis(mouseRay)

	if not hasDistance then
		return
	end

	local handleId = self._draggingHandleId

	if not (handleId and self._handles[handleId]) then
		return
	end
	
	local startDist = self._startDistance or 0
	local delta = self:_solveForAdjustedDistance(distance) - startDist
	local snappedDelta = self:_getSnappedDelta(delta)

	-- Let the implementation figure out what global transform can actually be
	-- applied (because there may be collisions / constraints involved)
	local axis = self._axis or Vector3.zero

	local actualGlobalTransform = self._implementation:updateDrag(CFrame.new(axis * snappedDelta))
	assert(actualGlobalTransform ~= nil, "Did not return a transform from updateDrag.")

	-- Set the new resulting CFrame
	local bboxCFrame = self._draggingOriginalBoundingBoxCFrame or CFrame.identity
	self:_setMidMoveBoundingBox(actualGlobalTransform * bboxCFrame)
	self._lastGlobalTransformForRender = actualGlobalTransform
end

function MoveHandles.mouseUp(self: Class, mouseRay: Ray)
	self._draggingHandleId = nil
	local newSelectionInfoHint = self._implementation:endDrag()
	self._schema.addUndoWaypoint(self._draggerContext, "Axis Move Selection")
	return newSelectionInfoHint
end

function MoveHandles._updateHandles(self: Class)
	local selectionInfo = self._selectionInfo
	
	if selectionInfo and selectionInfo:isEmpty() then
		self._handles = {}
	else
		for handleId, handleDef in pairs(MoveHandleDefinitions) do
			local bboxCFrame = self._boundingBox.CFrame
			local handleBaseCFrame = bboxCFrame * self:_getBasisOffset() * handleDef.Offset
			
			self._handles[handleId] = {
				Outset = self._props.Outset,
				Axis = handleBaseCFrame,
				Color = handleDef.Color,
				Scale = self._draggerContext:getHandleScale(handleBaseCFrame.Position),
				AlwaysOnTop = ALWAYS_ON_TOP,
				Thin = false,
				Hovered = false,
			}
		end
	end
end

return MoveHandles
