--!strict
-- StateManager.lua
local StateManager = {}
StateManager.__index = StateManager

export type StateValue = string | number | boolean | {[any]: any}
export type StateChangeCallback = (newValue: StateValue, oldValue: StateValue) -> ()
export type StateValidator = (value: StateValue) -> boolean

export type StateManager = {
    DefineState: (self: StateManager, stateName: string, defaultValue: StateValue, validator: StateValidator?) -> (),
    Set: (self: StateManager, stateName: string, value: StateValue) -> boolean,
    Get: (self: StateManager, stateName: string) -> StateValue,
    Has: (self: StateManager, stateName: string) -> boolean,
    OnStateChange: (self: StateManager, stateName: string, callback: StateChangeCallback) -> () -> (),
    GetAllStates: (self: StateManager) -> {[string]: StateValue},
    SetMultiple: (self: StateManager, updates: {[string]: StateValue}) -> (),
}

function StateManager.New(updateEvent: BindableEvent?)
    local self = setmetatable({}, StateManager) :: any

    self._states = {} :: {[string]: StateValue}
    self._listeners = {} :: {[string]: {StateChangeCallback}}
    self._validators = {} :: {[string]: StateValidator}
    self._updateEvent = updateEvent

    return self :: StateManager
end

function StateManager:DefineState(stateName: string, defaultValue: StateValue, validator: StateValidator?)
    (self :: any)._states[stateName] = defaultValue

    if validator then
        (self :: any)._validators[stateName] = validator
    end

    -- Create getter/setter
    (self :: any)[stateName] = defaultValue
end

function StateManager:Set(stateName: string, value: StateValue): boolean
    local oldValue = (self :: any)._states[stateName]

    -- Validate if validator exists
    if (self :: any)._validators[stateName] then
        if not (self :: any)._validators[stateName](value) then
            warn(`Invalid value for state {stateName}: {value}`)
            return false
        end
    end

    -- Update state
    (self :: any)._states[stateName] = value
    ;(self :: any)[stateName] = value

    -- Fire state-specific listeners
    if (self :: any)._listeners[stateName] then
        -- listeners are added via table.insert, so use ipairs for array order
        for _, listener in ipairs((self :: any)._listeners[stateName]) do
            task.spawn(listener, value, oldValue)
        end
    end

    -- Fire general update event if provided
    if (self :: any)._updateEvent then
        (self :: any)._updateEvent:Fire(stateName, value, oldValue)
    end

    return true
end

function StateManager:Get(stateName: string): StateValue
    return (self :: any)._states[stateName]
end

-- Check if a state has been defined (API parity with server StateManager)
function StateManager:Has(stateName: string): boolean
    return (self :: any)._states[stateName] ~= nil
end

function StateManager:OnStateChange(stateName: string, callback: StateChangeCallback): () -> ()
    if not (self :: any)._listeners[stateName] then
        (self :: any)._listeners[stateName] = {}
    end

    table.insert((self :: any)._listeners[stateName], callback)

    -- Return disconnect function
    return function()
        local index = table.find((self :: any)._listeners[stateName], callback)
        if index then
            table.remove((self :: any)._listeners[stateName], index)
        end
    end
end

-- Get all current states
function StateManager:GetAllStates(): {[string]: StateValue}
    local copy: {[string]: StateValue} = {}
    for key, value in pairs((self :: any)._states) do
        copy[key] = value
    end
    return copy
end

-- Batch update multiple states
function StateManager:SetMultiple(updates: {[string]: StateValue})
    for stateName, value in pairs(updates) do
        self:Set(stateName, value)
    end
end

return StateManager