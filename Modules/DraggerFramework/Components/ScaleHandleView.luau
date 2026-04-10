--[[
	Component that displays a spherical scale handle.
]]

local ScaleHandleView = {}

local DraggerFramework = script.Parent.Parent
local Packages = DraggerFramework.Parent
local React = require(Packages.React)

-- Dragger Framework
local Math = require(DraggerFramework.Utility.Math)

local CULLING_MODE = Enum.AdornCullingMode.Never

local HANDLE_RADIUS = 0.5
local HANDLE_RADIUS_HOVERED_SCALE = 1.15 -- Radius scale when handle is hovered
local HANDLE_HITTEST_RADIUS_SCALE = 2.5 -- Radius scale for hit testing

local HANDLE_TRANSPARENCY_START = 0.75
local HANDLE_TRANSPARENCY_END = 0.2
local HANDLE_OFFSET = 1.5

local HANDLE_THIN_BY_FRAC = 0.34

export type Props = {
	NormalId: number?,
	HandleCFrame: CFrame,
	Color: Color3,
	Scale: number,
	Hovered: boolean,
	Thin: boolean,
}

local function getDebugSettingValue(name: string, defaultValue: number)
	local setting = workspace:FindFirstChild(name)

	if setting and setting:IsA("NumberValue") then
		return setting.Value
	end
	
	return defaultValue
end

function ScaleHandleView.render(props: Props)
	-- DEBUG: Allow designers to play with handle settings.
	-- Remove before shipping!
	HANDLE_OFFSET = getDebugSettingValue("ScaleHandleOffset", 1.5)
	HANDLE_RADIUS = getDebugSettingValue("ScaleHandleRadius", 0.5)
	HANDLE_TRANSPARENCY_START = getDebugSettingValue("ScaleHandleTransparencyStart", 0.75)
	HANDLE_TRANSPARENCY_END = getDebugSettingValue("ScaleHandleTransparencyEnd", 0.2)

	local children = {}
	local color = props.Color
	local cframe = props.HandleCFrame * CFrame.new(0, 0, -HANDLE_OFFSET * props.Scale)
	local radius = HANDLE_RADIUS * props.Scale

	if props.Thin then
		radius = radius * HANDLE_THIN_BY_FRAC
	end

	if not props.Hovered then
		children.HiddenHandle = React.createElement("SphereHandleAdornment", {
			Adornee = workspace.Terrain,
			AlwaysOnTop = true,
			CFrame = cframe,
			Color3 = color,
			Radius = radius,
			Transparency = HANDLE_TRANSPARENCY_START,
			ZIndex = 1,
			AdornCullingMode = CULLING_MODE,
		})
	end

	local transparencyEnd = HANDLE_TRANSPARENCY_END

	if props.Hovered then
		radius = radius * HANDLE_RADIUS_HOVERED_SCALE
		transparencyEnd = 0
	end

	children.Handle = React.createElement("SphereHandleAdornment", {
		Adornee = workspace.Terrain,
		AlwaysOnTop = props.Hovered,
		CFrame = cframe,
		Color3 = color,
		Radius = radius,
		Transparency = transparencyEnd,
		ZIndex = 0,
		AdornCullingMode = CULLING_MODE,
	})

	return React.createElement("Folder", {}, children)
end

--[[
	Check if the mouse is over the scale handle.
	DON'T include the hitTest radius. We will deal with the scale handles by
	first checking if we hit any of them, and taking that one if we do.
	If we don't actually hit any, then we see if we're within the hitTest radius
	for any of them, and if we are take the closest one.
]]
function ScaleHandleView.hitTest(props: Props, mouseRay: Ray): number?
	local radius = HANDLE_RADIUS * props.Scale
	local unitRay = mouseRay.Unit

	local worldPosition = props.HandleCFrame * Vector3.new(0, 0, -HANDLE_OFFSET * props.Scale)
	local result, t = Math.intersectRaySphere(unitRay.Origin, unitRay.Direction, worldPosition, radius)

	if result then
		return t
	else
		return nil
	end
end

function ScaleHandleView.distanceFromHandle(props: Props, mouseRay: Ray): number
	local hitTestRadius = HANDLE_RADIUS * props.Scale * HANDLE_HITTEST_RADIUS_SCALE
	local worldPosition = props.HandleCFrame * Vector3.new(0, 0, -HANDLE_OFFSET * props.Scale)

	local rayDir = mouseRay.Direction.Unit
	local projectedLength = (worldPosition - mouseRay.Origin):Dot(rayDir)

	local projectedPoint = mouseRay.Origin + rayDir * projectedLength
	local distanceToRay = (worldPosition - projectedPoint).Magnitude

	return distanceToRay - hitTestRadius
end

return ScaleHandleView
