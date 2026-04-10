local NO_COLLISIONS_TRANSPARENCY = 0.4

local TemporaryTransparency = {}
TemporaryTransparency.__index = TemporaryTransparency

type TemporaryTransparency = {
	_draggingModifiedParts: { BasePart },
}

type Proto = typeof(TemporaryTransparency)
export type Class = setmetatable<TemporaryTransparency, Proto>

function TemporaryTransparency.new(parts: { BasePart }): Class
	local self = setmetatable({
		_draggingModifiedParts = {},
	}, TemporaryTransparency)

	for _, part in ipairs(parts) do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = NO_COLLISIONS_TRANSPARENCY
			table.insert(self._draggingModifiedParts, part)
		end
	end

	return self
end

function TemporaryTransparency.destroy(self: Class)
	for _, part in ipairs(self._draggingModifiedParts) do
		part.LocalTransparencyModifier = 0
	end
end

return TemporaryTransparency