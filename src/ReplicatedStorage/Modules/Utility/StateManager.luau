--!nonstrict
-- StateManager.lua
local StateManager = {}
StateManager.__index = StateManager

export type StateChangeCallback = (newValue: any, oldValue: any) -> ()
export type StateValidator = (value: any) -> boolean
export type StateChangeEvent = {
    Fire: (self: any, stateName: string, newValue: any, oldValue: any) -> ()
} | BindableEvent

function StateManager.New(updateEvent: StateChangeEvent?)
    local self = setmetatable({}, StateManager)

    self._states = {}
    self._listeners = {}
    self._validators = {}
    self._updateEvent = updateEvent

    return self
end

function StateManager:DefineState(stateName: string, defaultValue: any, validator: StateValidator?)
    self._states[stateName] = defaultValue

    if validator then
        self._validators[stateName] = validator
    end

    -- Create getter/setter
    self[stateName] = defaultValue
end

function StateManager:Set(stateName: string, value: any)
    local oldValue = self._states[stateName]

    -- Validate if validator exists
    if self._validators[stateName] then
        if not self._validators[stateName](value) then
            warn(`Invalid value for state {stateName}: {value}`)
            return false
        end
    end

    -- Update state
    self._states[stateName] = value
    self[stateName] = value

    -- Fire state-specific listeners
    if self._listeners[stateName] then
        -- listeners are added via table.insert, so use ipairs for array order
        for _, listener in ipairs(self._listeners[stateName]) do
            task.spawn(listener, value, oldValue)
        end
    end

    -- Fire general update event if provided
    if self._updateEvent then
        self._updateEvent:Fire(stateName, value, oldValue)
    end

    return true
end

function StateManager:Get(stateName: string)
    return self._states[stateName]
end

-- Check if a state has been defined (API parity with server StateManager)
function StateManager:Has(stateName: string): boolean
    return self._states[stateName] ~= nil
end

function StateManager:OnStateChange(stateName: string, callback: StateChangeCallback)
    if not self._listeners[stateName] then
        self._listeners[stateName] = {}
    end

    table.insert(self._listeners[stateName], callback)

    -- Return disconnect function
    return function()
        local index = table.find(self._listeners[stateName], callback)
        if index then
            table.remove(self._listeners[stateName], index)
        end
    end
end

-- Get all current states
function StateManager:GetAllStates(): {[string]: any}
    local copy = {}
    for key, value in pairs(self._states) do
        copy[key] = value
    end
    return copy
end

-- Batch update multiple states
function StateManager:SetMultiple(updates: {[string]: any})
    for stateName, value in pairs(updates) do
        self:Set(stateName, value)
    end
end

return StateManager