
-- Libraries
local DraggerFramework = script.Parent.Parent
local Shared = DraggerFramework.Parent
local React = require(Shared.React)

-- Dragger Framework
local Utility = DraggerFramework.Utility
local Colors = require(Utility.Colors)
local Math = require(Utility.Math)
local roundRotation = require(Utility.roundRotation)

local Components = DraggerFramework.Components
local RotateHandleView = require(Components.RotateHandleView)
local StandaloneSelectionBox = require(Components.StandaloneSelectionBox)

local Implementation = DraggerFramework.Implementation
local DraggerContext = require(Implementation.DraggerContext)
local DraggerToolModel = require(Implementation.DraggerToolModel)

-- The minimum rotate increment to display snapping increments for (below this
-- increment there are so many points that they become visual noise)
local MIN_ROTATE_INCREMENT = 5.0

local RIGHT_ANGLE = math.pi / 2
local RIGHT_ANGLE_EXACT_THRESHOLD = 0.001

local RotateHandles = {}
RotateHandles.__index = RotateHandles

--[[
	Axis of rotation is the CFrame right vector.
	RadiusOffset slightly bumps the arc radii so that we can control which one
	shows up on top where they intersect.
]]

type RotateHandleDef = {
	Offset: CFrame,
	Color: Color3,
	RadiusOffset: number,
	HideWhenTempPart: boolean?,
}

type Props = {
	Summonable: boolean?,
	ShowBoundingBox: boolean?,
}

type HandleProps = RotateHandleView.Props
type DraggerContext = DraggerContext.Class
type DraggerToolModel = DraggerToolModel.Class

export type Implementation<T = any> = {
	beginDrag: (self: T, selection: { [number]: Instance }, selectionInfo: any) -> (),
	updateDrag: (self: T, globalTransform: CFrame) -> CFrame,
	endDrag: (self: T) -> any?,
	render: (self: T, handleCFrame: CFrame) -> React.ReactElement<any>,
}

type RotateHandles = {
	_draggerContext: DraggerContext,
	_handles: { [string]: HandleProps },
	_props: Props,
	_implementation: Implementation,

	_draggingHandleId: string?,
	_handleCFrame: CFrame,
	_startAngle: number,
	_draggingLastGoodDelta: number,
	_originalBoundingBoxCFrame: CFrame?,
	_lastGlobalTransformForRender: CFrame?,

	_boundingBox: {
		CFrame: CFrame,
		Size: Vector3,
	},

	_basisOffset: CFrame,
	_selectionInfo: any,
	_selectionWrapper: any,
	_tabKeyDown: boolean,

	_schema: any,
	_scale: number,
}

type Proto = typeof(RotateHandles)
export type Class = setmetatable<RotateHandles, Proto>

local RotateHandleDefinitions: { [string]: RotateHandleDef } = {
	XAxis = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, Vector3.yAxis, Vector3.zAxis),
		Color = Colors.X_AXIS,
		RadiusOffset = 0.00,
		HideWhenTempPart = true,
	},

	YAxis = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.zAxis, Vector3.xAxis),
		Color = Colors.Y_AXIS,
		RadiusOffset = 0.01,
	},

	ZAxis = {
		Offset = CFrame.fromMatrix(Vector3.zero, Vector3.zAxis, Vector3.xAxis, Vector3.yAxis),
		Color = Colors.Z_AXIS,
		RadiusOffset = 0.02,
		HideWhenTempPart = true,
	},
}

local function isRightAngle(angleDelta: number)
	local snappedTo90 = math.floor((angleDelta / RIGHT_ANGLE) + 0.5) * RIGHT_ANGLE
	return math.abs(snappedTo90 - angleDelta) < RIGHT_ANGLE_EXACT_THRESHOLD
end

local function getRotationTransform(mainCFrame: CFrame, axisVector: Vector3, delta: number, rotateIncrement: number)
	local localAxis = mainCFrame:VectorToObjectSpace(axisVector)
	local rotationCFrame = CFrame.fromAxisAngle(localAxis, delta)

	-- Special case rotations in 90 degree increments as a permutation of
	-- the identity matrix rather than numerically calculating an axis
	-- rotation which would introduce floating point error.
	if rotateIncrement > 0 and isRightAngle(delta) then
		-- Since we know that this is already almost a right angle rotation
		-- thanks to the isRightAngle check, we can find the pure
		-- permutation rotation matrix simply by rounding the rotation
		-- matrix elements to the nearest integer.
		rotationCFrame = roundRotation(rotationCFrame)
	end

	-- Convert the rotation to a global space transformation
	return mainCFrame * rotationCFrame * mainCFrame:Inverse()
end

--[[
	Find the angle around the rotation axis where the mouse ray intersects the
	plane perpendicular to the rotation axis.
]]
local function rotationAngleFromRay(cframe: CFrame, unitRay: Ray): number?
	local t = Math.intersectRayPlane(unitRay.Origin, unitRay.Direction, cframe.Position, cframe.RightVector)
	
	if t >= 0 then
		local mouseWorld = unitRay.Origin + unitRay.Direction * t
		local direction = (mouseWorld - cframe.Position).Unit

		local rx = cframe.LookVector:Dot(direction)
		local ry = cframe.UpVector:Dot(direction)

		-- Remap into [0, 2pi] for better snapping behavior with not
		-- evenly divisible snapping angles.
		local theta = math.atan2(ry, rx)

		if theta < 0 then
			return 2 * math.pi + theta
		else
			return theta
		end
	end

	return nil
end

local function snapToRotateIncrementIfNeeded(angle: number, rotateIncrement: number)
	if rotateIncrement > 0 then
		local angleIncrement = math.rad(rotateIncrement)
		local snappedAngle = math.floor(angle / angleIncrement + 0.5) * angleIncrement
		
		local deltaFromCompleteRotation = math.abs(angle - math.pi * 2)
		local deltaFromSnapPoint = math.abs(angle - snappedAngle)
		
		if deltaFromCompleteRotation < deltaFromSnapPoint then
			-- For rotate increments which don't evenly divide the
			-- circle, there won't be a snap point at 360 degrees, so
			-- this if statement manually adds a special case for that
			-- additional snap point.
			return 0
		else
			return snappedAngle
		end
	else
		return angle
	end
end

function RotateHandles.new(draggerContext: DraggerContext, props: Props?, implementation: Implementation): Class
	local self = {}

	self._draggerContext = draggerContext
	self._handles = {}

	self._props = props or {
		Summonable = true,
	}

	self._handleCFrame = CFrame.identity
	self._startAngle = 0

	self._implementation = implementation
	self._tabKeyDown = false

	return setmetatable(self, RotateHandles) :: Class
end

function RotateHandles.update(self: Class, draggerToolModel: DraggerToolModel, selectionInfo: any)
	if not self._draggingHandleId then
		local cframe, offset, size = selectionInfo:getBoundingBox()
		
		self._boundingBox = {
			Size = size,
			CFrame = cframe * CFrame.new(offset),
		}

		self._basisOffset = CFrame.new(-offset)
		self._selectionInfo = selectionInfo
		self._selectionWrapper = draggerToolModel:getSelectionWrapper()
		self._schema = draggerToolModel:getSchema()
		self._scale = self._draggerContext:getHandleScale(self._boundingBox.CFrame.Position)
	end

	self:_updateHandles()
end

function RotateHandles.shouldBiasTowardsObjects(self: Class): boolean
	return false
end

function RotateHandles.hitTest(self: Class, mouseRay: Ray, ignoreExtraThreshold: boolean)
	local closestHandleId, closestHandleDistance = nil, math.huge

	for handleId, handleProps in pairs(self._handles) do
		local distance = RotateHandleView.hitTest(handleProps, mouseRay)
		if distance and distance < closestHandleDistance then
			closestHandleDistance = distance
			closestHandleId = handleId
		end
	end

	local alwaysOnTop = true
	return closestHandleId, closestHandleDistance, alwaysOnTop
end

function RotateHandles.render(self: Class, hoveredHandleId: string?)
	local children = {} :: {
		[string]: React.ReactElement<any>,
	}

	local increment = self._draggerContext:getRotateIncrement()
	local tickAngle

	if increment >= MIN_ROTATE_INCREMENT then
		tickAngle = math.rad(increment)
	end

	if self._draggingHandleId and self._handles[self._draggingHandleId] then
		local handleProps = self._handles[self._draggingHandleId]

		children[self._draggingHandleId] = React.createElement<<any>>(RotateHandleView.render, {
			HandleCFrame = handleProps.HandleCFrame,
			Color = handleProps.Color,
			StartAngle = self._startAngle - self._draggingLastGoodDelta,
			EndAngle = self._startAngle,
			Scale = self._scale,
			Hovered = false,
			RadiusOffset = handleProps.RadiusOffset,
			TickAngle = tickAngle,
		})

		-- Show the other handles, but thinner
		for handleId, otherHandleProps in pairs(self._handles) do
			if handleId ~= self._draggingHandleId then
				local offset = RotateHandleDefinitions[handleId].Offset

				children[handleId] = React.createElement<<any>>(RotateHandleView.render, {
					HandleCFrame = self._boundingBox.CFrame * offset,
					Color = Colors.makeDimmed(otherHandleProps.Color),
					Scale = self._scale,
					Thin = true,
					RadiusOffset = handleProps.RadiusOffset,
				})
			end
		end

		children.ImplementationRendered = self._implementation:render(self._boundingBox.CFrame * self._basisOffset)
	else
		for handleId, handleProps in pairs(self._handles) do
			local color = handleProps.Color
			local hovered = (handleId == hoveredHandleId)
			local tickAngleToUse

			if hovered then
				tickAngleToUse = tickAngle
			else
				color = Colors.makeDimmed(color)
			end

			children[handleId] = React.createElement<<any>>(RotateHandleView.render, {
				HandleCFrame = handleProps.HandleCFrame,
				Color = color,
				Scale = self._scale,
				Hovered = hovered,
				RadiusOffset = handleProps.RadiusOffset,
				TickAngle = tickAngleToUse,
			})
		end
	end

	if self._props.ShowBoundingBox and #self._selectionWrapper:get() > 1 then
		children.SelectionBoundingBox = React.createElement<<any>>(StandaloneSelectionBox, {
			CFrame = self._boundingBox.CFrame,
			Size = self._boundingBox.Size,
			Color = self._draggerContext:getSelectionBoxColor(),
			LineThickness = self._draggerContext:getHoverLineThickness(),
			Container = self._draggerContext:getGuiParent(),
		})
	end

	return React.createElement("Folder", {}, children)
end

function RotateHandles.mouseDown(self: Class, mouseRay: Ray, handleId: string)
	-- Attempted to re-drag a handle which no longer exists
	-- (happens if the selection changes in the middle of the drag in a way
	-- which causes the previously dragged handle to no longer exist)
	if not self._handles[handleId] then
		return
	end

	-- Check if we can find a starting angle
	local offset = RotateHandleDefinitions[handleId].Offset
	local handleCFrame = self._boundingBox.CFrame * offset
	local angle = rotationAngleFromRay(handleCFrame, mouseRay.Unit)

	if not angle then
		return
	end

	-- We can start a drag as a result of this mouse down
	self._draggingHandleId = handleId
	self._handleCFrame = handleCFrame
	self._lastGlobalTransformForRender = CFrame.identity
	self._draggingLastGoodDelta = 0
	self._originalBoundingBoxCFrame = self._boundingBox.CFrame

	self._startAngle = snapToRotateIncrementIfNeeded(
		angle, self._draggerContext:getRotateIncrement())

	self._implementation:beginDrag(self._selectionWrapper:get(), self._selectionInfo)
end

function RotateHandles.mouseDrag(self: Class, mouseRay: Ray)
	-- We never started this drag in the first place
	local draggingHandleId = self._draggingHandleId

	if not draggingHandleId then
		return
	end

	if not self._handles[draggingHandleId] then
		return
	end

	local angle = rotationAngleFromRay(self._handleCFrame, mouseRay.Unit)

	if not angle then
		return
	end

	local snappedAngle =
		snapToRotateIncrementIfNeeded(angle, self._draggerContext:getRotateIncrement())

	local snappedDelta = snappedAngle - self._startAngle
	local bboxCFrame = self._originalBoundingBoxCFrame or CFrame.identity

	local candidateGlobalTransform = getRotationTransform(bboxCFrame,
		self._handleCFrame.RightVector,
		snappedDelta,
		self._draggerContext:getRotateIncrement())

	local appliedGlobalTransform =
		self._implementation:updateDrag(candidateGlobalTransform)

	-- Adjust the bounding box
	self._boundingBox.CFrame = appliedGlobalTransform * bboxCFrame
	self._lastGlobalTransformForRender = appliedGlobalTransform

	-- Derive the applied rotation angle (we need to display this in the
	-- user interface)
	local rotatedAxis = appliedGlobalTransform:VectorToObjectSpace(self._handleCFrame.LookVector)
	local ry = self._handleCFrame.UpVector:Dot(rotatedAxis)
	local rx = self._handleCFrame.LookVector:Dot(rotatedAxis)
	self._draggingLastGoodDelta = -math.atan2(ry, rx)
end

function RotateHandles.mouseUp(self: Class, mouseRay: Ray)
	-- We never started this drag in the first place
	if not self._draggingHandleId then
		return
	end
	
	self._draggingHandleId = nil
	local newSelectionInfoHint = self._implementation:endDrag()
	self._schema.addUndoWaypoint(self._draggerContext, "Axis Rotate Selection")
	return newSelectionInfoHint
end

function RotateHandles._updateHandles(self: Class)
	if self._selectionInfo:isEmpty() then
		self._handles = {}
	else
		for handleId, handleDefinition in pairs(RotateHandleDefinitions) do
			if not handleDefinition.HideWhenTempPart or true then
				self._handles[handleId] = {
					HandleCFrame = (self._boundingBox.CFrame * handleDefinition.Offset),
					Color = handleDefinition.Color,
					RadiusOffset = handleDefinition.RadiusOffset,
					Scale = self._scale,
					Thin = false,
					Hovered = false,
				}
			else
				self._handles[handleId] = nil
			end
		end
	end
end

return RotateHandles
