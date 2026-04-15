--[[
	DraggerToolComponent is a React component which drives an internal
	DraggerToolModel with inputs in a real-time situation such as ingame or in
	studio plugin.
]]

-- Services
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Components = script.Parent
local DraggerFramework = Components.Parent
local Packages = DraggerFramework.Parent
local React = require(Packages.React)

local Implementation = DraggerFramework.Implementation
local DraggerContext = require(Implementation.DraggerContext)
local DraggerToolModel = require(Implementation.DraggerToolModel)

-- Utilities
local Utility = DraggerFramework.Utility
local shouldDragAsFace = require(Utility.shouldDragAsFace)
local ViewChangeDetector = require(Utility.ViewChangeDetector)

-- Constants
local DRAGGER_UPDATE_BIND_NAME = "DraggerToolViewUpdate"
type DraggerSettings = DraggerToolModel.DraggerSettings
type DraggerToolModel = DraggerToolModel.Class

export type Props = {
	DraggerContext: DraggerContext.Class,
	DraggerSettings: DraggerSettings,
	DraggerSchema: any,

	Mouse: Mouse,
	InitialMouseDown: boolean?,
}

local function DraggerToolComponent(props: Props)
	local viewBoundsAreDirty = React.useRef(false)
	local selectionBoundsAreDirty = React.useRef(false)
	local draggerToolModelRef = React.useRef(nil :: DraggerToolModel?)
	local renderNode, setRenderNode = React.useState(nil :: React.Node?)
	
	local requestRedraw = React.useMemo(function ()
		return function()
			local draggerToolModel = draggerToolModelRef.current

			if draggerToolModel then
				local render = draggerToolModel:render()
				setRenderNode(render)
			end
		end
	end, {})

	React.useEffect(function ()
		local draggerToolModel = DraggerToolModel.new(
			props.DraggerContext,
			props.DraggerSchema,
			props.DraggerSettings,
			requestRedraw,
			function() viewBoundsAreDirty.current = true end,
			function() selectionBoundsAreDirty.current = true end
		)

		draggerToolModelRef.current = draggerToolModel

		if props.InitialMouseDown then
			task.defer(function()
				if draggerToolModel then
					draggerToolModel:_processMouseDown()
				end
			end)
		end

		-- Select it first before we potentially start feeding input to it
		draggerToolModel:_processSelected()

		-- Trigger a render now that the model exists
		requestRedraw()

		return function()
			draggerToolModel:_processDeselected()
		end
	end, {
		props.DraggerSchema,
		props.DraggerContext,
		props.DraggerSettings,
	})

	-- Input wiring and render loop
	React.useEffect(function ()
		local mouse = props.Mouse
		local bindName = DRAGGER_UPDATE_BIND_NAME .. HttpService:GenerateGUID(false)

		local mouseDownConn = mouse.Button1Down:Connect(function()
			local draggerToolModel = draggerToolModelRef.current
			
			if draggerToolModel then
				draggerToolModel:_processMouseDown()
			end
		end)

		local mouseUpConn = mouse.Button1Up:Connect(function()
			local draggerToolModel = draggerToolModelRef.current

			if draggerToolModel then
				draggerToolModel:_processMouseUp()
			end
		end)

		local keyDownConn = UserInputService.InputBegan:Connect(function(input, _gameProcessed)
			if input.UserInputType == Enum.UserInputType.Keyboard then
				local draggerToolModel = draggerToolModelRef.current

				if draggerToolModel then
					draggerToolModel:_processKeyDown(input.KeyCode)
				end
			end
		end)

		local keyUpConn = UserInputService.InputEnded:Connect(function(input, _gameProcessed)
			if input.UserInputType == Enum.UserInputType.Keyboard then
				local draggerToolModel = draggerToolModelRef.current

				if draggerToolModel then
					draggerToolModel:_processKeyUp(input.KeyCode)
				end
			end
		end)

		local dragEnterConn: RBXScriptConnection?

		if mouse:IsA("PluginMouse") then
			dragEnterConn = mouse.DragEnter:Connect(function(instances)
				local draggerToolModel = draggerToolModelRef.current

				if #instances > 0 and draggerToolModel then
					if #instances == 1 and shouldDragAsFace(instances[1]) then
						draggerToolModel:_processToolboxInitiatedFaceDrag(instances)
					else
						draggerToolModel:_processToolboxInitiatedFreeformSelectionDrag()
					end
				end
			end)
		end

		local viewChange = ViewChangeDetector.new(mouse)
		local lastUseLocalSpace = props.DraggerContext:shouldUseLocalSpace()

		RunService:BindToRenderStep(bindName, Enum.RenderPriority.First.Value, function()
			local draggerToolModel = draggerToolModelRef.current

			if draggerToolModel then
				draggerToolModel:update()
			else
				return
			end
			
			local shouldUpdateView = false
			local shouldUpdateSelection = false

			if viewChange:poll() then
				shouldUpdateView = true
			end

			if selectionBoundsAreDirty.current then
				selectionBoundsAreDirty.current = false
				shouldUpdateSelection = true
			end

			if viewBoundsAreDirty.current then
				viewBoundsAreDirty.current = false
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

		return function()
			local draggerToolModel = draggerToolModelRef.current
			mouseDownConn:Disconnect()
			mouseUpConn:Disconnect()
			keyDownConn:Disconnect()
			keyUpConn:Disconnect()
			
			if dragEnterConn then
				dragEnterConn:Disconnect()
			end

			RunService:UnbindFromRenderStep(bindName)

			-- Deselect after we stop potentially sending events
			if draggerToolModel then
				draggerToolModel:_processDeselected()
			end
		end
	end, { props.Mouse })

	return renderNode
end

return DraggerToolComponent
