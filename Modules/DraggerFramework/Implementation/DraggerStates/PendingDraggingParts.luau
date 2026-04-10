local Implementation = script.Parent.Parent
local DraggerFramework = Implementation.Parent

local DraggerToolModel = require(Implementation.DraggerToolModel)
type DraggerToolModel = DraggerToolModel.Class

local Utility = DraggerFramework.Utility
local StandardCursor = require(Utility.StandardCursor)

local FREEFORM_DRAG_THRESHOLD = 4

local PendingDraggingParts = {}
PendingDraggingParts.__index = PendingDraggingParts

export type Class = setmetatable<{
	_draggerToolModel: DraggerToolModel,
	_dragStartLocation: Vector2,
	_dragInfo: any,
	_isDoubleClick: boolean,
}, typeof(PendingDraggingParts)>

function PendingDraggingParts.new(draggerToolModel: DraggerToolModel, isDoubleClick: boolean, dragInfo: any): Class
	return setmetatable({
		_isDoubleClick = isDoubleClick,
		_dragStartLocation = draggerToolModel._draggerContext:getMouseLocation(),
		_dragInfo = dragInfo,
		_draggerToolModel = draggerToolModel
	}, PendingDraggingParts)
end

function PendingDraggingParts.enter(self: Class)

end

function PendingDraggingParts.leave(self: Class)

end

function PendingDraggingParts.render(self: Class)
	self._draggerToolModel:setMouseCursor(StandardCursor.getClosedHand())
end

function PendingDraggingParts.processSelectionChanged(self: Class)
	-- Don't clear the state back to Ready in this case. In Run mode the
	-- selection should change while we're sitting in Pending state, and
	-- that's okay, because we already recorded how to drag the selection
	-- relative to the mouse on down.
end

function PendingDraggingParts.processMouseDown(self: Class)
	error("Mouse should already be down while pending part drag.")
end

function PendingDraggingParts.processViewChanged(self: Class)
	local location = self._draggerToolModel._draggerContext:getMouseLocation()
	local screenMovement = location - self._dragStartLocation

	if screenMovement.Magnitude > FREEFORM_DRAG_THRESHOLD then
		self._draggerToolModel:transitionToState("DraggingParts", self._dragInfo)
	end
end

function PendingDraggingParts.processMouseUp(self: Class)
	-- If the mouse didn't move enough to start a drag, try to select next
	-- selectables instead.
	self._draggerToolModel:selectNextSelectables(
		self._dragInfo, self._isDoubleClick)

	self._draggerToolModel:transitionToState("Ready")
end

function PendingDraggingParts.processKeyDown(self: Class, keyCode: Enum.KeyCode)
	-- Nothing to do.
end

function PendingDraggingParts.processKeyUp(self: Class, keyCode: Enum.KeyCode)
	-- Nothing to do.
end

return PendingDraggingParts