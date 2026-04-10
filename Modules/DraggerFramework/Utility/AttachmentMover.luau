local RunService = game:GetService("RunService")

local AttachmentMover = {}
AttachmentMover.__index = AttachmentMover

type AttachmentMover = {
	_originalWorldCFrames: {
		[Attachment]: CFrame,
	},

	_partsToUnanchor: {
		[BasePart]: true,
	},
}

type Proto = typeof(AttachmentMover)
export type Class = setmetatable<AttachmentMover, Proto>

function AttachmentMover.new(): Class
	return setmetatable({
		_originalWorldCFrames = {},
		_partsToUnanchor = {},
	}, AttachmentMover)
end

function AttachmentMover.setDragged(self: Class, attachments: { Attachment })
	local isRunning = RunService:IsRunning()
	table.clear(self._originalWorldCFrames)
	table.clear(self._partsToUnanchor)
	
	for _, attachment in ipairs(attachments) do
		self._originalWorldCFrames[attachment] = attachment.WorldCFrame

		if isRunning then
			local part = attachment:FindFirstAncestorWhichIsA("BasePart")

			if part and not part:IsGrounded() then
				self._partsToUnanchor[part] = true
			end
		end
	end

	for part in self._partsToUnanchor do
		part.Anchored = true
	end
end

function AttachmentMover.transformTo(self: Class, transform: CFrame)
	for attachment, originalWorldCFrame in pairs(self._originalWorldCFrames) do
		attachment.WorldCFrame = transform * originalWorldCFrame
	end
end

function AttachmentMover.commit(self: Class)
	table.clear(self._originalWorldCFrames)

	for part in self._partsToUnanchor do
		part.Anchored = false
	end

	table.clear(self._partsToUnanchor)
end

return AttachmentMover