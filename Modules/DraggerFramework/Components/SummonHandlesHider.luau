local DraggerFramework = script.Parent.Parent
local Implementation = DraggerFramework.Implementation
local DraggerContext = require(Implementation.DraggerContext)

local Packages = DraggerFramework.Parent
local React = require(Packages.React)

local SummonHandlesHider = {}

-- When the user has summoned the handles for at duration, the hint that they
-- can be summoned will permanently become hidden. We do it this way so that if
-- you just slightly tap the tab key you won't lose the hint, you actually have
-- to hold it down.
local sTotalSummonHintTime = 2

-- Was the hint hidden in a previous session?
local SETTING_NAME = "CoreDraggersSummonHintHidden"
local sWasPreviouslyHidden = nil :: boolean?

type DraggerContext = DraggerContext.Class

type Props = {
	DraggerContext: DraggerContext,
}

function SummonHandlesHider.render(props: Props)
	React.useEffect(function ()
		local startTime = os.clock()

		return function ()
			local duration = os.clock() - startTime
			sTotalSummonHintTime -= duration

			if sWasPreviouslyHidden == nil then
				sWasPreviouslyHidden = props.DraggerContext:getSetting(SETTING_NAME)
			end

			if sTotalSummonHintTime <= 0 and not sWasPreviouslyHidden then
				props.DraggerContext:setSetting(SETTING_NAME, true)
				sWasPreviouslyHidden = true
			end
		end
	end, {})
end

function SummonHandlesHider.hasSeenEnough(draggerContext: DraggerContext)
	if sWasPreviouslyHidden == nil then
		sWasPreviouslyHidden = draggerContext:getSetting(SETTING_NAME)
	end

	return sWasPreviouslyHidden or sTotalSummonHintTime <= 0
end

return SummonHandlesHider