local DraggerFramework = script.Parent.Parent
local Utility = DraggerFramework.Utility

local getGeometry = require(Utility.getGeometry)
local JointPairs = require(Utility.JointPairs)
local JointUtil = require(Utility.JointUtil)

local JointMaker = {}
JointMaker.__index = JointMaker

type LengthConstraint =
	| RopeConstraint
	| RodConstraint

type Geometry = getGeometry.Geometry

type JointMaker = {
	_isSimulating: boolean?,
	_partSet: { [BasePart]: true },
	_parts: { BasePart },
	_rootPartSet: { [BasePart]: true },

	_lengthConstraintsToFixupSet: {
		[LengthConstraint]: {
			Span: number,
			Length: number
		}
	},

	_springsToFixupSet: {
		[SpringConstraint]: {
			Span: number,
			FreeLength: number
		}
	},

	_internalJointSet: { [JointInstance]: BasePart },
	_initiallyTouchingSets: { [BasePart]: { [BasePart]: true } },
	_jointsToDestroy: { JointInstance },
	_weldConstraintsToReenableSet: { [WeldConstraint]: true },
	_motor6dsToAdjustAndReenableSet: { [Motor6D]: CFrame },
	_alreadyConnectedToSets: { [BasePart]: { [BasePart]: true } },
	_geometryCache: { [BasePart]: Geometry },
	_toUnanchorSet: { [BasePart]: true }?,
}

type Proto = typeof(JointMaker)
export type Class = setmetatable<JointMaker, Proto>

function JointMaker.new(isSimulating: boolean?): Class
	local self: JointMaker = {
		_partSet = {},
		_parts = {},
		_rootPartSet = {},
		_lengthConstraintsToFixupSet = {},
		_springsToFixupSet = {},
		_internalJointSet = {},
		_initiallyTouchingSets = {},
		_jointsToDestroy = {},
		_weldConstraintsToReenableSet = {},
		_motor6dsToAdjustAndReenableSet = {},
		_alreadyConnectedToSets = {},
		_geometryCache = {},
		_isSimulating = isSimulating,
	}

	return setmetatable(self, JointMaker)
end

local function getConstraintLength(joint: Constraint)
	local a0 = joint.Attachment0
	local a1 = joint.Attachment1

	if a0 and a1 then
		return (a0.WorldPosition - a1.WorldPosition).Magnitude
	end

	return 0
end

--[[
	Set the parts to compute joints for, precomputing as much info as possible
]]
function JointMaker.pickUpParts(self: Class, parts: { BasePart })
	local partSet = {}

	for _, part in ipairs(parts) do
		partSet[part] = true
	end
	
	self._parts = parts
	self._partSet = partSet
	self._rootPartSet = {} -- Intentionally empty, only needed for IK moves

	local weldConstraintsToReenableSet = {}
	local motor6dsToAdjustAndReenableSet = {}
	local jointsToDestroy = {}
	local alreadyConnectedToSets = {}
	local initiallyTouchingSets = {}
	local internalJointSet = {}
	local springsToFixupSet = {}
	local lengthConstraintsToFixupSet = {}

	for _, part in ipairs(parts) do
		alreadyConnectedToSets[part] = {}

		for _, joint in ipairs(part:GetJoints()) do
			if joint:IsA("Constraint") then
				local other = JointUtil.getConstraintCounterpart(joint, part)

				if other then
					alreadyConnectedToSets[part][other] = true

					if joint:IsA("RopeConstraint") or
						joint:IsA("RodConstraint") then
						lengthConstraintsToFixupSet[joint] = {
							Span = getConstraintLength(joint),
							Length = joint.Length,
						}
					elseif joint:IsA("SpringConstraint") then
						springsToFixupSet[joint] = {
							Span = getConstraintLength(joint),
							FreeLength = joint.FreeLength,
						}
					end
				end
			elseif joint:IsA("JointInstance") then
				local other = JointUtil.getJointInstanceCounterpart(joint, part)
				
				if other and partSet[other] then
					internalJointSet[joint] = joint.Part1
				else
					if joint:IsA("Motor6D") then
						if other then
							joint.Enabled = false
							motor6dsToAdjustAndReenableSet[joint] = part.CFrame
							alreadyConnectedToSets[part][other] = true
						end
					else
						table.insert(jointsToDestroy, joint)
					end
				end
			elseif joint:IsA("WeldConstraint") then
				local other = JointUtil.getWeldConstraintCounterpart(joint, part)

				if other then
					joint.Enabled = false
					alreadyConnectedToSets[part][other] = true
					weldConstraintsToReenableSet[joint] = true
				end
			elseif joint:IsA("NoCollisionConstraint") then
				local other = JointUtil.getNoCollisionConstraintCounterpart(joint, part)

				if other then
					alreadyConnectedToSets[part][other] = true
				end
			end
		end

		initiallyTouchingSets[part] = {}

		for _, otherPart in ipairs(part:GetTouchingParts()) do
			initiallyTouchingSets[part][otherPart] = true
		end
	end

	self._lengthConstraintsToFixupSet = lengthConstraintsToFixupSet
	self._springsToFixupSet = springsToFixupSet
	self._internalJointSet = internalJointSet
	self._initiallyTouchingSets = initiallyTouchingSets
	self._jointsToDestroy = jointsToDestroy
	self._weldConstraintsToReenableSet = weldConstraintsToReenableSet
	self._motor6dsToAdjustAndReenableSet = motor6dsToAdjustAndReenableSet
	self._alreadyConnectedToSets = alreadyConnectedToSets
	self._geometryCache = {}
end

function JointMaker.anchorParts(self: Class)
	local toUnanchorSet = {}

	for _, part in ipairs(self._parts) do
		if not part.Anchored then
			part.Anchored = true
			toUnanchorSet[part] = true
		end
	end
	
	self._toUnanchorSet = toUnanchorSet
end

function JointMaker.restoreAnchored(self: Class)
	if self._toUnanchorSet then
		for part, _ in pairs(self._toUnanchorSet) do
			part.Anchored = false
		end
		self._toUnanchorSet = nil
	end
end

--[[
	Break existing joints to others
]]
function JointMaker.breakJointsToOutsiders(self: Class)
	for _, joint in ipairs(self._jointsToDestroy) do
		joint.Parent = nil
	end
	self._jointsToDestroy = {}
end

--[[
	Break joints between parts in the part list
]]
function JointMaker.disconnectInternalJoints(self: Class)
	for joint, _ in pairs(self._internalJointSet) do
		joint.Part1 = nil
	end
end

--[[
	Reconnect the internal joints between parts with a scale
]]
function JointMaker.reconnectInternalJointsWithScale(self: Class, scale: number)
	for joint, part1 in pairs(self._internalJointSet) do
		joint.C0 = joint.C0 + joint.C0.Position * (scale - 1)
		joint.C1 = joint.C1 + joint.C1.Position * (scale - 1)
		joint.Part1 = part1
	end
end

--[[
	Compute the candidate joint pairs for the parts at their current location.
]]
function JointMaker.computeJointPairs(self: Class)
	local jointPairs = JointPairs.new(self._parts, self._partSet, self._rootPartSet,
		CFrame.identity,
		self._alreadyConnectedToSets, function(part)
			return self:_getGeometry(part)
		end)

	if self._isSimulating then
		self._geometryCache = {}
	end

	return jointPairs
end

function JointMaker.isColliding(self: Class, includeInitiallyTouching: boolean)
	for _, part in ipairs(self._parts) do
		for _, otherPart in ipairs(part:GetTouchingParts()) do
			if not self._partSet[otherPart] then
				if includeInitiallyTouching or not self._initiallyTouchingSets[part][otherPart] then
					return true
				end
			end
		end
	end

	return false
end

function JointMaker.fixupConstraintLengths(self: Class)
	for constraint, data in pairs(self._lengthConstraintsToFixupSet) do
		local scaledBy = getConstraintLength(constraint) / data.Span
		constraint.Length = data.Length * scaledBy
	end
	for constraint, data in pairs(self._springsToFixupSet) do
		local scaledBy = getConstraintLength(constraint) / data.Span
		constraint.FreeLength = data.FreeLength * scaledBy
	end
end

function JointMaker.putDownParts(self: Class)
	for weld, _ in pairs(self._weldConstraintsToReenableSet) do
		weld.Enabled = true
	end

	for motor6d, originalCFrame in pairs(self._motor6dsToAdjustAndReenableSet) do
		local part0 = motor6d.Part0
		local part1 = motor6d.Part1

		if part0 and self._partSet[part0] then
			-- Modify C0
			motor6d.C0 = part0.CFrame:Inverse() * originalCFrame * motor6d.C0
		elseif part1 then
			-- Modify C1
			motor6d.C1 = part1.CFrame:Inverse() * originalCFrame * motor6d.C1
		end
		
		motor6d.Enabled = true
	end

	table.clear(self._motor6dsToAdjustAndReenableSet)
	table.clear(self._weldConstraintsToReenableSet)
	table.clear(self._alreadyConnectedToSets)
	table.clear(self._geometryCache)

	table.clear(self._parts)
	table.clear(self._partSet)
end

function JointMaker._getGeometry(self: Class, part: BasePart): Geometry
	if self._partSet[part] then
		-- Scaling, so our geometry might change every step
		return getGeometry(part)
	else
		local geometry = self._geometryCache[part]

		if not geometry then
			geometry = getGeometry(part)
			self._geometryCache[part] = geometry
		end
		
		return geometry
	end
end

return JointMaker