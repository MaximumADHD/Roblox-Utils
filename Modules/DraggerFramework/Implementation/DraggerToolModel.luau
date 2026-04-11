local Implementation = script.Parent
local DraggerFramework = Implementation.Parent

local Packages = DraggerFramework.Parent
local ReactRoblox = require(Packages.ReactRoblox)
local React = require(Packages.React)

local Utility = DraggerFramework.Utility
local classifyPivot = require(Utility.classifyPivot)
local SelectionInfo = require(Utility.SelectionInfo)
local SelectionHelper = require(Utility.SelectionHelper)
local BoundsChangedTracker = require(Utility.BoundsChangedTracker)

local SelectionWrapper = require(Utility.SelectionWrapper)
local DraggerContext = require(Implementation.DraggerContext)

type BoundsChangedTracker = BoundsChangedTracker.Class
type SelectionWrapper = SelectionWrapper.Class
type DraggerContext = DraggerContext.Class
type SelectionInfo = SelectionInfo.Class
type PivotType = classifyPivot.PivotType

local DraggerToolModel = {}
DraggerToolModel.__index = DraggerToolModel

type DraggerToolModel = {
	_lastMouseClickTime: number,
	_lastMouseClickLocation: Vector2,
	_handlesList: { DraggerHandle },
	_draggerContext: DraggerContext,
	_draggerSchema: any,
	_modelProps: DraggerSettings,
	_requestRenderCallback: () -> (),
	_markViewDirtyCallback: () -> (),
	_markSelectionDirtyCallback: () -> (),
	_selectionWrapper: SelectionWrapper?,
	_mainState: DraggerStateType?,
	_stateObject: DraggerState?,
	_selectionInfo: SelectionInfo,
	_boundsChangedTracker: BoundsChangedTracker,
	_selectionChangedConnection: any?,
	_isMouseDown: boolean?,
	_mouseCursor: string?,
	_debugInProcessSelected: boolean?,
	_debugInProcessDeselected: boolean?,
	_oldShowPivot: boolean?,
}

type Proto = typeof(DraggerToolModel)
export type Class = setmetatable<DraggerToolModel, Proto>

-- States
local DraggerStates = Implementation.DraggerStates

export type DraggerStateType =
	| "Ready"
	| "FreeformDragger"
	| "DraggingFaceInstance"
	| "PendingDraggingParts"
	| "PendingSelectNext"
	| "DraggingHandle"
	| "DraggingParts"
	| "DragSelecting"
	| string

export type DraggerState<T = any, Args... = ...any> = {
	new: (Args...) -> T,
	enter: (self: T) -> (),
	leave: (self: T) -> (),
	render: (self: T) -> any,
	processSelectionChanged: (self: T) -> (),
	processKeyDown: (self: T, keyCode: Enum.KeyCode) -> (),
	processKeyUp: (self: T, keyCode: Enum.KeyCode) -> (),
	processMouseDown: (self: T, isDoubleClick: boolean) -> (),
	processMouseUp: (self: T) -> (),
	processViewChanged: (self: T) -> (),
	update: ((self: T) -> ())?,
}

-- Table of hot-loaded state modules.
-- This is necessary to avoid cyclic dependency.

local DraggerState = setmetatable({} :: {
	[DraggerStateType]: DraggerState?
}, {
	__index = function(self, index: DraggerStateType)
		local module = DraggerStates:FindFirstChild(index)

		if module then
			local success, result = xpcall(require, function (err)
				warn("Error requiring DraggerState module: "..tostring(err))
			end, module)

			if success then
				rawset(self, index, result)
				return result
			end
		end

		return nil
	end,
})

-- We can't respect the OS setting, no way to tell whether a click in the 3d
-- viewport is a double click :(
local DOUBLE_CLICK_TIME = 0.5

-- Note: ShowSelectionDot remove because we don't use it anymore
-- Note: UseCollisionsTransparency is part of the Schema now
export type DraggerSettings = {
	AllowDragSelect: boolean?,
	AllowFreeformDrag: boolean?,
	ShowLocalSpaceIndicator: boolean?,
	ShowSelectionDot: boolean?, -- Note: This is no longer used but we keep it here for backwards compatibility
	UseCollisionsTransparency: boolean?, -- Note: This is now technically part of the Schema, but we keep it here for backwards compatibility
	WasAutoSelected: boolean?,
	HandlesList: {any}?,
	ShowPivotIndicator: boolean?,
}

local DEFAULT_DRAGGER_SETTINGS: DraggerSettings = {
	AllowDragSelect = true,
	AllowFreeformDrag = true,
	ShowLocalSpaceIndicator = false,
	WasAutoSelected = false,
	HandlesList = {},
	ShowPivotIndicator = false,
}

type DraggerHandle<T = any> = {
	update: (self: T, draggerToolModel: Class, selectionInfo: SelectionInfo) -> (),
	mouseDown: (self: T, mouseRay: Ray, handleId: string) -> (),
	render: (self: T, hoverHandleId: string?) -> React.Node?,
	keyUp: ((self: T, keyCode: Enum.KeyCode) -> boolean?)?,
	keyDown: ((self: T, keyCode: Enum.KeyCode) -> boolean?)?,
}

function DraggerToolModel.new(
	draggerContext: DraggerContext,
	draggerSchema: any,
	draggerSettings: DraggerSettings,
	requestRenderCallback: () -> (),
	markViewDirtyCallback: () -> (),
	markSelectionDirtyCallback: () -> ()
): Class
	-- Build props for this dragger
	local draggerSettingsOrDefault = {} :: any

	for prop: any, default: any in pairs(DEFAULT_DRAGGER_SETTINGS :: any) do
		if (draggerSettings :: any)[prop] ~= nil then
			(draggerSettingsOrDefault :: any)[prop] = (draggerSettings :: any)[prop]
		else
			(draggerSettingsOrDefault :: any)[prop] = default
		end
	end

	return setmetatable({
		_lastMouseClickTime = 0,
		_lastMouseClickLocation = Vector2.new(-1, -1),
		_handlesList = draggerSettingsOrDefault.HandlesList,
		_draggerContext = draggerContext,
		_draggerSchema = draggerSchema,
		_modelProps = draggerSettingsOrDefault,
		_requestRenderCallback = requestRenderCallback,
		_markViewDirtyCallback = markViewDirtyCallback,
		_markSelectionDirtyCallback = markSelectionDirtyCallback,
		_selectionWrapper = nil,
	}, DraggerToolModel) :: Class
end

--[[
	Called by the DraggerTool main states to set the mouse cursor.

	To not interfere with other parts of studio which set the mouse cursor,
	we have to only set the cursor when we think it should change. This is the
	abstraction layer that guarantees this.
]]
function DraggerToolModel.setMouseCursor(self: Class, cursor: string?)
	if self._mouseCursor ~= cursor then
		self._mouseCursor = cursor
		self._draggerContext:setMouseIcon(cursor)
	end
end

--[[
	Called by the main DraggerToolModel code, and the code in individual
	DraggerTool main states in order to transition to a new state.

	The variable arguments are passed as arguments to the constructor of the
	new state object which will be constructed and transitioned to.
]]
function DraggerToolModel.transitionToState(self: Class, draggerStateType: DraggerStateType, ...: any)
	assert(DraggerState[draggerStateType], "Missing state type: "..tostring(draggerStateType))

	if self._stateObject then
		self._stateObject:leave()
		self._stateObject = nil
	end

	local newState = DraggerState[draggerStateType]
	self._mainState = draggerStateType

	if newState then
		local new = newState.new(self, ...)
		self._stateObject = new
		new:enter()
	end

	self:_updatePivotIndicatorVisibility()
	self:_scheduleRender()
end

function DraggerToolModel.render(self: Class)
	self:_updateHandles()

	return ReactRoblox.createPortal({
		DraggerUI = React.createElement("Folder", {}, if self._stateObject
			then self._stateObject:render()
			else nil
		),
	}, self._draggerContext:getGuiParent())
end

-- Called every frame on render step
function DraggerToolModel.update(self: Class)
	local stateObject = self._stateObject

	if stateObject and stateObject.update then
		stateObject:update()
	end

	if self._draggerContext:isSimulating() then
		-- Must do a view update every frame in run mode to catch stuff
		-- moving under our mouse.
		self._markViewDirtyCallback()

		-- If there's a physically simulated part in the selection then we
		-- have to update the whole selection every frame.
		local isDragging =
			self._mainState == "DraggingHandle" or
			self._mainState == "DraggingParts"
		if not isDragging then
			if self._selectionInfo:isDynamic() then
				self._markSelectionDirtyCallback()
			end
		end
	end
end

function DraggerToolModel.getSelectionWrapper(self: Class): SelectionWrapper
	return assert(self._selectionWrapper)
end

-- Note: This needs to be exposed now because the Schema analytics care about it
function DraggerToolModel.wasAutoSelected(self: Class)
	return self._modelProps.WasAutoSelected
end

function DraggerToolModel.getSchema(self: Class)
	return self._draggerSchema
end

function DraggerToolModel.getHandlesList(self: Class)
	return self._handlesList
end

function DraggerToolModel.doesAllowDragSelect(self: Class)
	return self._modelProps.AllowDragSelect
end

function DraggerToolModel.doesAllowFreeformDrag(self: Class)
	return self._modelProps.AllowFreeformDrag
end

function DraggerToolModel.shouldShowLocalSpaceIndicator(self: Class)
	return self._modelProps.ShowLocalSpaceIndicator
end

function DraggerToolModel.shouldShowSelectionDot(self: Class)
	return self._modelProps.ShowSelectionDot
end

function DraggerToolModel.shouldUseCollisionTransparency(self: Class)
	return self._modelProps.UseCollisionsTransparency
end

function DraggerToolModel.shouldAlignDraggedObjects(self: Class)
	return self._draggerContext:shouldAlignDraggedObjects()
end

function DraggerToolModel.selectNextSelectables(self: Class, dragInfo: any, isDoubleClick: boolean)
	local selectionWrapper = self:getSelectionWrapper()
	local oldSelection: { Instance } = selectionWrapper and selectionWrapper:get() or {}

	local nextSelectables = self._draggerSchema.getNextSelectables(
		self._draggerContext,
		oldSelection,
		dragInfo,
		isDoubleClick)

	if nextSelectables then
		local shouldXorSelection = false
		local shouldExtendSelection = self._draggerContext:shouldExtendSelection()

		local newSelection =
			SelectionHelper.updateSelectionWithMultipleSelectables(
				nextSelectables, oldSelection, shouldXorSelection, shouldExtendSelection)
		
		if selectionWrapper then
			selectionWrapper:set(newSelection)
		end
		
		self:_updateSelectionInfo()
	end
end

--[[
Tries to boil what the pivot for the current selection is set to down to a
single descriptive analytics value as a string. Possible return values:
	- None: There is no selection
	- Default: The pivot is at the center of the bounds
	- Inside: The pivot is within (but not exactly on) the bounds
	- Surface: The pivot is exactly on the surface of the bounds
	- Outside: The pivot is outside of the bounds
	- Far: The pivot is very far outside the bounds (more than one size away)
]]
function DraggerToolModel.classifySelectionPivot(self: Class): PivotType
	if not self._selectionInfo then
		return "None"
	end

	local cframe, offset, size = self._selectionInfo:getBoundingBox()
	return classifyPivot(cframe, offset, size)
end

function DraggerToolModel._processSelected(self: Class)
	local readyState = DraggerState.Ready
	self._debugInProcessSelected = true

	if readyState then
		self._mainState = "Ready"
		self._stateObject = readyState.new(self)
	end

	if self._modelProps.ShowPivotIndicator then
		self._oldShowPivot = self._draggerContext:setPivotIndicator(true)
	end

	self._mouseCursor = ""
	self._draggerContext:setMouseIcon("")

	-- We defer handling part bounds changes to the render step, as the
	-- changes that are happening to the selection may be happening to many
	-- objects in the selection. Without deferring we could end up with
	-- N^2 behavior if the whole selection is being updated (N part bounds
	-- changes x each bounds change requires looking at all N parts in
	-- the selection to calculate the new bounds)
	self._boundsChangedTracker =
		self._draggerSchema.BoundsChangedTracker.new(
			self._draggerContext,
			function(item)
				self._markSelectionDirtyCallback()
			end)
	
	local selectionWrapper = SelectionWrapper.new(self._draggerContext:getSelection())
	self._selectionWrapper = selectionWrapper
	self._boundsChangedTracker:install()

	self._selectionChangedConnection = selectionWrapper.onSelectionExternallyChanged:Connect(function()
		self:_processSelectionChanged()
	end)

	self:_updateSelectionInfo()
	
	if self._stateObject then
		self._stateObject:enter()
	end

	self._debugInProcessSelected = false
end

function DraggerToolModel._processDeselected(self: Class)
	self._debugInProcessDeselected = true

	if self._isMouseDown then
		self:_processMouseUp()
	end

	if self._modelProps.ShowPivotIndicator then
		self._draggerContext:setPivotIndicator(self._oldShowPivot)
	end

	-- Need to explicitly leave the last state now for correct behavior
	if self._stateObject then
		self._stateObject:leave()
		self._stateObject = nil
	end

	if self._selectionWrapper then
		self._selectionWrapper:destroy()
		self._selectionWrapper = nil
	end
	
	self._boundsChangedTracker:uninstall()
	self._debugInProcessDeselected = false

	if self._selectionChangedConnection then
		self._selectionChangedConnection:Disconnect()
		self._selectionChangedConnection = nil
	end
end

function DraggerToolModel._processSelectionChanged(self: Class)
	self:_updateSelectionInfo()

	if self._stateObject then
		self._stateObject:processSelectionChanged()
	end

	self:_scheduleRender()
end

function DraggerToolModel._processKeyDown(self: Class, keyCode: Enum.KeyCode)
	if self._stateObject then
		self._stateObject:processKeyDown(keyCode)
	end
end

function DraggerToolModel._processKeyUp(self: Class, keyCode: Enum.KeyCode)
	if self._stateObject then
		self._stateObject:processKeyUp(keyCode)
	end
end

function DraggerToolModel._processMouseDown(self: Class)
	if self._isMouseDown then
		-- Not ideal code. There are just too many situations where the engine
		-- passes us disbalanced mouseup / mousedown events for us to reliably
		-- handle all of them, so as an escape hatch, handle a mouse up if we
		-- get a mouse down without having gotten the preceeding mouse up.
		self:_processMouseUp()
	end

	local isDoubleClick
	local thisClickLocation = self._draggerContext:getMouseLocation()

	if (os.clock() - self._lastMouseClickTime) < DOUBLE_CLICK_TIME and
		thisClickLocation == self._lastMouseClickLocation then
		isDoubleClick = true
		self._lastMouseClickTime = 0 -- Suppress double-double clicks
	else
		isDoubleClick = false
		self._lastMouseClickTime = os.clock()
	end

	self._lastMouseClickLocation = thisClickLocation
	self._isMouseDown = true

	if self._stateObject then
		self._stateObject:processMouseDown(isDoubleClick)
	end
end

function DraggerToolModel._processMouseUp(self: Class)
	if not self._isMouseDown then
		-- There are various circumstances where the mouse can be down without
		-- us having started an associated drag. The engine has a habit of
		-- sending mismatched mouse up/down events in various rare edge cases.
		return
	end

	self._isMouseDown = false
	self._stateObject:processMouseUp()
end

--[[
	Called when the camera or mouse position changes, i.e., the world position
	currently under the mouse cursor has changed.
]]

function DraggerToolModel._processViewChanged(self: Class)
	if not self._stateObject then
		return
	end

	self._stateObject:processViewChanged()

	-- Derived world state may have changed as a result of the view update, so
	-- we need to manually trigger a re-render here.
	self:_scheduleRender()
end

function DraggerToolModel._updateHandles(self: Class)
	for _, handle in pairs(self._handlesList) do
		if handle.update then
			handle:update(self, self._selectionInfo)
		end
	end
end

function DraggerToolModel._updateSelectionInfo(self: Class, newSelectionInfoHint: any?)
	if newSelectionInfoHint then
		self._selectionInfo = newSelectionInfoHint
	else
		local selection: { Instance } = if self._selectionWrapper
			then self._selectionWrapper:get()
			else {}
		
		self._selectionInfo = self._draggerSchema.SelectionInfo.new(self._draggerContext, selection)
	end

	self._boundsChangedTracker:setSelection(self._selectionInfo)

	self:_updateHandles()
	self:_updatePivotIndicatorVisibility()
end

function DraggerToolModel._updatePivotIndicatorVisibility(self: Class)
	if self._modelProps.ShowPivotIndicator then
		if self._mainState == "DragSelecting" or #self._selectionWrapper:get() > 1 then
			self._draggerContext:setPivotIndicator(self._oldShowPivot)
		else
			self._draggerContext:setPivotIndicator(true)
		end
	end
end

function DraggerToolModel._processToolboxInitiatedFreeformSelectionDrag(self: Class)
	-- We didn't get an associated mouse down, so we have to set the mouse
	-- down tracking variable here.
	self._isMouseDown = true

	self:transitionToState("DraggingParts", {
		mouseLocation = self._draggerContext:getMouseLocation(),
		basisPoint = Vector3.zero, -- Just drag from the center of the object
		clickPoint = Vector3.zero,
	})
end

function DraggerToolModel._processToolboxInitiatedFaceDrag(self: Class, instances: { Instance })
	-- We didn't get an associated mouse down, so we have to set the mouse
	-- down tracking variable here.
	self._isMouseDown = true
	local connectionToBreak

	if instances[1]:IsA("VideoFrame") then
		local videoFrameContainer = Instance.new("SurfaceGui")
		videoFrameContainer.Enabled = true
		videoFrameContainer.Parent = workspace
		instances[1].Parent = videoFrameContainer

		-- When we the user drags out of the 3D view, the face instance that was
		-- passed to us will be removed. When that happens we need to also
		-- remove the container we made for it here.
		connectionToBreak = videoFrameContainer.ChildRemoved:Connect(function(instance)
			videoFrameContainer:Destroy()
		end)

		if self._selectionWrapper then
			self._selectionWrapper:set({ videoFrameContainer })
		end

		self:_updateSelectionInfo()
	end
	
	self:transitionToState("DraggingFaceInstance", connectionToBreak)
end

function DraggerToolModel._scheduleRender(self: Class)
	self._requestRenderCallback()
end

function DraggerToolModel.RegisterToolModule<T, Args...>(moduleName: string, module: DraggerState<T, Args...>)
	if not rawget(DraggerState, moduleName) then
		rawset(DraggerState, moduleName, module :: DraggerState)
	end
end

return DraggerToolModel
