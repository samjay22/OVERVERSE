--!strict
-- Strongly-typed State Manager with event-driven architecture

local CoreTypes = require(game.ServerStorage.Modules.Types.CoreTypes)
local EventBus = require(game.ServerStorage.Modules.Utilities.EventBus)

export type IStateManager = CoreTypes.IStateManager
export type StateValue = CoreTypes.StateValue
export type StateChangeCallback = CoreTypes.StateChangeCallback

local StateManager = {}
StateManager.__index = StateManager

function StateManager.New(): IStateManager
	local self = setmetatable({}, StateManager)
	
	self._states = {} :: {[string]: StateValue}
	self._eventBus = EventBus.New()
	self._changeListeners = {} :: {[string]: {StateChangeCallback}}
	
	return (self :: any) :: IStateManager
end

function StateManager:Get(key: string): StateValue
	return self._states[key]
end

function StateManager:Set(key: string, value: StateValue): ()
	local oldValue = self._states[key]
	
	-- Don't trigger events if value hasn't changed
	if oldValue == value then
		return
	end
	
	self._states[key] = value
	
	-- Trigger change event
	local event = self._eventBus:Get(`StateChanged_{key}`)
	event:Fire(value, oldValue)
	
	-- Trigger generic state change event with state data
	local genericEvent = self._eventBus:Get("StateChanged")
	genericEvent:Fire({key = key, newValue = value, oldValue = oldValue})
	
	-- Call registered callbacks in a batch to reduce overhead
	local listeners = self._changeListeners[key]
	if listeners then
		-- Use a single task.spawn for all callbacks to reduce thread overhead
		if #listeners > 0 then
			task.spawn(function()
				for _, callback in ipairs(listeners) do
					local success, err = pcall(callback, value, oldValue)
					if not success then
						warn(`StateManager callback failed: {err}`)
					end
				end
			end)
		end
	end
end

function StateManager:SetMultiple(states: {[string]: StateValue}): ()
	local changes = {}
	
	-- Collect all changes
	for key, value in pairs(states) do
		local oldValue = self._states[key]
		if oldValue ~= value then
			changes[key] = {old = oldValue, new = value}
			self._states[key] = value
		end
	end
	
	-- Fire events for all changes
	for key, change in pairs(changes) do
		local event = self._eventBus:Get(`StateChanged_{key}`)
		event:Fire(change.new, change.old)
		
		-- Call registered callbacks in batch
		local listeners = self._changeListeners[key]
		if listeners and #listeners > 0 then
			task.spawn(function()
				for _, callback in ipairs(listeners) do
					local success, err = pcall(callback, change.new, change.old)
					if not success then
						warn(`StateManager batch callback failed: {err}`)
					end
				end
			end)
		end
	end
	
	-- Fire batch change event if there were changes
	if next(changes) then
		local batchEvent = self._eventBus:Get("StateChangedBatch")
		batchEvent:Fire(changes)
	end
end

function StateManager:GetAll(): {[string]: StateValue}
	return table.clone(self._states)
end

function StateManager:OnChange(key: string, callback: StateChangeCallback): RBXScriptConnection
	-- Store callback for direct calling
	if not self._changeListeners[key] then
		self._changeListeners[key] = {}
	end
	table.insert(self._changeListeners[key], callback)
	
	-- Return connection to event bus for easy disconnection
	local event = self._eventBus:Get(`StateChanged_{key}`)
	return event:Connect(callback)
end

function StateManager:RemoveChangeListener(key: string, connection: RBXScriptConnection): ()
	connection:Disconnect()
	
	-- Clean up callback list
	local listeners = self._changeListeners[key]
	if listeners then
		-- Note: We can't easily remove specific callbacks without tracking connections
		-- This is a limitation of the current design
	end
end

function StateManager:Clear(): ()
	local oldStates = table.clone(self._states)
	table.clear(self._states)
	
	-- Fire clear event
	local clearEvent = self._eventBus:Get("StateCleared")
	clearEvent:Fire(oldStates)
	
	-- Fire individual change events for cleared states
	for key, oldValue in pairs(oldStates) do
		local event = self._eventBus:Get(`StateChanged_{key}`) :: any
		event:Fire(nil, oldValue)
		
		-- Call registered callbacks
		local listeners = self._changeListeners[key]
		if listeners then
			for _, callback in ipairs(listeners) do
				task.spawn(callback, nil, oldValue)
			end
		end
	end
end

function StateManager:Has(key: string): boolean
	return self._states[key] ~= nil
end

-- Additional utility methods
function StateManager:GetKeys(): {string}
	local keys = {}
	for key in pairs(self._states) do
		table.insert(keys, key)
	end
	return keys
end

function StateManager:GetStateCount(): number
	local count = 0
	for _ in pairs(self._states) do
		count += 1
	end
	return count
end

function StateManager:Subscribe(eventName: string, callback: (...any) -> ()): RBXScriptConnection
	local event = self._eventBus:Get(eventName)
	return event:Connect(callback)
end

function StateManager:Increment(key: string, amount: number?): StateValue
	local current = self._states[key]
	local increment = amount or 1
	
	if typeof(current) == "number" then
		local newValue = current + increment
		self:Set(key, newValue)
		return newValue
	else
		warn(`StateManager: Cannot increment non-number state '{key}' (current type: {typeof(current)})`)
		return current
	end
end

function StateManager:Decrement(key: string, amount: number?): StateValue
	local current = self._states[key]
	local decrement = amount or 1
	
	if typeof(current) == "number" then
		local newValue = current - decrement
		self:Set(key, newValue)
		return newValue
	else
		warn(`StateManager: Cannot decrement non-number state '{key}' (current type: {typeof(current)})`)
		return current
	end
end

function StateManager:Toggle(key: string): StateValue
	local current = self._states[key]
	
	if typeof(current) == "boolean" then
		local newValue = not current
		self:Set(key, newValue)
		return newValue
	else
		warn(`StateManager: Cannot toggle non-boolean state '{key}' (current type: {typeof(current)})`)
		return current
	end
end

function StateManager:Destroy(): ()
	self._eventBus:Destroy()
	table.clear(self._states)
	table.clear(self._changeListeners)
end

return StateManager
