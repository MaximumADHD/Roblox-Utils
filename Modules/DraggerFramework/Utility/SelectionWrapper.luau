--!strict

--[[
	A wrapper around a Selection object (anything with the same API the Roblox
	SelectionService has), which disambiguates selection changed events which
	were caused by something else setting the selection, vs selection changed
	events which were caused by calling :Set on the Selection object.

	Also caches the selection between changes, so that repeated calls to
	the get method do not need to check what the underlying selection is.
]]

local Utility = script.Parent
local DraggerFramework = Utility.Parent

local Root = DraggerFramework.Parent
local Signal = require(Root.Signal)

local SelectionWrapper = {}
SelectionWrapper.__index = SelectionWrapper

type Signal<T...> = Signal.Typed<T...>

type SelectionWrapper = {
	_selectionObject: any,
	_selection: {Instance},
	_isSettingSelection: boolean,
	_destroyed: boolean,
	onSelectionExternallyChanged: Signal<>,
	_selectionChangedConnection: RBXScriptConnection?,
}

type Proto = typeof(SelectionWrapper)
export type Class = setmetatable<SelectionWrapper, Proto>

local WRAPPER_COUNT = 0

function SelectionWrapper.new(selectionObject: any): Class
	local self: Class = setmetatable({
		_selectionObject = selectionObject,
		_selection = selectionObject:Get(),
		_isSettingSelection = false,
		_destroyed = false,
	}, SelectionWrapper)

	self.onSelectionExternallyChanged = Signal.new()
	self._selectionChangedConnection =
		selectionObject.SelectionChanged:Connect(function()
			self:_handleSelectionChanged()
		end)

	WRAPPER_COUNT += 1
	
	if WRAPPER_COUNT > 1 then
		warn("More than one SelectionWrapper created at once, this is probably a mistake!")
	end

	return self
end

function SelectionWrapper.get(self: Class): {Instance}
	return self._selection
end

function SelectionWrapper.set(self: Class, selection: {Instance}, hint: any)
	self._selection = selection
	self._isSettingSelection = true
	self._selectionObject:Set(selection, hint)
	self._isSettingSelection = false
end

function SelectionWrapper.destroy(self: Class)
	assert(not self._destroyed)

	if self._selectionChangedConnection then
		self._selectionChangedConnection:Disconnect()
		self._selectionChangedConnection = nil
	end
	
	WRAPPER_COUNT -= 1
	self._destroyed = true
end

function SelectionWrapper._handleSelectionChanged(self: Class)
	if not self._isSettingSelection then
		self._selection = self._selectionObject:Get()
		self.onSelectionExternallyChanged:Fire()
	end
end

function SelectionWrapper.getActiveSelectable(self: Class): Instance?
	return self._selection[#self._selection]
end

return SelectionWrapper