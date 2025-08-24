--!strict
-- Types for character state values with strong typing

export type CharacterStateValue = string | number | boolean | {[any]: any}

-- Specific typed state getters for type safety
export type TypedStateManager = {
    -- Core stats (numbers)
    GetHealth: (self: TypedStateManager) -> number,
    GetMaxHealth: (self: TypedStateManager) -> number,
    GetStamina: (self: TypedStateManager) -> number,
    GetMaxStamina: (self: TypedStateManager) -> number,
    GetGuard: (self: TypedStateManager) -> number,
    GetMaxGuard: (self: TypedStateManager) -> number,
    
    -- Modifiers (numbers)
    GetOutgoingDamageMult: (self: TypedStateManager) -> number,
    GetIncomingDamageMult: (self: TypedStateManager) -> number,
    GetStaminaCostMult: (self: TypedStateManager) -> number,
    GetAttackCooldownMult: (self: TypedStateManager) -> number,
    GetGuardRegenMult: (self: TypedStateManager) -> number,
    GetStaminaRegenBonus: (self: TypedStateManager) -> number,
    GetCritChance: (self: TypedStateManager) -> number,
    GetCritDamage: (self: TypedStateManager) -> number,
    
    -- Boolean states
    GetIsDead: (self: TypedStateManager) -> boolean,
    GetIsRunning: (self: TypedStateManager) -> boolean,
    GetIsBlocking: (self: TypedStateManager) -> boolean,
    GetIsStunned: (self: TypedStateManager) -> boolean,
    GetIsDashing: (self: TypedStateManager) -> boolean,
    
    -- Generic state access
    Get: (self: TypedStateManager, key: string) -> CharacterStateValue,
    Set: (self: TypedStateManager, key: string, value: CharacterStateValue) -> (),
    SetMultiple: (self: TypedStateManager, states: {[string]: CharacterStateValue}) -> (),
    OnStateChange: (self: TypedStateManager, key: string, callback: (newValue: CharacterStateValue, oldValue: CharacterStateValue) -> ()) -> () -> (),
}

-- Helper functions to safely cast state values
local StateHelpers = {}

function StateHelpers.asNumber(value: CharacterStateValue, default: number?): number
    if type(value) == "number" then
        return value
    end
    return default or 0
end

function StateHelpers.asBoolean(value: CharacterStateValue, default: boolean?): boolean
    if type(value) == "boolean" then
        return value
    end
    return default or false
end

function StateHelpers.asString(value: CharacterStateValue, default: string?): string
    if type(value) == "string" then
        return value
    end
    return default or ""
end

export type StateHelpers = typeof(StateHelpers)

return StateHelpers
