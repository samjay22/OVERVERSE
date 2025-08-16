--!strict
-- CharacterStates: utilities for managing character state definitions

local Constants = require(game.ReplicatedStorage.Modules.Utility.Constants)

local CharacterStates = {}

function CharacterStates.GetDefinitions()
    return Constants.CHARACTER_STATE_DEFINITIONS or {}
end

function CharacterStates.GetDefaultValue(stateName: string)
    local definitions = CharacterStates.GetDefinitions()
    local def = definitions[stateName]
    return def and def.default or nil
end

function CharacterStates.GetValidator(stateName: string)
    local definitions = CharacterStates.GetDefinitions()
    local def = definitions[stateName]
    return def and def.validator or nil
end

function CharacterStates.ValidateValue(stateName: string, value: any): boolean
    local validator = CharacterStates.GetValidator(stateName)
    if validator then
        return validator(value)
    end
    return true -- No validator means any value is valid
end

-- Apply state definitions to a given StateManager by defining states with defaults and validators
function CharacterStates.applyTo(stateManager: any, definitions: {[string]: {default: any, validator: ((value: any) -> boolean)?}})
    definitions = definitions or CharacterStates.GetDefinitions()
    for stateName, def in pairs(definitions) do
        local defaultValue = def and def.default or nil
        local validator = def and def.validator or nil
        if stateManager and stateManager.DefineState then
            stateManager:DefineState(stateName, defaultValue, validator)
        end
    end
end

return CharacterStates
