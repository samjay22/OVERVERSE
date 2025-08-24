--!strict

local CoreTypes = require(game.ServerStorage.Modules.Types.CoreTypes)

export type ServiceCallback = (...any) -> ()

export type StateValue = CoreTypes.StateValue
export type StateChangeCallback = CoreTypes.StateChangeCallback

export type StateManager = {
    Get: (self: StateManager, state: string) -> StateValue,
    Set: (self: StateManager, state: string, value: StateValue) -> (),
    SetMultiple: (self: StateManager, states: { [string]: StateValue }) -> (),
    GetAllStates: (self: StateManager) -> { [string]: StateValue },
    OnStateChange: (self: StateManager, state: string, callback: StateChangeCallback) -> ()
}

export type ResourceHandlers = {
    onStaminaChange: ServiceCallback,
    onGuardChange: ServiceCallback
}

export type HealthHandlers = {
    onDamage: (damage: number) -> (),
    onDeath: () -> ()
}

export type CharacterInstance = {
    PlayerId: number,
    Model: Model,
    Humanoid: Humanoid,
    StateManager: StateManager
}

return {}
