--[[
	Component that displays an "L" label near the bottom-right corner of the
	passed in bounding volume.
]]

local DraggerFramework = script.Parent.Parent
local Packages = DraggerFramework.Parent
local React = require(Packages.React)

local PADDING = 3
local Implementation = DraggerFramework.Implementation
local DraggerContext = require(Implementation.DraggerContext)

type DraggerContext = DraggerContext.Class

export type Props = {
	CFrame: CFrame,
	Size: Vector3,
	DraggerContext: DraggerContext,

	BackgroundTransparency: number?,
	Font: Enum.Font?,
	TextSize: number?,
	TextColor3: Color3?,
	TextStrokeColor3: Color3?,
	TextStrokeTransparency: number?,
}

const defaultProps = {
	BackgroundTransparency = 1,
	Font = Enum.Font.ArialBold,
	TextSize = 16,
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeColor3 = Color3.new(0, 0, 0),
	TextStrokeTransparency = 0,
}

local function LocalSpaceIndicator(props: Props): React.ReactElement?
	local draggerContext = props.DraggerContext
	local cframe = props.CFrame
	local halfSize = props.Size / 2

	-- Compute the bounding box corners in object space.
	local max = halfSize
	local min = -halfSize

	local font = props.Font or defaultProps.Font
	local textSize = props.TextSize or defaultProps.TextSize
	local textColor3 = props.TextColor3 or defaultProps.TextColor3
	local textStrokeColor3 = props.TextStrokeColor3 or defaultProps.TextStrokeColor3
	local textStrokeTransparency = props.TextStrokeTransparency or defaultProps.TextStrokeTransparency
	local backgroundTransparency = props.BackgroundTransparency or defaultProps.BackgroundTransparency

	local corners = {
		Vector3.new(min.X, min.Y, min.Z),
		Vector3.new(min.X, max.Y, min.Z),
		Vector3.new(min.X, max.Y, max.Z),
		Vector3.new(min.X, min.Y, max.Z),
		Vector3.new(max.X, min.Y, min.Z),
		Vector3.new(max.X, max.Y, min.Z),
		Vector3.new(max.X, max.Y, max.Z),
		Vector3.new(max.X, min.Y, max.Z),
	}

	local projectedCorners = {} :: {{
		point: Vector2,
		onScreen: boolean,
	}}

	local optimalX, optimalY = -math.huge, -math.huge

	-- Find the optimal screen position for the label. This will be the maximum
	-- of all the points.
	for i = 1, #corners do
		-- For each projected corner record whether it is onscreen, but use the
		-- point for the optimal point calculation regardless. Not using all of
		-- the bounding volume corners can cause the "L" indicator to jump around
		-- when the bounding volume is partly outside the viewport.
		local worldPoint = cframe:PointToWorldSpace(corners[i])
		local screenPoint, onScreen = draggerContext:worldToViewportPoint(worldPoint)
		local point = Vector2.new(screenPoint.X, screenPoint.Y)

		table.insert(projectedCorners, {
			point = point,
			onScreen = onScreen,
		})

		optimalX = math.max(optimalX, point.X)
		optimalY = math.max(optimalY, point.Y)
	end

	-- Take the projected point closest to the optimal point to use as the
	-- position of the label.
	local optimalPoint = Vector2.new(optimalX, optimalY)
	local minDistanceToOptimal = math.huge
	local isProjectedCornerOnScreen = false
	local position = Vector2.zero

	for i = 1, #projectedCorners do
		local screenPoint = projectedCorners[i].point
		local distanceToOptimal = (screenPoint - optimalPoint).Magnitude
		if distanceToOptimal < minDistanceToOptimal then
			minDistanceToOptimal = distanceToOptimal
			position = screenPoint
			isProjectedCornerOnScreen = projectedCorners[i].onScreen
		end
	end

	if not isProjectedCornerOnScreen then
		return nil
	end

	-- Label size calculation is an approximation to avoid using TextService
	-- to measure a single-character string.
	local labelSize = textSize + PADDING * 2

	return React.createElement("ScreenGui", {}, {
		React.createElement("TextLabel", {
			BackgroundTransparency = backgroundTransparency,
			Position = UDim2.fromOffset(position.X, position.Y),
			Size = UDim2.fromOffset(labelSize, labelSize),
			Font = font,
			TextSize = textSize,
			Text = "L",
			TextColor3 = textColor3,
			TextStrokeColor3 = textStrokeColor3,
			TextStrokeTransparency = textStrokeTransparency,
			Selectable = false,
		})
	})
end

return LocalSpaceIndicator
