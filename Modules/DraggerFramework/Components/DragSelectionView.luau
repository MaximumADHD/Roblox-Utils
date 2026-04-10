--[[
	Component that displays a rubber band-style selection frame.
]]

local GuiService = game:GetService("GuiService")

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

local function DragSelectionView(props: Props): React.ReactElement?
	local min = props.DragStartLocation
	local max = props.DragEndLocation

	if not min or not max then
		return nil
	end

	-- Adjust by GUI inset
	local topInset = GuiService:GetGuiInset()
	local rect = Rect.new(min - topInset, max - topInset)

	local backgroundColor3 = props.BackgroundColor3 or Colors.BLACK
	local backgroundTransparency = props.BackgroundTransparency or 1
	local borderColor3 = props.BorderColor3 or Colors.GRAY

	return React.createElement("ScreenGui", {}, {
		React.createElement("Frame", {
			Position = UDim2.new(0, rect.Min.X, 0, rect.Min.Y),
			Size = UDim2.new(0, rect.Width, 0, rect.Height),
			BackgroundColor3 = backgroundColor3,
			BackgroundTransparency = backgroundTransparency,
			BorderSizePixel = 0,
		}, {
			Left = React.createElement("Frame", {
				Size = UDim2.new(0, 1, 1, 0),
				BackgroundColor3 = borderColor3,
				BorderSizePixel = 0,
			}),

			Top = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = borderColor3,
				BorderSizePixel = 0,
			}),

			Right = React.createElement("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.new(0, 1, 1, 0),
				BackgroundColor3 = borderColor3,
				BorderSizePixel = 0,
			}),

			Bottom = React.createElement("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, 0),
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = borderColor3,
				BorderSizePixel = 0,
			}),
		})
	})
end

return DragSelectionView
