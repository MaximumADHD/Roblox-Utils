local StateType = {
	Ready = "Ready",
	PendingDraggingParts = "PendingDraggingParts",
	PendingSelectNext = "PendingSelectNext",
	DraggingHandle = "DraggingHandle",
	DraggingParts = "DraggingParts",
	DragSelecting = "DragSelecting",
	DraggingFaceInstance = "DraggingFaceInstance",
}

export type StateType = keyof<typeof(StateType)> | string

setmetatable(StateType, {
	__index = function(self, index)
		error("Attempt to get invalid StateType `"..tostring(index).."`")
	end,
})

return table.freeze(StateType)