--[[
	DraggerContext is a class which wraps all of the global state which the
	dragger needs to access to operate. This is the fixture implementation of
	the context, which allows the values which the globals will have to be
	expicitly set, to be used in doing testing.
]]

--!strict
local UserInputService = game:GetService("UserInputService")

local gotStudioService, StudioService = pcall(function ()
	return assert(game:GetService("StudioService"))
end)

local gotChangeHistoryService, ChangeHistoryService = pcall(function()
	return assert(game:GetService("ChangeHistoryService"))
end)

local gotDraggerService, DraggerService = pcall(function()
	return assert(game:GetService("DraggerService"))
end)

local DraggerFramework = script.Parent.Parent
local Colors = require(DraggerFramework.Utility.Colors)

local Packages = DraggerFramework.Parent
local Signal = require(Packages.Signal)

type Signal<T...> = Signal.Signal<T...>

local DraggerContext = {}
DraggerContext.__index = DraggerContext

const RAYCAST_DIRECTION_SCALE = 10000
const HANDLE_SCALE_FACTOR = 0.05
const MAX_UNDO_WAYPOINTS = 20

export type ConnectionLike = {
	Disconnect: <T>(self: T) -> (),
}

export type SignalLike<Args...> = {
	Connect: (self: any, handler: (Args...) -> ()) -> ConnectionLike,
}

export type SelectionLike = {
	Get: (self: any) -> { Instance },
	Set: (self: any, selection: { Instance }) -> (),
	SelectionChanged: SignalLike<{ Instance }>,
}

export type ISelection = 
	| SelectionLike
	| Selection

export type Config = {
	GuiTarget: BasePlayerGui,
	Selection: ISelection,
	Mouse: Mouse,

    ShowHoverOver: boolean?,
    AnimateHoverOver: boolean?,
    HoverAnimateSpeed: Enum.HoverAnimateSpeed?,
	ShowActiveInstanceHighlight: boolean?,
	ShouldAlignDraggedObjects: boolean?,
	ShouldSelectScopeByDefault: boolean?,
    ActiveHoverOverColor: Color3?,
    HoverOverColor: Color3?,
	HoverLineThickness: number?,
	SelectionLineThickness: number?,
    ActiveSelectionColor: Color3?,
    SelectionColor: Color3?,
	Camera: Camera?,
}

export type Gizmo = 
	| Attachment
	| Constraint
	| NoCollisionConstraint
	| WeldConstraint

type DraggerContext = {
    _guiTarget: BasePlayerGui,
    _selection: ISelection,
    _camera: Camera,
    _mouse: Mouse?,

    _useLocalSpace: boolean,
	_activeMouseIcon: string,
    _areCollisionsEnabled: boolean,
    _areConstraintsEnabled: boolean,
    _areConstraintDetailsShown: boolean,
    _drawConstraintsOnTop: boolean,
    _shouldJoinSurfaces: boolean,
    _isSimulating: boolean,
    _gridSize: number,
    _rotateIncrement: number,
    _undoWaypoints: {string},
    _isAltDown: boolean,
    _isCtrlDown: boolean,
    _isShiftDown: boolean,
    _hoverInstance: Instance?,
	_insertPoint: Vector3?,

	_config: Config,
	_settingValues: { [string]: any },

	SetDraggingFunction: ((isDragging: boolean, noRerenderSet: { Instance }?) -> ())?,
	DragUpdatedSignal: Signal<any>?,
}

type Proto = typeof(DraggerContext)
export type Class = setmetatable<DraggerContext, Proto>

function DraggerContext.new(config: Config): Class
	return setmetatable<<DraggerContext, Proto>>({
        _camera = config.Camera or workspace.CurrentCamera,
		_guiTarget = config.GuiTarget,
        _selection = config.Selection,
        _mouse = config.Mouse,

		_useLocalSpace = false,
		_activeMouseIcon = "",
		_areCollisionsEnabled = true,
		_areConstraintsEnabled = false,
		_areConstraintDetailsShown = false,
		_drawConstraintsOnTop = false,
		_shouldJoinSurfaces = true,
		_isSimulating = false,
		_undoWaypoints = {},

		_isAltDown = false,
		_isCtrlDown = false,
		_isShiftDown = false,

		_gridSize = 1,
		_rotateIncrement = math.rad(30),

		_config = config,
		_settingValues = {},
	}, DraggerContext)
end

-- What instance should the plugin's GUI objects get created under?
function DraggerContext.getGuiParent(self: Class): BasePlayerGui
	return self._guiTarget
end

function DraggerContext.getMouse(self: Class): Mouse?
	return self._mouse
end

function DraggerContext.setMouse(self: Class, mouse: Mouse?)
	self._mouse = mouse

	if mouse then
		mouse.Icon = self._activeMouseIcon
	end
end

function DraggerContext.setHoverInstance(self: Class, instance: Instance?)
	self._hoverInstance = instance
end

function DraggerContext.expectHoverInstance(self: Class, instance: Instance?)
	if self._hoverInstance ~= instance then
		local expected = instance and instance:GetFullName() or "nil"
		local got = self._hoverInstance and self._hoverInstance:GetFullName() or "nil"
		error("Wrong hover instance,\n    Expected: " .. expected .. "\n    Got: " .. got)
	end
end

function DraggerContext.shouldUseLocalSpace(self: Class): boolean
	return self._useLocalSpace
end

function DraggerContext.setUseLocalSpace(self: Class, value: boolean)
	self._useLocalSpace = value
end

function DraggerContext.areCollisionsEnabled(self: Class): boolean
	return self._areCollisionsEnabled
end

function DraggerContext.setCollisionsEnabled(self: Class, value: boolean)
	self._areCollisionsEnabled = value
end

function DraggerContext.areConstraintsEnabled(self: Class): boolean
	return self._areConstraintsEnabled
end

function DraggerContext.setConstraintsEnabled(self: Class, value: boolean)
	self._areConstraintsEnabled = value
end

function DraggerContext.areConstraintDetailsShown(self: Class): boolean
	return self._areConstraintDetailsShown
end

function DraggerContext.setConstraintDetailsShown(self: Class, value: boolean)
	self._areConstraintDetailsShown = value
end

function DraggerContext.shouldDrawConstraintsOnTop(self: Class): boolean
	return self._drawConstraintsOnTop
end

function DraggerContext.setDrawConstraintsOnTop(self: Class, value: boolean)
	self._drawConstraintsOnTop = value
end

function DraggerContext.shouldJoinSurfaces(self: Class): boolean
	return self._shouldJoinSurfaces
end

function DraggerContext.setJoinSurfaces(self: Class, value: boolean)
	assert(typeof(value) == "boolean") -- Don't try to pass the Enum
	self._shouldJoinSurfaces = value
end

function DraggerContext.shouldShowHover(self: Class): boolean
	return self._config.ShowHoverOver or false
end

function DraggerContext.shouldAnimateHover(self: Class): boolean
	return self._config.AnimateHoverOver or false
end

function DraggerContext.shouldSelectScopeByDefault(self: Class): boolean
	return if self._config.ShouldSelectScopeByDefault ~= nil
		then self._config.ShouldSelectScopeByDefault
		else true
end

function DraggerContext.getHoverAnimationSpeedInSeconds(self: Class): number
	local speed = self._config.HoverAnimateSpeed or Enum.HoverAnimateSpeed.Medium

	if speed == Enum.HoverAnimateSpeed.VerySlow then
		return 2
	elseif speed == Enum.HoverAnimateSpeed.Slow then
		return 1
	elseif speed == Enum.HoverAnimateSpeed.Medium then
		return 0.5
	elseif speed == Enum.HoverAnimateSpeed.Fast then
		return 0.25
	elseif speed == Enum.HoverAnimateSpeed.VeryFast then
		return 0.1
	end

	return 0
end

function DraggerContext.getHoverBoxColor(self: Class, isActive: boolean)
    if isActive then
		return self._config.ActiveHoverOverColor or Color3.fromRGB(255, 204, 153)
    else
        return self._config.HoverOverColor or Color3.fromRGB(178, 229, 255)
    end
end

function DraggerContext.getHoverLineThickness(self: Class)
	return self._config.HoverLineThickness or 0.04
end

function DraggerContext.getSelectionBoxColor(self: Class, isActive: boolean?)
    if isActive then
        return self._config.ActiveSelectionColor or Color3.fromRGB(255, 204, 153)
    else
        return self._config.SelectionColor or Color3.fromRGB(178, 229, 255)
    end
end

function DraggerContext.getGeometrySnapColor(self: Class)
	return DraggerService.GeometrySnapColor
end

function DraggerContext.getHandleScale(self: Class, focusPoint: Vector3?)
    local camera = self._camera

	local focus = focusPoint or camera.Focus.Position
    local distance = (camera.CFrame.Position - focus).Magnitude

	local angleFrac = math.sin(math.rad(camera.FieldOfView))
	return angleFrac * distance * HANDLE_SCALE_FACTOR
end

function DraggerContext.getMouseUnitRay(self: Class)
	if self._mouse then
		return self._mouse.UnitRay
	else
		return self:viewportPointToRay(self:getMouseLocation())
	end
end

function DraggerContext.getMouseRay(self: Class): Ray
	local unitRay = self:getMouseUnitRay()
	return Ray.new(unitRay.Origin, unitRay.Direction * RAYCAST_DIRECTION_SCALE)
end

function DraggerContext.getMouseLocation(self: Class)
	return UserInputService:GetMouseLocation()
end

function DraggerContext.viewportPointToRay(self: Class, mouseLocation: Vector2)
	return self._camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
end

function DraggerContext.worldToViewportPoint(self: Class, worldPoint: Vector3)
	return self._camera:WorldToViewportPoint(worldPoint)
end

function DraggerContext.getViewportSize(self: Class)
	return self._camera.ViewportSize
end

function DraggerContext.setMouseIcon(self: Class, icon: string)
	if self._mouse then
		self._mouse.Icon = icon
	end

	self._activeMouseIcon = icon
end

function DraggerContext.expectMouseIcon(self: Class, icon: string)
	if self._activeMouseIcon ~= icon then
		local expected = icon or "nil"
		local got = self._activeMouseIcon or "nil"
		error("Wrong mouse icon,\n    Expected: " .. expected .. "\n    Got: " .. got)
	end
end

function DraggerContext.getSelection(self: Class): SelectionLike
	return self._selection
end

-- Are non-anchored parts in the world currently being physically simulated?
-- (i.e. are they moving around of thier own accord)
function DraggerContext.isSimulating(self: Class)
	return self._isSimulating
end

function DraggerContext.setSimulating(self: Class, value: boolean)
	self._isSimulating = value
end

function DraggerContext.isAltKeyDown(self: Class)
	return self._isAltDown
end

function DraggerContext.isCtrlKeyDown(self: Class)
	return self._isCtrlDown
end

function DraggerContext.isShiftKeyDown(self: Class)
	return self._isShiftDown
end

function DraggerContext.shouldExtendSelection(self: Class)
	return self:isCtrlKeyDown() or self:isShiftKeyDown()
end

function DraggerContext.setCtrlAltShift(self: Class, ctrl: boolean, alt: boolean, shift: boolean)
	self._isCtrlDown = ctrl
	self._isAltDown = alt
	self._isShiftDown = shift
end

function DraggerContext.getGridSize(self: Class)
	return self._gridSize
end

function DraggerContext.snapToGridSize(self: Class, distance: number)
	-- Use an exact check here because we're in control of things, we can set
	-- exactly grid size = 0 when snapping should be disabled.
	if self._gridSize > 0 then
		return math.floor(distance / self._gridSize + 0.5) * self._gridSize
	else
		return distance
	end
end

function DraggerContext.getRotateIncrement(self: Class)
	return self._rotateIncrement
end

function DraggerContext.setGridSize(self: Class, value: number)
	self._gridSize = math.max(value, 0.001)
end

function DraggerContext.setRotateIncrement(self: Class, value: number)
	self._rotateIncrement = value
end

function DraggerContext.gizmoRaycast(self: Class, origin: Vector3, direction: Vector3, raycastParams: RaycastParams?): RaycastResult<Gizmo>?
	if gotStudioService then
		return StudioService:GizmoRaycast(origin, direction, raycastParams)
	end

	return nil
end

function DraggerContext.setInsertPoint(self: Class, location: Vector3)
	self._insertPoint = location
end

function DraggerContext.expectInsertPoint(self: Class, location: Vector3)
	if self._insertPoint ~= location then
		local expected = tostring(location)
		local got = tostring(self._insertPoint)
		error("Wrong insert point,\n    Expected: " .. expected .. "\n    Got: " .. got)
	end
end

function DraggerContext.shouldShowActiveInstanceHighlight(self: Class)
	return self._config.ShowActiveInstanceHighlight or false
end

function DraggerContext.shouldAlignDraggedObjects(self: Class)
	return self._config.ShouldAlignDraggedObjects or false
end

function DraggerContext.addUndoWaypoint(self: Class, waypointIdentifier: string, waypointText: string)
	if gotChangeHistoryService then
		pcall(function ()
			ChangeHistoryService:SetWaypoint(waypointIdentifier)
		end)
	end

	table.insert(self._undoWaypoints, waypointIdentifier)

	while #self._undoWaypoints > MAX_UNDO_WAYPOINTS do
		table.remove(self._undoWaypoints, 1)
	end
end

function DraggerContext.expectMostRecentUndoWaypoint(self: Class, waypointIdentifier: string)
	local mostRecent = self._undoWaypoints[#self._undoWaypoints]

	if mostRecent ~= waypointIdentifier then
		error("Wrong last undo waypoint,\n    Expected: " .. waypointIdentifier ..
			"\n    Got: " .. (mostRecent or "<none>"))
	end
end

function DraggerContext.expectAndUndo(self: Class, waypointIdentifier: string)
	self:expectMostRecentUndoWaypoint(waypointIdentifier)
	self._undoWaypoints[#self._undoWaypoints] = nil

	if gotChangeHistoryService then
		pcall(function ()
			ChangeHistoryService:Undo()
		end)
	end
end

function DraggerContext.getText(self: Class, scope: string, key: string, args: {string}?)
	if args then
		return ("%s.%s (%s)").format(scope, key, table.concat(args, ","))
	else
		return ("%s.%s").format(scope, key)
	end
end

function DraggerContext.getThemeColor(self: Class, item: Enum.StudioStyleGuideColor)
	if item == Enum.StudioStyleGuideColor.MainBackground then
		return Colors.WHITE
	else
		return Colors.BLACK
	end
end

function DraggerContext.getSetting(self: Class, name: string)
	return self._settingValues[name]
end

function DraggerContext.setSetting(self: Class, name: string, value: any)
	self._settingValues[name] = value
end

function DraggerContext.setPivotIndicator(self: Class, state: boolean)
	if gotDraggerService then
		local oldValue = DraggerService.ShowPivotIndicator
		DraggerService.ShowPivotIndicator = state
		return oldValue
	end

	return false
end

return DraggerContext
