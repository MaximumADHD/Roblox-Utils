local Implementation = script.Parent.Parent
local DraggerToolModel = require(Implementation.DraggerToolModel)

local DraggerFramework = Implementation.Parent
local Packages = DraggerFramework.Parent

local React = require(Packages.React)
local Components = DraggerFramework.Components
local DragSelectionView = require(Components.DragSelectionView)

local Utility = DraggerFramework.Utility
local DragSelector = require(Utility.DragSelector)
local StandardCursor = require(Utility.StandardCursor)

type DragSelector = DragSelector.Class
type DraggerToolModel = DraggerToolModel.Class

local DragSelecting = {}
DragSelecting.__index = DragSelecting

export type Class = setmetatable<{
	_dragSelector: DragSelector,
	_draggerToolModel: DraggerToolModel,
	_mouseStartLocation: Vector2,
	_hasMovedMouse: boolean,
}, typeof(DragSelecting)>

function DragSelecting.new(draggerToolModel: DraggerToolModel)
	local self = setmetatable({
		_dragSelector = DragSelector.new(
			draggerToolModel:getSelectionWrapper(),
			draggerToolModel:getSchema().beginBoxSelect,
			draggerToolModel:getSchema().endBoxSelect
		),
		_mouseStartLocation = Vector2.zero,
		_draggerToolModel = draggerToolModel,
		_hasMovedMouse = false,
	}, DragSelecting)

	self:_init()
	return self
end

function DragSelecting.enter(self: Class)
	self._mouseStartLocation = self._draggerToolModel._draggerContext:getMouseLocation()
	self._draggerToolModel:setMouseCursor(StandardCursor.getArrow())
end

function DragSelecting.leave(self: Class)

end

function DragSelecting._init(self: Class)
	self._hasMovedMouse = false
end

function DragSelecting.render(self: Class): React.Node
	local startLocation =
		self._hasMovedMouse and
		self._dragSelector:getStartLocation() or
		self._draggerToolModel._draggerContext:getMouseLocation()

	return React.createElement<<any>>(DragSelectionView, {
		DragStartLocation = startLocation,
		DragEndLocation = self._draggerToolModel._draggerContext:getMouseLocation(),
	}) :: React.Node
end

function DragSelecting.processSelectionChanged(self: Class)
	-- Don't do anything. We don't want to unnecessarily fight other sources
	-- over selection changes.
end

function DragSelecting.processMouseDown(self: Class)
	error("Mouse should already be down while drag selecting.")
end

function DragSelecting.processViewChanged(self: Class)
	if not self._hasMovedMouse then
		self._dragSelector:beginDrag(
			self._draggerToolModel._draggerContext, self._mouseStartLocation)
		self._hasMovedMouse = true
	end

	self._dragSelector:updateDrag(self._draggerToolModel._draggerContext)
end

function DragSelecting.processMouseUp(self: Class)
	if self._hasMovedMouse then
		self._dragSelector:commitDrag(self._draggerToolModel._draggerContext)
		self._draggerToolModel:_updateSelectionInfo()
		self._hasMovedMouse = false
	end

	self._draggerToolModel:transitionToState("Ready")
end

function DragSelecting.processKeyDown(self: Class, keyCode: Enum.KeyCode)
	
end

function DragSelecting.processKeyUp(self: Class, keyCode: Enum.KeyCode)
	
end

return DragSelecting