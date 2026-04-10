--[[
	Checks whether the current mouse location or camera orientation has changed.
	Used to response to the world position under the mouse changing.
]]


local ViewChangeDetector = {}
ViewChangeDetector.__index = ViewChangeDetector

type ViewChangeDetector = {
	_mouse: Mouse,
	_lastCameraCFrame: CFrame,
	_lastMouseX: number,
	_lastMouseY: number,
}

type Proto = typeof(ViewChangeDetector)
export type Class = setmetatable<ViewChangeDetector, Proto>

function ViewChangeDetector.new(mouse: Mouse): Class
	local currentCamera = workspace.CurrentCamera

	return setmetatable({
		_mouse = mouse,
		_lastCameraCFrame = currentCamera and currentCamera.CFrame or CFrame.identity,
		_lastMouseX = mouse.X,
		_lastMouseY = mouse.Y,
	}, ViewChangeDetector)
end

function ViewChangeDetector.poll(self: Class): boolean
	local camera = workspace.CurrentCamera
	local mouse = self._mouse

	if (self._lastCameraCFrame ~= camera.CFrame) or (self._lastMouseX ~= mouse.X) or (self._lastMouseY ~= mouse.Y) then
		self._lastCameraCFrame = camera.CFrame
		self._lastMouseX = mouse.X
		self._lastMouseY = mouse.Y
		return true
	end

	return false
end

return ViewChangeDetector
