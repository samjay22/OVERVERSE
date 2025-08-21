--!strict

local StateManager = require(game.ReplicatedStorage.Modules.Utility.StateManager)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

-- Character Class identifiers
export type CharacterClassId = string

-- Import shared types from AbilityTypes to avoid circular dependency
export type EntityType = AbilityTypes.EntityType
export type EntityRef = AbilityTypes.EntityRef

-- Hooks that a character class can implement
export type CharacterClassHooks = {
    onInit: ((character: any) -> ())?,
    onUpdate: ((character: any, dt: number) -> ())?,
    onCleanup: ((character: any) -> ())?,
}

-- Character class definition
export type CharacterDefinition = {
    id: CharacterClassId,
    displayName: string?,
    -- Optional animation pack name (see ReplicatedStorage.Modules.AssetHandlers.Animations)
    animationPack: string?,
    -- Initial state definitions to apply to the StateManager. Values may be raw defaults
    -- or a table with { default: any, validator: (any) -> boolean }
    initialStates: {[string]: any}?,
    -- Optional mapping of a state/form key to an Ability Loadout assetKey in the Loadouts registry.
    -- Example: { Human = "Rem", Beast = "Ram", Default = "Default" }
    loadoutMapping: {[string]: string}?,
    -- Arbitrary custom data fields attached to characterData.Custom
    customFields: {[string]: any}?,
    hooks: CharacterClassHooks?,
}

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
	Entity : EntityRef, -- Replaces Player field to support both players and NPCs
    Character: Model,
	Humanoid : Humanoid,
    WeaponSheath : BasePart?,
    ClassId: CharacterClassId?,

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
    Definition: CharacterDefinition?,
    Custom: {[string]: any}?,

    Animations : Instance?,
}

export type CharacterConfig = {
    MaxHealth: number?,
    MaxStamina: number?,
    MaxGuard: number?,
    WalkSpeed: number?,
    RunSpeed: number?,
    RespawnTime: number?,
    AbilityLoadout: AbilityTypes.Loadout?,
    ClassId: CharacterClassId?,
    Custom: {[string]: any}?,
    -- NPC-specific configuration
    IsNPC: boolean?, -- Indicates if this is an NPC character
    NPCName: string?, -- Custom name for NPC (if different from model name)
}

export type ComponentInterface = {
    Initialize: (internalCharacter, any?) -> (),
    Update: (internalCharacter, number) -> ()?,
    Cleanup: (internalCharacter) -> ()?
}

export type ICharacterRegistry = {
    Register: (id: CharacterClassId, def: CharacterDefinition) -> (),
    Get: (id: CharacterClassId) -> CharacterDefinition?,
    GetAll: () -> {[string]: CharacterDefinition},
    Count: () -> number,
}

return 0