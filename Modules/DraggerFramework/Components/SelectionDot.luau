--[[
	Component that displays a dot of fixed size at the given position.
	Intended to be used to show the center of the current selection.
]]
local DraggerFramework = script.Parent.Parent
local Packages = DraggerFramework.Parent

local React = require(Packages.React)
local Colors = require(DraggerFramework.Utility.Colors)

export type Props = {
	Position: Vector3?,
	Size: number?,

	BackgroundColor3: Color3?,
	BorderColor3: Color3?,
}

local function SelectionDot(props: Props): React.ReactElement?
	local screenPosition, onScreen = workspace.CurrentCamera:WorldToScreenPoint(props.Position or Vector3.zero)

	if not onScreen then
		return nil
	end

	local size = props.Size or 3

	return React.createElement("ScreenGui", {}, {
		React.createElement("Frame", {
			BackgroundColor3 = props.BackgroundColor3 or Colors.WHITE,
			BorderColor3 = props.BorderColor3 or Colors.BLACK,
			BorderSizePixel = 1,
			Position = UDim2.fromOffset(screenPosition.X, screenPosition.Y),
			Selectable = false,
			Size = UDim2.fromOffset(size, size),
		})
	})
end

return SelectionDot
