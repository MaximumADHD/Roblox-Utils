--[[
	DraggerToolComponent is a React component which drives an internal
	DraggerToolModel with inputs in a real-time situation such as ingame or in
	studio plugin.
]]

-- Services
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local DraggerFramework = script.Parent
local Packages = DraggerFramework.Parent
local React = require(Packages.React)

local Implementation = DraggerFramework.Implementation
local DraggerContext = require(Implementation.DraggerContext)
local DraggerToolModel = require(Implementation.DraggerToolModel)

-- Utilities
local Utility = DraggerFramework.Utility
local ViewChangeDetector = require(Utility.ViewChangeDetector)
local shouldDragAsFace = require(Utility.shouldDragAsFace)

-- Constants
local DRAGGER_UPDATE_BIND_NAME = "DraggerToolViewUpdate"

export type Props = {
	DraggerContext: DraggerContext.Class,
	DraggerSchema: any,
	DraggerSettings: any,
	Mouse: PluginMouse,
	InitialMouseDown: boolean?,
}

local function DraggerToolComponent(props: Props)
	local redraw, setRedraw = React.useState(0)
	local viewBoundsAreDirty, setViewBoundsAreDirty = React.useState(false)
	local selectionBoundsAreDirty, setSelectionBoundsAreDirty = React.useState(false)
	
	local requestRedraw = React.useMemo(function ()
		return function()
			setRedraw(function(t: number)
				return t + 1
			end)
		end
	end, {})

	local draggerToolModel = React.useMemo(function ()
		assert(props.DraggerSchema)
		assert(props.DraggerContext)
		assert(props.DraggerSettings)

		return DraggerToolModel.new(
			props.DraggerContext,
			props.DraggerSchema,
			props.DraggerSettings,
			requestRedraw,
			function() setViewBoundsAreDirty(true) end,
			function() setSelectionBoundsAreDirty(true) end
		)
	end, {
		props.DraggerContext,
		props.DraggerSchema,
		props.DraggerSettings,
		redraw,
	})
	
	React.useEffect(function ()
		local isMounted = true
		local bindName = DRAGGER_UPDATE_BIND_NAME .. HttpService:GenerateGUID(false)

		local function requestRender()
			if isMounted then
				setRedraw(function(t: number)
					return t + 1
				end)
			end
		end

		local draggerToolModel = DraggerToolModel.new(
			props.DraggerContext,
			props.DraggerSchema,
			props.DraggerSettings,
			requestRender,
			function() viewBoundsAreDirty = true end,
			function() selectionBoundsAreDirty = true end
		)

		-- Select it first before we potentially start feeding input to it
		draggerToolModel:_processSelected()

		-- Trigger a render now that the model exists
		draggerToolModel:render()

		-- This should never return true because we disconnect connections before
		-- tearing down our state.
		local function bailed(_reason)
			return not isMounted
		end

		local mouse = props.Mouse

		local mouseDownConn = mouse.Button1Down:Connect(function()
			if bailed("Button1Down") then return end
			draggerToolModel:_processMouseDown()
		end)

		local mouseUpConn = mouse.Button1Up:Connect(function()
			if bailed("Button1Up") then return end
			draggerToolModel:_processMouseUp()
		end)

		local keyDownConn = UserInputService.InputBegan:Connect(function(input, _gameProcessed)
			if bailed("KeyDown") then return end
			if input.UserInputType == Enum.UserInputType.Keyboard then
				draggerToolModel:_processKeyDown(input.KeyCode)
			end
		end)

		local keyUpConn = UserInputService.InputEnded:Connect(function(input, _gameProcessed)
			if bailed("KeyUp") then return end
			if input.UserInputType == Enum.UserInputType.Keyboard then
				draggerToolModel:_processKeyUp(input.KeyCode)
			end
		end)

		local dragEnterConn = mouse.DragEnter:Connect(function(instances)
			if bailed("DragEnter") then return end
			if #instances > 0 then
				if #instances == 1 and shouldDragAsFace(instances[1]) then
					draggerToolModel:_processToolboxInitiatedFaceDrag(instances)
				else
					draggerToolModel:_processToolboxInitiatedFreeformSelectionDrag()
				end
			end
		end)

		local viewChange = ViewChangeDetector.new(mouse)
		local lastUseLocalSpace = props.DraggerContext:shouldUseLocalSpace()

		RunService:BindToRenderStep(bindName, Enum.RenderPriority.First.Value, function()
			if not isMounted then return end
			draggerToolModel:update()

			local shouldUpdateView = false
			local shouldUpdateSelection = false

			if viewChange:poll() then
				shouldUpdateView = true
			end

			if selectionBoundsAreDirty then
				selectionBoundsAreDirty = false
				shouldUpdateSelection = true
			end
			if viewBoundsAreDirty then
				viewBoundsAreDirty = false
				shouldUpdateView = true
			end

			local currentUseLocalSpace = props.DraggerContext:shouldUseLocalSpace()

			if currentUseLocalSpace ~= lastUseLocalSpace then
				-- Can't use a changed event for this, since Changed doesn't fire
				-- for changes to UseLocalSpace.
				shouldUpdateSelection = true
			end

			if shouldUpdateSelection then
				draggerToolModel:_processSelectionChanged()
			end
			
			if shouldUpdateView then
				draggerToolModel:_processViewChanged()
			end

			lastUseLocalSpace = currentUseLocalSpace
		end)

		if props.InitialMouseDown then
			task.defer(function()
				if isMounted then
					draggerToolModel:_processMouseDown()
				end
			end)
		end

		return function()
			isMounted = false

			mouseDownConn:Disconnect()
			mouseUpConn:Disconnect()
			keyDownConn:Disconnect()
			keyUpConn:Disconnect()

			dragEnterConn:Disconnect()
			RunService:UnbindFromRenderStep(bindName)

			-- Deselect after we stop potentially sending events
			draggerToolModel:_processDeselected()
		end
	end, {
		props.Mouse,
		props.DraggerSchema,
		props.DraggerContext,
		props.DraggerSettings,
		props.InitialMouseDown,
		draggerToolModel,
	} :: {any})

	return nil
end

return DraggerToolComponent