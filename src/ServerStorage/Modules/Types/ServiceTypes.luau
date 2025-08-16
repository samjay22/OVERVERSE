--!nonstrict
local Types = {}

export type ServiceCallback = (...any) -> ()
export type StateManager = {
    Get: (self: StateManager, state: string) -> any,
    Set: (self: StateManager, state: string, value: any) -> (),
    SetMultiple: (self: StateManager, states: { [string]: any }) -> (),
    GetAllStates: (self: StateManager) -> { [string]: any },
    OnStateChange: (self: StateManager, state: string, callback: (new: any, old: any) -> ()) -> ()
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

return Types
