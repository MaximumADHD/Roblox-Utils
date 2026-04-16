local DraggerFramework = script.Parent.Parent.Parent
local Implementation = DraggerFramework.Implementation

local DraggerToolModel = require(Implementation.DraggerToolModel)

local Utility = DraggerFramework.Utility
local PartMover = require(Utility.PartMover)
local StandardCursor = require(Utility.StandardCursor)

local DraggingParts = {}
DraggingParts.__index = DraggingParts

type PartMover = PartMover.Class
type DraggerToolModel = DraggerToolModel.Class

type Class = setmetatable<{
	_draggerToolModel: DraggerToolModel,
	_freeformDragger: any,
	_partMover: PartMover,
	_alreadyEndingDrag: boolean,
	_raycastFilter: { BasePart },
}, typeof(DraggingParts)>

function DraggingParts.new(draggerToolModel: DraggerToolModel, dragInfo: any): Class
	draggerToolModel._boundsChangedTracker:uninstall()
	draggerToolModel:getSchema().beginRecording(draggerToolModel._draggerContext, "End Freeform Drag")

	local self = setmetatable({
		_draggerToolModel = draggerToolModel,
		_freeformDragger = draggerToolModel:getSchema().FreeformDragger.new(
			draggerToolModel._draggerContext, draggerToolModel, dragInfo)
	}, DraggingParts) :: Class

	return self
end

function DraggingParts.enter(self: Class)
	self._draggerToolModel:setMouseCursor(StandardCursor.getClosedHand())
	self:_updateFreeformSelectionDrag()
end

function DraggingParts.leave(self: Class)
end

function DraggingParts._initIgnoreList(self: Class, parts: { BasePart })
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

function DraggingParts.render(self: Class)
	return self._freeformDragger:render()
end

function DraggingParts.processSelectionChanged(self: Class)
	if self._alreadyEndingDrag then
		return
	end
	-- If something unexpectedly changes the selection out from underneath us,
	-- bail out of the drag.
	self:_endFreeformSelectionDrag()
end

function DraggingParts.processMouseDown(self: Class)
	error("Mouse should already be down while dragging parts.")
end

function DraggingParts.processViewChanged(self: Class)
	self:_updateFreeformSelectionDrag()
end

function DraggingParts.processMouseUp(self: Class)
	self:_endFreeformSelectionDrag()
end

function DraggingParts.processKeyDown(self: Class, keyCode: Enum.KeyCode)
	if keyCode == Enum.KeyCode.R then
		self:_tiltRotateFreeformSelectionDrag(Vector3.yAxis)
	elseif keyCode == Enum.KeyCode.T then
		self:_tiltRotateFreeformSelectionDrag(Vector3.xAxis)
	end
end

function DraggingParts.processKeyUp(self: Class, keyCode: Enum.KeyCode)
end

function DraggingParts._tiltRotateFreeformSelectionDrag(self: Class, axis)
	self._freeformDragger:rotate(axis)
	self:_updateFreeformSelectionDrag()
	self._draggerToolModel:_scheduleRender()
end

function DraggingParts._updateFreeformSelectionDrag(self: Class)
	self._freeformDragger:update()
end

--[[
	Refresh selection info to reflect the new CFrames of the dragged parts
	and return to the Ready state.
]]
function DraggingParts._endFreeformSelectionDrag(self: Class)
	self._alreadyEndingDrag = true
	local newSelectionInfoHint = self._freeformDragger:destroy()

	self._draggerToolModel._boundsChangedTracker:install()
	self._draggerToolModel:_updateSelectionInfo(newSelectionInfoHint)
	self._draggerToolModel:transitionToState("Ready")

	self._draggerToolModel:getSchema().addUndoWaypoint(
		self._draggerToolModel._draggerContext,
		"End Freeform Drag")

	self._draggerToolModel:getSchema().setActivePoint(
		self._draggerToolModel._draggerContext,
		self._draggerToolModel._selectionInfo)

	self._alreadyEndingDrag = false
end

return DraggingParts