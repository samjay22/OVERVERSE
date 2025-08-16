--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateManager = require(ReplicatedStorage.Modules.Utility.StateManager)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

export type CharacterSignals = {
    OnSpawn : BindableEvent,
    OnDeath : BindableEvent,
    OnDamage : BindableEvent,
    OnAttack : BindableEvent,
    OnUpdate : BindableEvent,
    OnStaminaChange : BindableEvent,
    OnGuardChange : BindableEvent,
    OnStateChange : BindableEvent,
    OnCleanup : BindableEvent,
}

export type Character = {
	PlayerId : number,
	Player : Player,
	Humanoid : Humanoid,
    WeaponSheath : BasePart?,

	OnSpawn : BindableEvent,
	OnDeath : BindableEvent,
	OnDamage : BindableEvent,
	OnAttack : BindableEvent,
	OnUpdate : BindableEvent,
	OnStaminaChange : BindableEvent,
	OnGuardChange : BindableEvent,
    OnStateChange : BindableEvent,
    OnCleanup : BindableEvent,

    Signals: CharacterSignals,
}

export type internalCharacter = Character & {
    _connections: {RBXScriptConnection},
    _cleanupTasks: {() -> ()},
    _lastUpdate: number,

    StateManager: typeof(StateManager.New()),
    Components: {[string]: any},

    Animations : {
        Idle : Animation?,
        Primary : Animation?,
        Secondary : Animation?,
        Walk : Animation?
    } & Instance
}

export type CharacterConfig = {
    MaxHealth: number?,
    MaxStamina: number?,
    MaxGuard: number?,
    WalkSpeed: number?,
    RunSpeed: number?,
    RespawnTime: number?,
    AbilityLoadout: AbilityTypes.Loadout?,
}

export type ComponentInterface = {
    Initialize: (Character, any?) -> (),
    Update: (Character, number) -> ()?,
    Cleanup: (Character) -> ()?
}

return 0