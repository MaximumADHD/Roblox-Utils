local Implementation = script.Parent.Parent
local DraggerToolModel = require(Implementation.DraggerToolModel)

local DraggerFramework = Implementation.Parent
local StandardCursor = require(DraggerFramework.Utility.StandardCursor)

local DraggingHandle = {}
DraggingHandle.__index = DraggingHandle

type DraggerToolModel = DraggerToolModel.Class

export type Class = setmetatable<{
	_draggerToolModel: DraggerToolModel,
	_draggingHandles: any,
	_draggingHandleId: string,
	_alreadyEndingDrag: boolean,
}, typeof(DraggingHandle)>

function DraggingHandle.new(draggerToolModel: DraggerToolModel, draggingHandles: any, draggingHandleId: string)
	local self: Class = setmetatable({
		_draggerToolModel = draggerToolModel,
		_draggingHandles = draggingHandles,
		_draggingHandleId = draggingHandleId,
		_alreadyEndingDrag = false,
	}, DraggingHandle)

	self:_init(draggingHandles, draggingHandleId)
	return self
end

function DraggingHandle.enter(self: Class)
end

function DraggingHandle.leave(self: Class)
end

function DraggingHandle._init(self: Class, draggingHandles: any, draggingHandleId: string)
	assert(draggingHandleId, "Missing draggingHandleId")
	self._draggerToolModel._boundsChangedTracker:uninstall()
	draggingHandles:mouseDown(self._draggerToolModel._draggerContext:getMouseRay(), draggingHandleId)
	self._draggingHandleId = draggingHandleId
	self._draggingHandles = draggingHandles
end

function DraggingHandle.render(self: Class)
	self._draggerToolModel:setMouseCursor(StandardCursor.getClosedHand())

	return self._draggingHandles:render(self._draggingHandleId)
end

function DraggingHandle.processSelectionChanged(self: Class)
	if self._alreadyEndingDrag then
		return
	end
	-- Re-init the drag if the selection changes.
	local invokedBySelectionChange = true
	self:_endHandleDrag(invokedBySelectionChange)
	self:_init(self._draggingHandles, self._draggingHandleId)
end

function DraggingHandle.processMouseDown(self: Class)
	error("Mouse should already be down while dragging handle.")
end

function DraggingHandle.processViewChanged(self: Class)
	self._draggingHandles:mouseDrag(
		self._draggerToolModel._draggerContext:getMouseRay())
end

function DraggingHandle.processMouseUp(self: Class)
	local invokedBySelectionChange = false
	self:_endHandleDrag(invokedBySelectionChange)
	self._draggerToolModel:transitionToState("Ready")
end

function DraggingHandle.processKeyDown(self: Class, keyCode: Enum.KeyCode)
	if self._draggingHandles.keyDown :: any then
		if self._draggingHandles:keyDown(keyCode) then
			-- Update the drag
			self:processViewChanged()
		end
	end
end

function DraggingHandle.processKeyUp(self: Class, keyCode: Enum.KeyCode)
	if self._draggingHandles.keyUp :: any then
		if self._draggingHandles:keyUp(keyCode) then
			-- Update the drag
			self:processViewChanged()
		end
	end
end

function DraggingHandle._endHandleDrag(self: Class, invokedBySelectionChange: boolean)
	self._alreadyEndingDrag = true
	-- Commit the results of using the tool
	
	local newSelectionInfoHint = self._draggingHandles:mouseUp(
		self._draggerToolModel._draggerContext:getMouseRay())
	
	if invokedBySelectionChange then
		-- If the drag was ended by a selection change, then our computed
		-- selection info hint will be stale, because it applies to the last
		-- selection, rather than the new selection. So we don't use it.
		self._draggerToolModel:_updateSelectionInfo(nil)
	else
		-- Use the Implementation's modification to the SelectionInfo hint
		self._draggerToolModel:_updateSelectionInfo(newSelectionInfoHint)
	end

	self._draggerToolModel._boundsChangedTracker:install()

	self._draggerToolModel:getSchema().setActivePoint(
		self._draggerToolModel._draggerContext,
		self._draggerToolModel._selectionInfo)

	self._alreadyEndingDrag = false
end

return DraggingHandle