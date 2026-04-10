const PIVOT_NEAR_EDGE_THRESHOLD = 0.01

export type PivotType = 
	| "None"
	| "Center"
	| "Surface"
	| "Inside"
	| "Outside"
	| "Far"

return function(cframe: CFrame, offset: Vector3, size: Vector3): PivotType
	if offset:FuzzyEq(Vector3.zero, PIVOT_NEAR_EDGE_THRESHOLD) then
		return "Center"
	end

	local absOffset = Vector3.new(
		math.abs(offset.X),
		math.abs(offset.Y),
		math.abs(offset.Z)
	)
	
	local halfSize = size / 2
	local howFarOutside = absOffset - halfSize

	local isInside =
		howFarOutside.X < PIVOT_NEAR_EDGE_THRESHOLD and
		howFarOutside.Y < PIVOT_NEAR_EDGE_THRESHOLD and
		howFarOutside.Z < PIVOT_NEAR_EDGE_THRESHOLD

	if isInside then
		if math.abs(howFarOutside.X) < PIVOT_NEAR_EDGE_THRESHOLD or
			math.abs(howFarOutside.Y) < PIVOT_NEAR_EDGE_THRESHOLD or
			math.abs(howFarOutside.Z) < PIVOT_NEAR_EDGE_THRESHOLD then
			return "Surface"
		else
			return "Inside"
		end
	else
		local fractionOutVector = howFarOutside / size
		local fractionOut = math.max(fractionOutVector.X, fractionOutVector.Y, fractionOutVector.Z)

		if fractionOut > 1 then
			return "Far"
		else
			return "Outside"
		end
	end
end