local DraggerFramework = script.Parent.Parent
local Packages = DraggerFramework.Parent
local React = require(Packages.React)

local Implementation = DraggerFramework.Implementation
local DraggerContext = require(Implementation.DraggerContext)

local MAIN_SPHERE_RADIUS = 0.4
local MAIN_SPHERE_TRANSPARENCY = 0.5

type DraggerContext = DraggerContext.Class

type Props = {
	CFrame: CFrame,
	IsActive: boolean,
	DraggerContext: DraggerContext,
}

return function(props: Props)
	local handleScale: number = props.DraggerContext:getHandleScale(props.CFrame.Position)

	return React.createElement("SphereHandleAdornment", {
		Adornee = workspace.Terrain,
		CFrame = props.CFrame,
		Radius = handleScale * MAIN_SPHERE_RADIUS,
		ZIndex = 0,
		AlwaysOnTop = false,
		Transparency = MAIN_SPHERE_TRANSPARENCY,
		Color3 = props.DraggerContext:getSelectionBoxColor(props.IsActive),
	})
end