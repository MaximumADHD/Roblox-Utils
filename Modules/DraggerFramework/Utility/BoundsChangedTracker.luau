
--[[
	BoundsChangedTracker object

	Watches a set of parts for cframe and size changes.
]]

local Utility = script.Parent
local SelectionInfo = require(Utility.SelectionInfo)

local DraggerFramework = Utility.Parent
local Implementation = DraggerFramework.Implementation
local DraggerContext = require(Implementation.DraggerContext)

local MAX_PARTS_TO_TRACK_BOUNDS_FOR = 1024

local BoundsChangedTracker = {}
BoundsChangedTracker.__index = BoundsChangedTracker

type Entry = {
	CFrameChangedSignal: RBXScriptSignal,
	CFrameChangedConnection: RBXScriptConnection?,

	RootCFrameChangedSignal: RBXScriptSignal?,
	RootCFrameChangedConnection: RBXScriptConnection?,

	SizeChangedSignal: RBXScriptSignal,
	SizeChangedConnection: RBXScriptConnection?,

	Trampoline: () -> (),
}

type DraggerContext = DraggerContext.Class
type SelectionInfo = SelectionInfo.Class

export type Class = setmetatable<{
	_handler: (PVInstance | Attachment) -> (),
	_installed: boolean,
	_partToEntry: { [BasePart]: Entry },
	_attachmentToEntry: { [Attachment]: Entry },
	_basisObject: (PVInstance | Attachment)?,
	_basisPivotChangedSignal: RBXScriptSignal?,
	_basisPivotChangedConnection: RBXScriptConnection?,
	_basisPivotChangedTrampoline: () -> (),
}, typeof(BoundsChangedTracker)>

function BoundsChangedTracker.new(draggerContext: DraggerContext, handler: (PVInstance | Attachment) -> ()): Class
	local self = setmetatable({
		_handler = handler,
		_installed = false,
		_partToEntry = {},
		_attachmentToEntry = {},
		_basisObject = nil :: (PVInstance | Attachment)?,
	}, BoundsChangedTracker)

	self._basisPivotChangedTrampoline = function()
		if self._basisObject then
			handler(self._basisObject)
		end
	end

	return self :: Class
end

local function hookUpConnections(entry: Entry)
	entry.CFrameChangedConnection = entry.CFrameChangedSignal:Connect(entry.Trampoline)

	if entry.RootCFrameChangedSignal then
		entry.RootCFrameChangedConnection = entry.RootCFrameChangedSignal:Connect(entry.Trampoline)
	end

	entry.SizeChangedConnection = entry.SizeChangedSignal:Connect(entry.Trampoline)
end

local function disconnectConnections(entry: Entry)
	if entry.CFrameChangedConnection then
		entry.CFrameChangedConnection:Disconnect()
		entry.CFrameChangedConnection = nil
	end

	if entry.RootCFrameChangedConnection then
		entry.RootCFrameChangedConnection:Disconnect()
		entry.RootCFrameChangedConnection = nil
	end

	if entry.SizeChangedConnection then
		entry.SizeChangedConnection:Disconnect()
		entry.SizeChangedConnection = nil
	end
end

local function hookUpAttachmentConnections(entry: Entry)
	entry.CFrameChangedConnection = entry.CFrameChangedSignal:Connect(entry.Trampoline)
end

local function disconnectAttachmentConnections(entry: Entry)
	if entry.CFrameChangedConnection then
		entry.CFrameChangedConnection:Disconnect()
		entry.CFrameChangedConnection = nil
	end
end

function BoundsChangedTracker._hookupBasisConnection(self: Class)
	if self._basisPivotChangedSignal then
		self._basisPivotChangedConnection = self._basisPivotChangedSignal:Connect(self._basisPivotChangedTrampoline)
	end
end

function BoundsChangedTracker._disconnectBasisConnection(self: Class)
	if self._basisPivotChangedConnection then
		self._basisPivotChangedConnection:Disconnect()
		self._basisPivotChangedConnection = nil
	end
end

function BoundsChangedTracker.install(self: Class)
	if self._installed then
		return false
	end
	
	self._installed = true

	for _, entry in pairs(self._partToEntry) do
		hookUpConnections(entry)
	end
	
	for _, entry in pairs(self._attachmentToEntry) do
		hookUpAttachmentConnections(entry)
	end
	
	if self._basisObject then
		self:_hookupBasisConnection()
	end

	return true
end

function BoundsChangedTracker.uninstall(self: Class)
	if not self._installed then
		return false
	end

	self._installed = false

	for _, entry in pairs(self._partToEntry) do
		disconnectConnections(entry)
	end

	for _, entry in pairs(self._attachmentToEntry) do
		disconnectAttachmentConnections(entry)
	end
	
	if self._basisObject then
		self:_disconnectBasisConnection()
	end

	return true
end

-- Public access for the AlignmentTool, which borrows this class
function BoundsChangedTracker.setParts(self: Class, parts: { BasePart })
	self:_setParts(parts)
end

function BoundsChangedTracker._setBasisObject(self: Class, object: PVInstance?)
	if self._basisObject ~= object then
		if self._installed and self._basisObject then
			self:_disconnectBasisConnection()
		end

		self._basisObject = object

		if object then
			if object:IsA("BasePart") then
				self._basisPivotChangedSignal = object:GetPropertyChangedSignal("PivotOffset")
			elseif object:IsA("Model") then
				if object.PrimaryPart then
					self._basisPivotChangedSignal = object.PrimaryPart:GetPropertyChangedSignal("PivotOffset")
				else
					self._basisPivotChangedSignal = object:GetPropertyChangedSignal("WorldPivot")
				end
			else
				self._basisPivotChangedSignal = nil
			end

			if self._installed then
				self:_hookupBasisConnection()
			end
		end
	end
end

function BoundsChangedTracker._setAttachments(self: Class, attachments: { Attachment })
	local attachmentToNewEntry = {} :: {
		[Attachment]: Entry
	}

	for _, attachment in ipairs(attachments) do
		local entry = self._attachmentToEntry[attachment]
		self._attachmentToEntry[attachment] = nil

		if not entry then
			entry = {
				CFrameChangedSignal = attachment:GetPropertyChangedSignal("CFrame"),
				Trampoline = function()
					self._handler(attachment)
				end,
			}
			
			if self._installed then
				hookUpAttachmentConnections(entry :: Entry)
			end
		end
		
		attachmentToNewEntry[attachment] = entry :: Entry
	end

	if self._installed then
		for attachment, entry in pairs(self._attachmentToEntry) do
			if not attachmentToNewEntry[attachment] then
				disconnectAttachmentConnections(entry)
			end
		end
	end
	
	self._attachmentToEntry = attachmentToNewEntry
end

function BoundsChangedTracker._setParts(self: Class, parts: { BasePart })
	local newPartToEntry = {}

	for index, part in ipairs(parts) do
		if index > MAX_PARTS_TO_TRACK_BOUNDS_FOR then
			-- Too expensive to handle bounds changes for more than ~1000 parts,
			-- so only handle the first 1024 parts for large selections. This
			-- only effects the visible behavior of the tool in very uncommon
			-- scenarios. E.g., if you move an object, select a large multiple
			-- selection containing that object and at least 1024 other parts,
			-- and press undo.
			break
		end

		local entry = self._partToEntry[part]
		self._partToEntry[part] = nil

		if not entry then
			local rootPart = part.AssemblyRootPart
			local rootCFrameChangedSignal

			if rootPart and rootPart ~= part then
				rootCFrameChangedSignal = rootPart:GetPropertyChangedSignal("CFrame")
			end

			entry = {
				CFrameChangedSignal = part:GetPropertyChangedSignal("CFrame"),
				RootCFrameChangedSignal = rootCFrameChangedSignal,
				SizeChangedSignal = part:GetPropertyChangedSignal("Size"),

				Trampoline = function()
					self._handler(part)
				end,
			}

			if self._installed then
				hookUpConnections(entry :: Entry)
			end
		end

		assert(not newPartToEntry[part]) -- Selection should not have duplicates
		newPartToEntry[part] = entry :: Entry
	end

	if self._installed then
		for part, entry in pairs(self._partToEntry) do
			if not newPartToEntry[part] then
				disconnectConnections(entry)
			end
		end
	end

	self._partToEntry = newPartToEntry
end

function BoundsChangedTracker.setSelection(self: Class, selectionInfo: SelectionInfo)
	self:_setAttachments(selectionInfo:getAllAttachments())
	self:_setParts(selectionInfo:getObjectsToTransform())
	self:_setBasisObject(selectionInfo:getBasisObject())
end

return BoundsChangedTracker
