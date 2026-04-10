-- Wrapper around WorldRoot::SetInsertPoint, since that function is Roblox only,
-- but we want the DraggerFramework to be forkable.

return function(insertPoint: Vector3)
	pcall(function()
		local setInsertPoint = (workspace :: any).SetInsertPoint
		setInsertPoint(workspace, insertPoint, true)
	end)
end