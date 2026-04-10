local DraggerFramework = script.Parent.Parent
local Implementation = DraggerFramework.Implementation
local DraggerContext = require(Implementation.DraggerContext)

local Packages = DraggerFramework.Parent
local ReactRoblox = require(Packages.ReactRoblox)
local React = require(Packages.React)

-- How much space between the note and the window edge
local EDGE_PADDING = 2

local FRAME_PADDING = 3
local TEXT_MARGIN = 2

type PaddingProps = {
	Padding: number,
}

export type Props = {
	DraggerContext: DraggerContext.Class,
	InView: boolean,
}

type Node = React.Node

local function SimplePadding(props: PaddingProps): Node
	local padding = React.useMemo(function()
		return UDim.new(0, props.Padding)
	end, { props.Padding :: any })

	return React.createElement("UIPadding", {
		PaddingBottom = padding,
		PaddingRight = padding,
		PaddingLeft = padding,
		PaddingTop = padding,
	}) :: Node
end

local function SummonHandlesNote(props: Props)
	if props.InView then
		return nil
	end

	local viewportSize = props.DraggerContext:getViewportSize()
	local background = props.DraggerContext:getThemeColor(Enum.StudioStyleGuideColor.Tooltip)
	local border = props.DraggerContext:getThemeColor(Enum.StudioStyleGuideColor.Border)
	local foreground = props.DraggerContext:getThemeColor(Enum.StudioStyleGuideColor.MainText)
	local tabBubble = props.DraggerContext:getThemeColor(Enum.StudioStyleGuideColor.DimmedText)
	local guiParent = props.DraggerContext:getGuiParent()

	return ReactRoblox.createPortal({
		SummonHandlesNoteGui = React.createElement("ScreenGui", {}, {
			Frame = React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundColor3 = background,
				BorderColor3 = border,
				Position = UDim2.new(0, viewportSize.X / 2, 0, EDGE_PADDING),
			}, {
				Padding = React.createElement(SimplePadding, {
					Padding = FRAME_PADDING
				}),
				
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, FRAME_PADDING),
				}),
				Tab = React.createElement("TextLabel", {
					Text = props.DraggerContext:getText("SummonPivot", "TabText"),
					TextColor3 = foreground,
					BackgroundColor3 = tabBubble,
					AutomaticSize = Enum.AutomaticSize.XY,
					LayoutOrder = 1,
				}, {
					Padding = React.createElement(SimplePadding, {
						Padding = TEXT_MARGIN
					}),

					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 4),
					}),
				}),
				Text = React.createElement("TextLabel", {
					Text = props.DraggerContext:getText("SummonPivot", "SummonText"),
					TextColor3 = foreground,
					AutomaticSize = Enum.AutomaticSize.XY,
					BackgroundTransparency = 1,
					LayoutOrder = 2,
				}, {
					Padding = React.createElement(SimplePadding, {
						Padding = TEXT_MARGIN
					}),
				})
			})
		})
	}, guiParent)
end

return SummonHandlesNote