--[[
	Displays an animated SelectionBox adornment on the hovered Workspace object.
]]

-- Services
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local DraggerFramework = script.Parent.Parent
local Packages = DraggerFramework.Parent
local React = require(Packages.React)

local ANIMATED_HOVER_BOX_UPDATE_BIND_NAME = "AnimatedHoverBoxUpdate"

--[[
	Return a hover color that is a blend between the Studio settings HoverOverColor
	and SelectColor, based on the current time and HoverAnimateSpeed.
]]
local function getHoverColorForTime(color1: Color3, color2: Color3, animatePeriod: number, currentTime: number): Color3
	local alpha = 0.5 + 0.5 * math.sin(currentTime / animatePeriod * math.pi)
	return color2:Lerp(color1, alpha)
end

export type Props = {
	HoverTarget: Instance,
	SelectColor: Color3,
	HoverColor: Color3,
	AnimatePeriod: number?,
	LineThickness: number,
	SelectionBoxComponent: SelectionBox | Highlight,
}

local function AnimatedHoverBox(props: Props)
	local currentColor, setCurrentColor = React.useBinding(
		getHoverColorForTime(
			props.SelectColor,
			props.HoverColor,
			props.AnimatePeriod or math.huge, 
			0
		)
	)

	React.useEffect(function ()
		local isMounted = true
		local startTime = tick()
		local bindName = ANIMATED_HOVER_BOX_UPDATE_BIND_NAME .. "_" .. HttpService:GenerateGUID(false)

		RunService:BindToRenderStep(bindName, Enum.RenderPriority.First.Value, function()
			if isMounted then
				local deltaT = tick() - startTime
				local color = getHoverColorForTime(props.SelectColor, props.HoverColor, props.AnimatePeriod or math.huge, deltaT)
				setCurrentColor(color)
			end
		end)

		return function ()
			isMounted = false
			RunService:UnbindFromRenderStep(bindName)
		end
	end, {
		props.HoverColor,
		props.SelectColor,
		props.AnimatePeriod
	})

	return React.createElement("Highlight", {
		Adornee = props.HoverTarget,
		OutlineColor = currentColor,
		OutlineTransparency = 0,
		FillColor = currentColor,
		FillTransparency = 1,
	})
end

return AnimatedHoverBox
