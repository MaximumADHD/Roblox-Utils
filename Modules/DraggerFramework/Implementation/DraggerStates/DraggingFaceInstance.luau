--[[
	When dragging over a Part, DraggingFaceInstance parents the instance onto
	the part and sets the instance's "Face" property to the closest Surface.
]]

--!nonstrict
local Implementation = script.Parent.Parent
local DraggerToolModel = require(Implementation.DraggerToolModel)

local DraggerFramework = Implementation.Parent
local Utility = DraggerFramework.Utility

local DragHelper = require(Utility.DragHelper)
local StandardCursor = require(Utility.StandardCursor)

type DraggerToolModel = DraggerToolModel.Class

local SURFACE_TO_FACE = {
	["TopSurface"] = "Top",
	["BottomSurface"] = "Bottom",
	["LeftSurface"] = "Left",
	["RightSurface"] = "Right",
	["FrontSurface"] = "Front",
	["BackSurface"] = "Back",
}

local DraggingFaceInstance = {}
DraggingFaceInstance.__index = DraggingFaceInstance

type DraggingFaceInstance = {
	_draggerToolModel: DraggerToolModel,
	_connectionToBreak: RBXScriptConnection?,
}

type Proto = typeof(DraggingFaceInstance)
export type Class = setmetatable<DraggingFaceInstance, Proto>

function DraggingFaceInstance.new(draggerToolModel: DraggerToolModel, connectionToBreak: RBXScriptConnection?): Class
	local self = setmetatable({
		_draggerToolModel = draggerToolModel,
		_connectionToBreak = connectionToBreak,
	}, DraggingFaceInstance)

	return self
end

function DraggingFaceInstance:enter()
	self._draggerToolModel:setMouseCursor(StandardCursor.getClosedHand())
end

function DraggingFaceInstance:leave()
	self._draggerToolModel._draggerSchema.addUndoWaypoint(self._draggerToolModel._draggerContext, "Drag Face Instance")

	if self._connectionToBreak then
		self._connectionToBreak:Disconnect()
	end
end

function DraggingFaceInstance.render(self: Class)
end

function DraggingFaceInstance.processSelectionChanged(self: Class)
	self:_endDrag()
end

function DraggingFaceInstance.processMouseDown(self: Class)
end

function DraggingFaceInstance.processViewChanged(self: Class)
	local part, surface = DragHelper.getPartAndSurface(self._draggerToolModel._draggerContext:getMouseRay())
	local configurableFaces = self._draggerToolModel._selectionInfo.instancesWithConfigurableFace

	if configurableFaces then
		for _, instance: FaceInstance in configurableFaces do
			if part and surface then
				instance.Parent = part
				instance.Face = SURFACE_TO_FACE[surface]
			end
		end
	end
end

function DraggingFaceInstance.processMouseUp(self: Class)
	self:_endDrag()
end

function DraggingFaceInstance.processKeyDown(self: Class, keyCode: Enum.KeyCode)
end

function DraggingFaceInstance.processKeyUp(self: Class, keyCode: Enum.KeyCode)
end

function DraggingFaceInstance._endDrag(self: Class)
	self._draggerToolModel:transitionToState("Ready")
end

return DraggingFaceInstance