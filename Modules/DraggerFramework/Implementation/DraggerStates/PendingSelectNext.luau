--[[
	When clicking on the selection in a way that doesn't change the selection on
	mouse down, attempt to select the next selectables instead when the mouse is
	released. The reason that we do this on mouse up is for uniformity with the
	begin freeform drag behavior.
]]
local Implementation = script.Parent.Parent
local DraggerToolModel = require(Implementation.DraggerToolModel)

local DraggerFramework = Implementation.Parent
local Utility = DraggerFramework.Utility

local StandardCursor = require(Utility.StandardCursor)
type DraggerToolModel = DraggerToolModel.Class

local PendingSelectNext = {}
PendingSelectNext.__index = PendingSelectNext

export type Class = setmetatable<{
	_draggerToolModel: DraggerToolModel,
	_dragInfo: any,
	_initialMouseLocation: Vector2,
	_wasDoubleClick: boolean,
}, typeof(PendingSelectNext)>

function PendingSelectNext.new(draggerToolModel: DraggerToolModel, isDoubleClick: boolean, dragInfo: any): Class
	local self = setmetatable({
		_draggerToolModel = draggerToolModel,
		_dragInfo = dragInfo,
		_initialMouseLocation = draggerToolModel._draggerContext:getMouseLocation(),
		_wasDoubleClick = isDoubleClick,
	}, PendingSelectNext)

	return self
end

function PendingSelectNext.enter(self: Class)
	self._draggerToolModel:setMouseCursor(StandardCursor.getOpenHand())
end

function PendingSelectNext.leave(self: Class)
end

function PendingSelectNext.render(self: Class)
end

function PendingSelectNext.processSelectionChanged(self: Class)
	self:_transitionBack()
end

function PendingSelectNext.processMouseDown(self: Class)
end

function PendingSelectNext.processViewChanged(self: Class)
end

function PendingSelectNext.processMouseUp(self: Class)
	if self._initialMouseLocation == self._draggerToolModel._draggerContext:getMouseLocation() then
		-- Clicked nothing without moving
		self._draggerToolModel:selectNextSelectables(self._dragInfo, self._wasDoubleClick)
	end

	self:_transitionBack()
end

function PendingSelectNext.processKeyDown(self: Class, keyCode)
end

function PendingSelectNext.processKeyUp(self: Class, keyCode)
end

function PendingSelectNext._transitionBack(self: Class)
	self._draggerToolModel:transitionToState("Ready")
end

return PendingSelectNext