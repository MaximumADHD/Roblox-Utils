
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local DraggerFramework = script.Parent.Parent
local Shared = DraggerFramework.Parent
local Math = require(DraggerFramework.Utility.Math)

local React = require(Shared.React)
local ReactRoblox = require(Shared.ReactRoblox)

local CULLING_MODE = Enum.AdornCullingMode.Never

local BASE_HANDLE_RADIUS = 0.10
local BASE_HANDLE_HITTEST_RADIUS = BASE_HANDLE_RADIUS * 4 -- Handle hittests bigger than it looks
local BASE_HANDLE_OFFSET = 0.60
local BASE_HANDLE_LENGTH = 4.00
local BASE_TIP_OFFSET = 0.20
local BASE_TIP_LENGTH = 0.25
local TIP_RADIUS_MULTIPLIER = 3
local SCREENSPACE_HANDLE_SIZE = 6
local HANDLE_DIM_TRANSPARENCY = 0.45
local HANDLE_THIN_BY_FRAC = 0.34
local HANDLE_THICK_BY_FRAC = 1.5

export type Props = {
	Axis: CFrame,
	Color: Color3,
	Scale: number,
	Outset: number?,
	Hovered: boolean,
	Thin: boolean,
	AlwaysOnTop: boolean,
}

local MoveHandleView = {}

function MoveHandleView.render(props: Props)
	local scale = props.Scale

	local length = scale * BASE_HANDLE_LENGTH
	local radius = scale * BASE_HANDLE_RADIUS

	local offset = scale * BASE_HANDLE_OFFSET
	offset = offset + length * (props.Outset or 0)

	local tipOffset = scale * BASE_TIP_OFFSET
	local tipLength = length * BASE_TIP_LENGTH

	if props.Thin then
		radius = radius * HANDLE_THIN_BY_FRAC
	end

	if props.Hovered then
		radius = radius * HANDLE_THICK_BY_FRAC
		tipLength = tipLength * HANDLE_THICK_BY_FRAC
	end

	local coneAtCFrame = props.Axis * CFrame.new(0, 0, -(offset + length))
	local tipAt = coneAtCFrame * Vector3.new(0, 0, -tipOffset)
	local tipAtScreen = workspace.CurrentCamera:WorldToScreenPoint(tipAt)
	local children = {}

	if not props.Hovered then
		children.Shaft = React.createElement("CylinderHandleAdornment", {
			Adornee = workspace.Terrain, -- Just a neutral anchor point
			ZIndex = 0,
			Radius = radius,
			Height = length,
			CFrame = props.Axis * CFrame.new(0, 0, -(offset + length * 0.5)),
			Color3 = props.Color,
			AlwaysOnTop = false,
			AdornCullingMode = CULLING_MODE,
		})

		if not props.Thin then
			children.Head = React.createElement("ConeHandleAdornment", {
				Adornee = workspace.Terrain,
				ZIndex = 0,
				Radius = TIP_RADIUS_MULTIPLIER * radius,
				Height = tipLength,
				CFrame = coneAtCFrame,
				Color3 = props.Color,
				AlwaysOnTop = false,
				AdornCullingMode = CULLING_MODE,
			})
		end
	end

	if props.AlwaysOnTop then
		children.DimmedShaft = React.createElement("CylinderHandleAdornment", {
			Adornee = workspace.Terrain, -- Just a neutral anchor point
			ZIndex = 0,
			Radius = radius,
			Height = length,
			CFrame = props.Axis * CFrame.new(0, 0, -(offset + length * 0.5)),
			Color3 = props.Color,
			AlwaysOnTop = true,
			Transparency = props.Hovered and 0.0 or HANDLE_DIM_TRANSPARENCY,
			AdornCullingMode = CULLING_MODE,
		})

		if not props.Thin then
			children.DimmedHead = React.createElement("ConeHandleAdornment", {
				Adornee = workspace.Terrain,
				ZIndex = 0,
				Radius = 3 * radius,
				Height = tipLength,
				CFrame = coneAtCFrame,
				Color3 = props.Color,
				AlwaysOnTop = true,
				Transparency = props.Hovered and 0.0 or HANDLE_DIM_TRANSPARENCY,
				AdornCullingMode = CULLING_MODE,
			})
		end
	elseif not props.Thin then
		local halfHandleSize = 0.5 * SCREENSPACE_HANDLE_SIZE

		children.ScreenBox = ReactRoblox.createPortal({
			MoveToolScreenspaceHandle = React.createElement("ScreenGui", {}, {
				Frame = React.createElement("Frame", {
					BorderSizePixel = 0,
					BackgroundColor3 = props.Color,
					Position = UDim2.new(0, tipAtScreen.X - halfHandleSize, 0, tipAtScreen.Y - halfHandleSize),
					Size = UDim2.new(0, SCREENSPACE_HANDLE_SIZE, 0, SCREENSPACE_HANDLE_SIZE),
					AdornCullingMode = CULLING_MODE,
				})
			})
		}, CoreGui)
	end

	return React.createElement("Folder", {}, children)
end

function MoveHandleView.hitTest(props: Props, mouseRay: Ray): number?
	local scale = props.Scale

	local length = scale * BASE_HANDLE_LENGTH
	local radius = scale * BASE_HANDLE_HITTEST_RADIUS
	local tipRadius = radius * TIP_RADIUS_MULTIPLIER

	local offset = scale * BASE_HANDLE_OFFSET
	offset = offset + length * (props.Outset or 0)
	
	local tipOffset = scale * BASE_TIP_OFFSET
	local tipLength = length * BASE_TIP_LENGTH
	local shaftEnd = offset + length

	if not props.AlwaysOnTop then
		-- Check the always on top 2D element at the tip of the vector
		local tipAt = props.Axis * Vector3.new(0, 0, -(offset + length + tipOffset))
		local tipAtScreen, _ = Workspace.CurrentCamera:WorldToScreenPoint(tipAt)
		local mouseAtScreen = Workspace.CurrentCamera:WorldToScreenPoint(mouseRay.Origin)
		local halfHandleSize = 0.5 * SCREENSPACE_HANDLE_SIZE

		if mouseAtScreen.X > tipAtScreen.X - halfHandleSize and
			mouseAtScreen.Y > tipAtScreen.Y - halfHandleSize and
			mouseAtScreen.X < tipAtScreen.X + halfHandleSize and
			mouseAtScreen.Y < tipAtScreen.Y + halfHandleSize
		then
			return 0
		end
	end

	local hasIntersection, hitDistance = Math.intersectRayRay(
			props.Axis.Position, props.Axis.LookVector,
			mouseRay.Origin, mouseRay.Direction.Unit)

	if not hasIntersection then
		return nil
	end

	-- Must have an intersection if the above intersect did
	local _, distAlongMouseRay =
		Math.intersectRayRay(
			mouseRay.Origin, mouseRay.Direction.Unit,
			props.Axis.Position, props.Axis.LookVector)

	local hitRadius =
		((props.Axis.Position + props.Axis.LookVector * hitDistance) -
		(mouseRay.Origin + mouseRay.Direction.Unit * distAlongMouseRay)).Magnitude

	if hitRadius < radius and hitDistance > offset and hitDistance < shaftEnd then
		return distAlongMouseRay
	elseif hitRadius < tipRadius and hitDistance > shaftEnd and hitDistance < shaftEnd + tipLength then
		return distAlongMouseRay
	else
		return nil
	end
end

--[[
	Returns:
		float Offset - From base CFrame
		float Size - Extending from CFrame + Offset
]]
function MoveHandleView.getHandleDimensionForScale(scale: number, outset: number?): (number, number)
	local length = scale * BASE_HANDLE_LENGTH

	local offset = scale * BASE_HANDLE_OFFSET
	offset = offset + length * (outset or 0)
	
	local tipLength = length * BASE_TIP_LENGTH
	return offset, length + tipLength
end

return MoveHandleView