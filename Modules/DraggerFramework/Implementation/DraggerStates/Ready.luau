--!strict

local Implementation = script.Parent.Parent
local DraggerFramework = Implementation.Parent

local Components = DraggerFramework.Components
local Packages = DraggerFramework.Parent
local Utility = DraggerFramework.Utility

local React = require(Packages.React)
local HoverTracker = require(Implementation.HoverTracker)
local DraggerToolModel = require(Implementation.DraggerToolModel)
local AnimatedHoverBox = require(Components.AnimatedHoverBox)
local LocalSpaceIndicator = require(Components.LocalSpaceIndicator)
local SelectionHelper = require(Utility.SelectionHelper)
local StandardCursor = require(Utility.StandardCursor)

local Ready = {}
Ready.__index = Ready

type HoverTracker = HoverTracker.Class
type DraggerToolModel = DraggerToolModel.Class
type Proto = typeof(Ready)

type Class = setmetatable<{
	_draggerToolModel: DraggerToolModel,
	_hoverTracker: HoverTracker,
}, Proto>

function Ready.new(draggerToolModel: DraggerToolModel)
	return setmetatable({
		_draggerToolModel = draggerToolModel
	}, Ready)
end

function Ready.enter(self: Class)
	local function onHoverExternallyChanged()
		self._draggerToolModel:_processViewChanged()
	end

	self._hoverTracker =
		HoverTracker.new(
			self._draggerToolModel:getSchema(),
			self._draggerToolModel:getHandlesList(),
			onHoverExternallyChanged)
	
	self:_updateHoverTracker()
end

function Ready.leave(self: Class)
	self._hoverTracker:clearHover(self._draggerToolModel._draggerContext)
end

function Ready.update(self: Class)
	local hoverSelectable = self._hoverTracker:getHoverSelectable()
	
	if hoverSelectable or self._hoverTracker:getHoverHandleId() then
		self._draggerToolModel:setMouseCursor(StandardCursor.getOpenHand())
	else
		self._draggerToolModel:setMouseCursor(StandardCursor.getArrow())
	end
end

function Ready.render(self: Class)
	local elements = {} :: {
		[string]: React.Node,
	}
	
	local draggerContext = self._draggerToolModel._draggerContext
	local hoverSelectable = self._hoverTracker:getHoverSelectable()

	if draggerContext:shouldShowHover() and hoverSelectable then
		-- Calls to the schema to know what kind of component to render the
		-- selection box for the hovered object with.
		local component = self._draggerToolModel:getSchema().getSelectionBoxComponent(
			draggerContext, hoverSelectable)
		if component then
			local animatePeriod
			if draggerContext:shouldAnimateHover() then
				animatePeriod = draggerContext:getHoverAnimationSpeedInSeconds()
			end

			local isActive = false
			if draggerContext:shouldShowActiveInstanceHighlight() then
				local activeInstance =
					self._draggerToolModel:getSelectionWrapper():getActiveSelectable()
				isActive = (hoverSelectable == activeInstance)
			end

			elements.HoverBox = React.createElement<<any>>(AnimatedHoverBox, {
				-- Configurable component to render the selection box
				SelectionBoxComponent = component,
				HoverTarget = hoverSelectable,
				SelectColor = draggerContext:getSelectionBoxColor(isActive),
				LineThickness = draggerContext:getHoverLineThickness(),
				HoverColor = draggerContext:getHoverBoxColor(isActive),
				AnimatePeriod = animatePeriod,
			}) :: React.Node
		end
	end

	if self._draggerToolModel:shouldShowLocalSpaceIndicator() then
		local selectionInfo = self._draggerToolModel._selectionInfo
		if not selectionInfo:isEmpty() and draggerContext:shouldUseLocalSpace() then
			local cframe, offset, size = selectionInfo:getBoundingBox()

			elements.LocalSpaceIndicator = React.createElement<<any>>(LocalSpaceIndicator, {
				CFrame = cframe * CFrame.new(offset),
				Size = size,
				TextColor3 = draggerContext:getSelectionBoxColor(),
				DraggerContext = draggerContext,
			}) :: React.Node
		end
	end

	local _, hoverHandleId = self._hoverTracker:getHoverHandleId()

	for i, handles in pairs(self._draggerToolModel:getHandlesList()) do
		elements["ImplementationUI" .. i] = handles:render(hoverHandleId)
	end

	return React.createElement(React.Fragment, {}, elements)
end

function Ready.processSelectionChanged(self: Class)
	-- We expect selection changes while in the ready state
	-- when the developer selects objects in the explorer window.
	self:_updateHoverTracker()
end

--[[
	Find the clicked part or constraint system gizmo by raycasting with the
	current mouse location and decide what action to take:

	* If the clicked instance is added to or was already in the selection, begin
	  (maybe) freeform dragging the selected parts.
	* If no selectable instance was clicked, begin drag selecting.
	* When an Attachment is clicked without a selection modifier key pressed,
	  begin (maybe) freeform dragging that Attachment.
	* When a Constraint is clicked, select it but don't do any form of drag.
]]
function Ready.processMouseDown(self: Class, isDoubleClick: boolean)
	-- We have to do an update here for the edge case where the 3D view just
	-- became selected thanks to the mouse down event, so we haven't received
	-- a view change event yet.
	self:_updateHoverTracker()

	local hoverHandles, hoverHandleId = self._hoverTracker:getHoverHandleId()
	if hoverHandleId then
		self._draggerToolModel:transitionToState("DraggingHandle", hoverHandles, hoverHandleId)
	else
		self:_clickInWorld(isDoubleClick)
	end
end

function Ready.processViewChanged(self: Class)
	self:_updateHoverTracker()
end

function Ready.processMouseUp(self: Class)
	-- Nothing to do. This case can ocurr when the user clicks on a constraint.
end

function Ready._scopeSelectChanged(self: Class)
	if self._hoverTracker:getHoverItem() ~= nil then
		self:_updateHoverTracker()
		self._draggerToolModel:_scheduleRender()
	end
end

function Ready.processKeyDown(self: Class, keyCode: Enum.KeyCode)
	if keyCode == Enum.KeyCode.LeftAlt or keyCode == Enum.KeyCode.RightAlt then
		self:_scopeSelectChanged()
	end
end

function Ready.processKeyUp(self: Class, keyCode: Enum.KeyCode)
	if keyCode == Enum.KeyCode.LeftAlt or keyCode == Enum.KeyCode.RightAlt then
		self:_scopeSelectChanged()
	end

	for _, handles in pairs(self._draggerToolModel:getHandlesList()) do
		if handles.keyUp then
			if handles:keyUp(keyCode) then
				self:processViewChanged()
				self._draggerToolModel:_scheduleRender()
			end
		end
	end
end

function Ready._updateHoverTracker(self: Class)
	self._hoverTracker:update(
		self._draggerToolModel._draggerContext,
		self._draggerToolModel:getSelectionWrapper():get(),
		self._draggerToolModel._selectionInfo
	)
end

--[[
	Called when the user clicking in the 3d space (not on a handle)
]]
function Ready._clickInWorld(self: Class, isDoubleClick: boolean)
	local draggerContext = self._draggerToolModel._draggerContext
	local clickedItem, position = self._hoverTracker:getHoverItem()
	local clickedSelectable = self._hoverTracker:getHoverSelectable()

	local oldSelection = self._draggerToolModel:getSelectionWrapper():get()
	local selectionDidContainSelectable = clickedSelectable and table.find(oldSelection, clickedSelectable) ~= nil
	local shouldExtendSelection = draggerContext:shouldExtendSelection()

	if isDoubleClick and selectionDidContainSelectable then
		-- Special case. Double clicking with extend selection would be a
		-- no-op, thanks to adding something to the selection and then
		-- immediately removing it again.
		-- Prevent this. This also allows us to handle double clicks with
		-- shouldExtendSelection activated as a getNextSelectable invocation.
		shouldExtendSelection = false
	end

	local isExclusiveSelectable =
		(clickedSelectable ~= nil) and
		self._draggerToolModel:getSchema().isExclusiveSelectable(
			draggerContext, clickedSelectable, clickedItem)
	
	local selectionDidChange, newSelection, hint =
		SelectionHelper.updateSelection(
			clickedSelectable,
			oldSelection,
			isExclusiveSelectable,
			shouldExtendSelection)
	
	if selectionDidChange then
		self._draggerToolModel:getSelectionWrapper():set(newSelection, hint)

		-- Process selection changed only gets called automatically when studio
		-- changes the selection, since we just changed the selection manually
		-- we need to invoke it here.
		self._draggerToolModel:_processSelectionChanged()

		-- If we have objects to transform, then change the insert point to
		-- the selection's center. This makes it easier to paste and insert
		-- objects at the position of a target object.
		self._draggerToolModel:getSchema().setActivePoint(
			self._draggerToolModel._draggerContext,
			self._draggerToolModel._selectionInfo)
	end

	local selectionEvent = {
		DoubleClicked = isDoubleClick,
		ClickedSelectable = clickedSelectable,
		ClickedItem = clickedItem,
		ClickedPosition = position,
		SelectionDidContainSelectable = selectionDidContainSelectable,
		SelectionNowContainsSelectable = clickedSelectable and table.find(newSelection, clickedSelectable) ~= nil,
	}

	local nextState, extraData =
		self._draggerToolModel:getSchema().dispatchWorldClick(
			self._draggerToolModel._draggerContext,
			self._draggerToolModel,
			selectionEvent)

	if nextState == "Ready" then
		if clickedSelectable and (not selectionDidChange or isDoubleClick) then
			self._draggerToolModel:transitionToState("PendingSelectNext", isDoubleClick, selectionEvent)
		else
			-- Nothing to do, stay in ready state
		end
	elseif nextState == "DragSelecting" then
		if self._draggerToolModel:doesAllowDragSelect() then
			self._draggerToolModel:transitionToState("DragSelecting")
		end
	elseif nextState == "FreeformSelectionDrag" then
		self._draggerToolModel:transitionToState("PendingDraggingParts", isDoubleClick, extraData)
	else
		error("Bad state returned from dispatchWorldClick: `" .. tostring(nextState) .. "`")
	end
end

return Ready