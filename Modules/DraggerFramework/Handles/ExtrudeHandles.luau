--[[
	Scale tool implementation. Responsible for handle state and handle views.
]]

-- Libraries
local DraggerFramework = script.Parent.Parent
local Plugin = DraggerFramework.Parent.Parent
local React = require(Plugin.Packages.React)

-- Dragger Framework
local Utility = DraggerFramework.Utility
local Colors = require(Utility.Colors)
local Math = require(Utility.Math)

local Components = DraggerFramework.Components
local ScaleHandleView = require(Components.ScaleHandleView)
local StandaloneSelectionBox = require(Components.StandaloneSelectionBox)

local Implementation = DraggerFramework.Implementation
local DraggerContext = require(Implementation.DraggerContext)
local DraggerToolModel = require(Implementation.DraggerToolModel)
local SelectionInfo = require(Utility.SelectionInfo)

local ExtrudeHandle = {}
ExtrudeHandle.__index = ExtrudeHandle

type HandleProps = ScaleHandleView.Props
type DraggerContext = DraggerContext.Class

type DraggerToolModel = DraggerToolModel.Class
type SelectionInfo = SelectionInfo.Class

local NormalId = {
	X_AXIS = 1,
	Y_AXIS = 2,
	Z_AXIS = 3,
}

type ScaleHandleDef = {
	Color: Color3,
	Offset: CFrame,
	NormalId: number,
}

type Props = {
	Summonable: boolean?,
	ShowBoundingBox: boolean?,
}

type BoundingBox = {
	CFrame: CFrame,
	Size: Vector3,
}

type Schema = {
	getBoundingBox: (selection: any, selectionInfo: any) -> (CFrame, Vector3, Vector3),
	getMouseTarget: (draggerContext: DraggerContext, mouseRay: Ray, options: any) -> (any, BasePart?, number?),
	addUndoWaypoint: (draggerContext: DraggerContext, waypointIdentifier: string, waypointText: string?) -> (),
}

export type Implementation<T = any> = {
	beginScale: (self: T, selection: any, selectionInfo: any, normalId: number) -> (),
	updateScale: (self: T, deltaSize: Vector3, deltaOffset: Vector3) -> (Vector3, Vector3),
	endScale: (self: T) -> (),
	shouldKeepAspectRatio: (self: T, selection: any, selectionInfo: any, normalId: number) -> boolean,
	shouldScaleFromCenter: (self: T, selection: any, selectionInfo: any, normalId: number) -> boolean,
	axesToScale: (self: T, selectionInfo: any, normalId: number) -> Vector3,
	getMinMaxSizes: (self: T, selectionInfo: any, axesToScale: Vector3, currentSize: Vector3) -> (Vector3, Vector3),
	render: (self: T, deltaSize: Vector3, deltaOffset: Vector3) -> React.Node,
}

local ScaleHandleDefinitions: { [string]: ScaleHandleDef } = {
	MinusX = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.zAxis),
		Color = Colors.X_AXIS,
		NormalId = NormalId.X_AXIS,
	},
	PlusX = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, -Vector3.zAxis),
		Color = Colors.X_AXIS,
		NormalId = NormalId.X_AXIS,
	},
	MinusY = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.zAxis, Vector3.xAxis),
		Color = Colors.Y_AXIS,
		NormalId = NormalId.Y_AXIS,
	},
	PlusY = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.zAxis, -Vector3.xAxis),
		Color = Colors.Y_AXIS,
		NormalId = NormalId.Y_AXIS,
	},
	MinusZ = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, Vector3.yAxis),
		Color = Colors.Z_AXIS,
		NormalId = NormalId.Z_AXIS,
	},
	PlusZ = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, -Vector3.yAxis),
		Color = Colors.Z_AXIS,
		NormalId = NormalId.Z_AXIS,
	},
}

local BOX_CORNERS = {
	Vector3.new(0.5, 0.5, 0.5),
	Vector3.new(0.5, 0.5, -0.5),
	Vector3.new(0.5, -0.5, 0.5),
	Vector3.new(0.5, -0.5, -0.5),
	Vector3.new(-0.5, 0.5, 0.5),
	Vector3.new(-0.5, 0.5, -0.5),
	Vector3.new(-0.5, -0.5, 0.5),
	Vector3.new(-0.5, -0.5, -0.5),
}

type ExtrudeHandle = {
	_draggingHandleId: string?,
	_normalId: number?,
	_handleCFrame: CFrame?,
	_originalBoundingBoxCFrame: CFrame?,
	_originalBoundingBoxSize: Vector3?,
	_selectionInfo: any, -- SelectionInfo
	_selectionWrapper: any, -- SelectionWrapper
	_schema: Schema?, -- Schema
	_boundingBox: BoundingBox?,

	_handles: {
		[string]: HandleProps,
	},

	_summonBasisOffset: Vector3?,
	_basisOffset: Vector3?,
	_startDistance: number?,
	_minimumSize: Vector3?,
	_maximumSize: Vector3?,

	_implementation: Implementation,
	_draggerContext: DraggerContext,

	_props: Props,
	_committedDeltaSize: Vector3?,
	_committedOffset: Vector3?,
	_lastDeltaSize: Vector3?,
	_lastOffset: Vector3?,
	_lastAxesToScale: Vector3?,
	_lastResizeFromCenter: boolean?,
	_scalingLimitReachedUpper: boolean?,
	_scalingLimitReachedLower: boolean?,
	_resizeWasConstrained: boolean?,
}

type Proto = typeof(ExtrudeHandle)
export type Class = setmetatable<ExtrudeHandle, Proto>

function ExtrudeHandle.new(
	draggerContext: DraggerContext,
	props: Props,
	implementation: Implementation
): Class
	local self: ExtrudeHandle = {
		_handles = {},
		_props = props or {},
		_draggerContext = draggerContext,
		_implementation = implementation,
	}
	
	return setmetatable(self, ExtrudeHandle)
end

-- Summon handles to the current mouse hover location
function ExtrudeHandle._summonHandles(self: Class)
	if not self._props.Summonable then
		return false
	end

	local boundingBox: BoundingBox? = self._boundingBox
	local schema: Schema? = self._schema

	if not (boundingBox and schema) then
		return false
	end

	local mouseRay: Ray = self._draggerContext:getMouseRay()
	local _, hitItem, distance = schema.getMouseTarget(self._draggerContext, mouseRay, {})

	if hitItem and distance and self._selectionInfo:doesContainItem(hitItem) then
		local hitPoint = mouseRay.Origin + mouseRay.Direction.Unit * distance
		local point = boundingBox.CFrame:PointToObjectSpace(hitPoint)
		local halfSize = boundingBox.Size / 2
		self._summonBasisOffset = CFrame.new(point:Max(-halfSize):Min(halfSize))
	else
		-- Try to pick a point on the selection closest to the cursor
		local cursorOnScreen = self._draggerContext:getMouseLocation()
		local closestWorldPoint
		local closestDistanceOnScreen = math.huge
		for _, cornerOffset in ipairs(BOX_CORNERS) do
			local cornerInWorld = self._boundingBox.CFrame * CFrame.new(self._boundingBox.Size * cornerOffset)
			local cornerOnScreen, inView = self._draggerContext:worldToViewportPoint(cornerInWorld.Position)
			local distance = (cursorOnScreen - Vector2.new(cornerOnScreen.X, cornerOnScreen.Y)).Magnitude
			if inView and distance < closestDistanceOnScreen then
				closestDistanceOnScreen = distance
				closestWorldPoint = cornerInWorld
			end
		end
		if closestWorldPoint then
			self._summonBasisOffset = self._boundingBox.CFrame:ToObjectSpace(closestWorldPoint)
		end
	end

	return true
end

function ExtrudeHandle._endSummon(self: Class)
	if self._summonBasisOffset then
		self._summonBasisOffset = nil
	end
end

function ExtrudeHandle._getBasisOffset(self: Class)
	return self._summonBasisOffset or self._basisOffset
end

function ExtrudeHandle.update(self: Class, draggerToolModel: DraggerToolModel, selectionInfo: SelectionInfo)
	if not self._draggingHandleId then
		-- Don't clobber these fields while we're dragging because we're
		-- updating the bounding box in a smart way given how we're moving the
		-- parts.

		self._selectionInfo = selectionInfo
		self._schema = draggerToolModel:getSchema()
		self._selectionWrapper = draggerToolModel:getSelectionWrapper()
		
		local cframe, offset, size = self._implementation:getBoundingBox(
			self._selectionWrapper:get(), self._selectionInfo)
		
		self._boundingBox = {
			Size = size,
			CFrame = cframe * CFrame.new(offset),
		}
	end

	self:_updateHandles()
end

function ExtrudeHandle.shouldBiasTowardsObjects(self: Class)
	return true
end

-- Called when the settings we're using to drag change (when we press/release
-- the key(s) for resize from center / maintain aspect ratio)
function ExtrudeHandle._refreshDrag(self: Class)
	self._committedDeltaSize = self._lastDeltaSize
	self._committedOffset = self._lastOffset

	if self._boundingBox then
		self._originalBoundingBoxSize = self._boundingBox.Size
		self._originalBoundingBoxCFrame = self._boundingBox.CFrame
	end

	-- The edge case where you rotate your camera exactly into alignment with
	-- the axis you started the drag on and then press Ctrl will act a bit weird
	-- here, but that it's almost impossible to hit that edge case (You have to
	-- key-bind a camera alignment command).
	local hasDistance, distance =
		self:_getDistanceAlongAxis(self._draggerContext:getMouseRay())
	
	self._startDistance = hasDistance and distance or 0
end

function ExtrudeHandle._getExtrudeMode(self: Class)
	local normalId = self._normalId or 0

	local keepAspectRatio = self._implementation:shouldKeepAspectRatio(
		self._selectionWrapper:get(), self._selectionInfo, normalId)
	
	local resizeFromCenter = self._implementation:shouldScaleFromCenter(
		self._selectionWrapper:get(), self._selectionInfo, normalId)
	
	return keepAspectRatio, resizeFromCenter
end

local function areAxesSame(old: Vector3?, new: Vector3?)
	return  (old == new) or
			(old and new and
			-- false and nil mean the same thing
			(not old.X == not new.X) and
			(not old.Y == not new.Y) and
			(not old.Z == not new.Z))
end

-- "Extrude Mode" is the state of the tool that controls how scaling is done:
-- self._lastAxesToScale specifies which axes get scaled (uniform/non-uniform scale)
-- self._lastResizeFromCenter specifies whether to resize on both sides or just one
-- self._minimumSize and self._maximumSize control scaling limits (which depend on the axes scaled)
-- The Extrude Mode is determined by e.g. whether the user holds down keys such as Ctrl or Shift,
-- and can change during scaling; the Implementation controls this behavior and computes these
-- values from the state of controls.
-- This function updates the Extrude Mode that this tool uses, and returns whether it changed
-- from the last time it was computed.
function ExtrudeHandle._updateExtrudeMode(self: Class)
	local boundingBox = self._boundingBox
	local size = boundingBox and boundingBox.Size or Vector3.zero
	
	local selection = self._selectionWrapper:get()
	local selectionInfo = self._selectionInfo
	
	local normalId = self._normalId or 0
	local resizeFromCenter = self._implementation:shouldScaleFromCenter(selection, selectionInfo, normalId)
	
	local axesToScale = self._implementation:axesToScale(selectionInfo, normalId)
	self._minimumSize, self._maximumSize = self._implementation:getMinMaxSizes(selectionInfo, axesToScale, size)
	
	local axesChanged = not areAxesSame(axesToScale, self._lastAxesToScale)
	local resizeFromCenterChanged = resizeFromCenter ~= self._lastResizeFromCenter
	
	self._lastAxesToScale = axesToScale
	self._lastResizeFromCenter = resizeFromCenter
	
	return axesChanged or resizeFromCenterChanged
end

-- Returns, whether we did need to refresh the drag
function ExtrudeHandle._refreshDragIfNeeded(self: Class)
	local refreshNeeded = self:_updateExtrudeMode()
	
	if refreshNeeded and self._draggingHandleId and self._handles[self._draggingHandleId] then
		self:_refreshDrag()
	end

	return refreshNeeded
end

function ExtrudeHandle.keyDown(self: Class, keyCode: Enum.KeyCode)
	return self:_refreshDragIfNeeded()
end

function ExtrudeHandle.keyUp(self: Class, keyCode: Enum.KeyCode)
	return self:_refreshDragIfNeeded()
end

function ExtrudeHandle.hitTest(self: Class, mouseRay: Ray, ignoreExtraThreshold: boolean): (string?, number)
	local closestHandleId, closestHandleDistance = nil, math.huge
	
	for handleId, handleProps in pairs(self._handles) do
		local distance = ScaleHandleView.hitTest(handleProps, mouseRay)
		
		if distance and distance < closestHandleDistance then
			closestHandleDistance = distance
			closestHandleId = handleId
		end
	end

	if closestHandleId then
		return closestHandleId, 0
	elseif ignoreExtraThreshold then
		return nil, 0
	else
		-- Second attempt to find a handle, now using closest distance to the ray
		-- rather than closest hit distance to the camera.
		for handleId, handleProps in pairs(self._handles) do
			local distance = ScaleHandleView.distanceFromHandle(handleProps, mouseRay)
			
			if distance < closestHandleDistance then
				closestHandleDistance = distance
				closestHandleId = handleId
			end
		end

		-- Only hit a handle if we are actually inside the closest handle's
		-- extra hitTest radius.
		if closestHandleDistance < 0 then
			return closestHandleId, 0
		else
			return nil, 0
		end
	end
end

function ExtrudeHandle._getBoundingBoxColor(self: Class)
	if self._scalingLimitReachedUpper or
		self._scalingLimitReachedLower or
		self._resizeWasConstrained
	then
		return Colors.SizeLimitReached
	end

	return self._draggerContext:getSelectionBoxColor()
end

function ExtrudeHandle._getBoundingBoxThickness(self: Class)
	return self._draggerContext:getHoverLineThickness()
end

function ExtrudeHandle._shouldDrawBoundingBox(self: Class)
	return 	self._scalingLimitReachedLower or
		self._scalingLimitReachedUpper or
		self._resizeWasConstrained or
		(self._props.ShowBoundingBox and #self._selectionWrapper:get() > 1)
end

function ExtrudeHandle.render(self: Class, hoveredHandleId: string?)
	local children = {} :: {
		[string]: React.Node,
	}

	if self._draggingHandleId and self._handles[self._draggingHandleId] then
		local handleProps = self._handles[self._draggingHandleId]
		children[self._draggingHandleId] = React.createElement<<any>>(ScaleHandleView.render, {
			GuiParent = self._draggerContext:getGuiParent(),
			HandleCFrame = handleProps.HandleCFrame,
			Color = handleProps.Color,
			Scale = handleProps.Scale,
		}) :: React.Node

		for otherHandleId, otherHandleProps in pairs(self._handles) do
			if otherHandleId ~= self._draggingHandleId then
				children[otherHandleId] = React.createElement<<any>>(ScaleHandleView.render, {
					GuiParent = self._draggerContext:getGuiParent(),
					HandleCFrame = otherHandleProps.HandleCFrame,
					Color = Colors.makeDimmed(otherHandleProps.Color),
					Scale = otherHandleProps.Scale,
					Thin = true,
				}) :: React.Node
			end
		end

		children.ImplementationRendered =
			self._implementation:render(self._lastDeltaSize, self._lastOffset)
	else
		for handleId, handleProps in pairs(self._handles) do
			local color = handleProps.Color
			local hovered = (handleId == hoveredHandleId)

			if not hovered then
				color = Colors.makeDimmed(handleProps.Color)
			end
			
			children[handleId] = React.createElement<<any>>(ScaleHandleView.render, {
				GuiParent = self._draggerContext:getGuiParent(),
				HandleCFrame = handleProps.HandleCFrame,
				Color = color,
				Scale = handleProps.Scale,
				Hovered = hovered,
			}) :: React.Node
		end
	end

	-- Show selection bounding box when scaling multiple items, or when scaling limit has been reached
	if self:_shouldDrawBoundingBox() then
		local boundingBox = self._boundingBox

		if boundingBox then
			children.SelectionBoundingBox = React.createElement<<any>>(StandaloneSelectionBox, {
				CFrame = boundingBox.CFrame,
				Size = boundingBox.Size,
				Color = self:_getBoundingBoxColor(),
				LineThickness = self:_getBoundingBoxThickness(),
				Container = self._draggerContext:getGuiParent(),
			}) :: React.Node
		end
	end
	
	return React.createElement("Folder", {}, children)
end

function ExtrudeHandle.mouseDown(self: Class, mouseRay: Ray, handleId: string?)
	self._draggingHandleId = handleId

	if not (handleId and self._handles[handleId]) then
		return
	end
	self._normalId = self._handles[handleId].NormalId
	self._handleCFrame = self._handles[handleId].HandleCFrame

	local boundingBox = self._boundingBox

	if boundingBox then
		self._originalBoundingBoxCFrame = boundingBox.CFrame
		self._originalBoundingBoxSize = boundingBox.Size
	end

	self:_updateExtrudeMode()
	
	local hasDistance, distance = self:_getDistanceAlongAxis(mouseRay)
	self._startDistance = hasDistance and distance or 0.0

	-- When you change extrude modes mid drag, we need to separate the
	-- resize you've done so far from the part you will do in the new mode.
	-- The part you've done so far is the "committed" part.
	self._committedDeltaSize = Vector3.zero
	self._committedOffset = Vector3.zero

	self._lastDeltaSize = Vector3.zero
	self._lastOffset = Vector3.zero

	self._implementation:beginScale(
		self._selectionWrapper:get(),
		self._selectionInfo,
		self._normalId or 0
	)
end

-- Clamp x between min and max while changing it in increments of step (when step is nonzero)
-- Assumes max - min > step >= 0
-- One can write this code in a single formula, but since implementation of % is different in C++ and Lua,
-- this would hurt readability
local function clampWithStep(x: number, min: number, max: number, step: number): number
	if x < min then
		if step > 0 then
			return min + (step - (min - x) % step)
		else
			return min
		end
	elseif x > max then
		if step > 0 then
			return max - (step - (x - max) % step)
		else
			return max
		end
	end
	return x
end

local function computeDeltaSizeMultiaxis(originalSize: Vector3, delta: number, axisId: number, axesToScale: any, gridStep: number, minSize: Vector3, maxSize: Vector3): (Vector3, number)
	if gridStep < 0.01 then
		gridStep = 0
	end

	local originalSizeArray = Math.vectorToArray(originalSize)
	local minDeltaSizeArray = Math.vectorToArray(minSize - originalSize)
	local maxDeltaSizeArray = Math.vectorToArray(maxSize - originalSize)

	local actualDelta = clampWithStep(delta, minDeltaSizeArray[axisId],  maxDeltaSizeArray[axisId], gridStep)
	local ratio = actualDelta / originalSizeArray[axisId]
	local deltaSize = originalSize * Math.setToVector3(axesToScale) * ratio
	
	return deltaSize, actualDelta
end

function ExtrudeHandle.mouseDrag(self: Class, mouseRay: Ray)
	--assert(self._draggingHandleId, "Missing dragging handle ID.")
	if not self._draggingHandleId then
		return
	end

	if not self._handles[self._draggingHandleId] then
		return
	end

	-- The settings used for the drag may have changed.
	-- Return value intentionally ignored, we're already in the process of
	-- updating the drag, so we're doing the drag update anyways regardless
	-- of whether a refresh was needed due to a settings change.
	self:_refreshDragIfNeeded()

	local hasDistance, distance = self:_getDistanceAlongAxis(mouseRay)
	if not hasDistance then
		return
	end

	local dragDistance = distance - self._startDistance
	local delta = self._draggerContext:snapToGridSize(dragDistance)
	local handleProps = self._handles[self._draggingHandleId]
	local normalId = handleProps.NormalId
	local axis = handleProps.Axis

	local localOffset
	if self._lastResizeFromCenter then
		delta = delta * 2
		localOffset = Vector3.zero
	else
		localOffset = axis * 0.5 * delta
	end

	-- Determine the size change for the selection
	local originalSize = self._originalBoundingBoxSize
	local deltaSize, actualDelta

	local axesToScale = self._lastAxesToScale
	local gridSize = self._draggerContext:getGridSize()
	local minSize = self._minimumSize
	local maxSize = self._maximumSize

	deltaSize, actualDelta = computeDeltaSizeMultiaxis(
		originalSize, delta, 
		normalId, axesToScale, 
		gridSize, minSize, maxSize
	)

	if delta ~= 0 then
		localOffset = localOffset * (actualDelta / delta)
	end

	self._scalingLimitReachedUpper = delta - actualDelta > 0
	self._scalingLimitReachedLower = actualDelta - delta > 0

	local deltaSizeToApply = deltaSize + self._committedDeltaSize
	local localOffsetToApply = localOffset + self._committedOffset

	-- Eliminate floating-point error for edits that don't have any visible impact
	if deltaSizeToApply:FuzzyEq(Vector3.zero) then
		deltaSizeToApply = Vector3.zero
	end

	if localOffsetToApply:FuzzyEq(Vector3.zero) then
		localOffsetToApply = Vector3.zero
	end

	self._lastDeltaSize, self._lastOffset =
		self._implementation:updateScale(deltaSizeToApply, localOffsetToApply)
	
	self._resizeWasConstrained = (deltaSizeToApply ~= self._lastDeltaSize)
	self._boundingBox.CFrame = self._originalBoundingBoxCFrame * CFrame.new(self._lastOffset - self._committedOffset)
	self._boundingBox.Size = originalSize + (self._lastDeltaSize - self._committedDeltaSize)
end

function ExtrudeHandle.mouseUp(self: Class, mouseRay: Ray)
	if self._draggingHandleId and self._handles[self._draggingHandleId] then
		self._implementation:endScale()
	end

	self._draggingHandleId = nil
	self._scalingLimitReachedUpper = false
	self._scalingLimitReachedLower = false
	self._resizeWasConstrained = false

	if self._schema then
		self._schema.addUndoWaypoint(self._draggerContext, "Scale Selection")
	end
end

function ExtrudeHandle._getDistanceAlongAxis(self: Class, mouseRay: Ray)
	local bboxCFrame = self._originalBoundingBoxCFrame or CFrame.identity
	local handleCFrame = self._handleCFrame or CFrame.identity
	local axis = handleCFrame.LookVector

	return Math.intersectRayRay(bboxCFrame.Position, axis, mouseRay.Origin, mouseRay.Direction.Unit)
end

function ExtrudeHandle._updateHandles(self: Class)
	local boundingBox = self._boundingBox

	if not boundingBox then
		self._handles = {}
		return
	end

	if self._selectionInfo:isEmpty() or boundingBox.Size:FuzzyEq(Vector3.zero) then
		-- Can't scale something with a zero size.
		self._handles = {}
	else
		for handleId, handleDefinition in pairs(ScaleHandleDefinitions) do
			-- Offset the handle's base position by the size of the bounding
			-- box on that handle's axis.
			local offset = handleDefinition.Offset
			
			local localSize = offset:Inverse():VectorToWorldSpace(boundingBox.Size)
			local boundingBoxOffset = 0.5 * math.abs(localSize.Z)
			local handleBaseCFrame = boundingBox.CFrame * offset * CFrame.new(0, 0, -boundingBoxOffset)

			self._handles[handleId] = {
				Color = handleDefinition.Color,
				Axis = offset.LookVector,
				HandleCFrame = handleBaseCFrame,
				NormalId = handleDefinition.NormalId,
				Scale = self._draggerContext:getHandleScale(handleBaseCFrame.Position),
				Thin = false,
				Hovered = false,
			}
		end
	end
end

return ExtrudeHandle
