--[[
	Component that displays a SelectionBox with an arbitrary position and size,
	without having to create an adornee.

	Internally, StandaloneSelectionBox creates a transparent adornee with the
	correct position/size and parents it to CoreGui to prevent implementation
	details from leaking into the workspace.
]]

local DraggerFramework = script.Parent.Parent
local Packages = DraggerFramework.Parent

local React = require(Packages.React)
local ReactRoblox = require(Packages.ReactRoblox)

export type Props = {
	CFrame: CFrame,
	Size: Vector3,
	Color: Color3,
	LineThickness: number,
	Container: Instance?, -- Optional parent for the internal dummy part. Defaults to CoreGui.
}

local function StandaloneSelectionBox(props: Props)
	local ones = Vector3.new(1, 1, 1)
	local dummyPartSize = props.Size:Min(ones)
	local dummyPartOffset = props.Size / 2 - dummyPartSize / 2
	
	local container = props.Container or game:GetService("CoreGui")
	local dummyPartRef = React.useRef(nil :: Model?)
	
	return ReactRoblox.createPortal({
		DummyModel = React.createElement("Model", {
			ref = dummyPartRef,
		}, {
			DummyPart1 = React.createElement("Part", {
				Shape = Enum.PartType.Block,
				Anchored = true,
				CanCollide = false,
				CFrame = props.CFrame * CFrame.new(-dummyPartOffset),
				Size = dummyPartSize,
				Transparency = 0,
			}),

			DummyPart2 = React.createElement("Part", {
				Shape = Enum.PartType.Block,
				Anchored = true,
				CanCollide = false,
				CFrame = props.CFrame * CFrame.new(dummyPartOffset),
				Size = dummyPartSize,
				Transparency = 0,
			})
		}),

		SelectionBox = React.createElement("SelectionBox", {
			Adornee = dummyPartRef,
			Color3 = props.Color,
			LineThickness = props.LineThickness,
			SurfaceTransparency = 1,
			Transparency = 0,
		})
	}, container)
end

return StandaloneSelectionBox
