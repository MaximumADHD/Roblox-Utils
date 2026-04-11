--[[
	Component that displays a rubber band-style selection frame.
]]

local DraggerFramework = script.Parent.Parent
local Packages = DraggerFramework.Parent
local React = require(Packages.React)

local Colors = require(DraggerFramework.Utility.Colors)

export type Props = {
	BackgroundColor3: Color3?,
	BackgroundTransparency: number?,
	BorderColor3: Color3?,

	DragStartLocation: Vector2,
	DragEndLocation: Vector2,
}

local function DragSelectionView(props: Props): React.Node?
	local min = props.DragStartLocation
	local max = props.DragEndLocation

	if not min or not max then
		return nil
	end

	local size = max - min
	local backgroundColor3 = props.BackgroundColor3 or Colors.BLACK
	local backgroundTransparency = props.BackgroundTransparency or 1
	local borderColor3 = props.BorderColor3 or Colors.GRAY

	return React.createElement("ScreenGui", {
		IgnoreGuiInset = true,
	}, {
		React.createElement("Frame", {
			Position = UDim2.fromOffset(min.X, min.Y),
			Size = UDim2.fromOffset(size.X, size.Y),
			BackgroundColor3 = backgroundColor3,
			BackgroundTransparency = backgroundTransparency,
			BorderSizePixel = 0,
		}, {
			Stroke = React.createElement("UIStroke", {
				BorderStrokePosition = Enum.BorderStrokePosition.Inner,
				Color = borderColor3,
				Thickness = 1,
			}),
		})
	}) :: React.Node
end

return DragSelectionView
