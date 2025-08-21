--!strict
-- Strongly-typed ability system definitions

local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)

-- Core ability types
-- Use broad string ID to align with registry keys and ease authoring
export type AbilityId = string | (Enum.UserInputType)
export type AbilityType = Enums.AbilityType
export type AbilityTarget = Enums.AbilityTarget

-- Entity types for character management (shared definition)
export type EntityType = "Player" | "NPC"

-- Entity reference that can be either a Player or NPC
export type EntityRef = {
    entityType: EntityType,
    player: Player?, -- Only set if entityType is "Player"
    npcId: string?, -- Only set if entityType is "NPC"
    name: string,
    userId: number, -- Positive for players, negative for NPCs
}

-- Character reference (updated to use new system)
export type CharacterRef = {
	PlayerId: number,
	Entity: EntityRef, -- Updated to use EntityRef instead of Player
	Character: Model?,
	Humanoid: Humanoid?,
	StateManager: any, -- Will be properly typed once StateManager is refactored
	Components: {[string]: any},
	Events: {[string]: BindableEvent},
}

-- Ability context for activation (updated to support both players and NPCs)
export type AbilityContext = {
	entity: EntityRef, -- Changed from player: Player to entity: EntityRef
	character: CharacterRef,
	abilityId: AbilityId,
	targetPosition: Vector3?,
	targetEntity: EntityRef?, -- Changed from targetPlayer to targetEntity
	direction: Vector3?,
	extra: {[string]: any}?,
	-- Legacy compatibility fields
	player: Player?, -- Only populated for player entities
	targetPlayer: Player?, -- Only populated if target is a player
}

-- Ability activation result
export type AbilityResult = {
	success: boolean,
	errorMessage: string?,
	data: {[string]: any}?,
}

export type BaseAbilityDef = {
	id: AbilityId,
	type: string, -- "Active" | "Passive" | "Toggle"
	name: string,
	description: string,
	icon: string?,
	targetType: AbilityTarget,
	cooldown: number?,
	staminaCost: number?,
	level: number?,
	tags: {string}?,
}

-- Active ability definition
export type ActiveAbilityDef = BaseAbilityDef & {
	type: "Active",
	-- No serverActivate: client-authoritative with server validation elsewhere
	clientPreview: ((context: AbilityContext) -> boolean)?,
	range: number?,
	radius: number?,
	castTime: number?,
	channelTime: number?,
	interruptible: boolean?,
}

-- Primary attack ability definition (treated as a special type of active)
export type PrimaryAttackDef = BaseAbilityDef & {
	type: "Primary",
	-- No serverActivate: client-authoritative with server validation elsewhere
	clientPreview: ((context: AbilityContext) -> boolean)?,
	range: number?,
	radius: number?,
	castTime: number?,
	channelTime: number?,
	interruptible: boolean?,
}

-- Passive ability definition - significantly different from active abilities
export type PassiveAbilityDef = BaseAbilityDef & {
	type: "Passive",
	-- Called when equipped to a character
	onEquip: ((context: AbilityContext) -> {[string]: number}?)?,
	-- Called when unequipped from a character  
	onUnequip: ((context: AbilityContext) -> ())?,
	-- Called periodically while equipped (optional)
	onTick: ((context: AbilityContext, deltaTime: number) -> ())?,
	-- Base stat modifiers this passive provides
	statModifiers: {[string]: number}?,
}

-- Toggle ability definition
export type ToggleAbilityDef = BaseAbilityDef & {
	type: "Toggle",
	onActivate: (context: AbilityContext) -> AbilityResult,
	onDeactivate: (context: AbilityContext) -> AbilityResult,
	staminaPerSecond: number?,
	maxDuration: number?,
}

-- Union type for all ability definitions (improved)
export type AbilityDef = {
	-- Base fields (always present)
	id: AbilityId,
	type: "Active" | "Passive" | "Toggle" | "Primary",
	name: string,
	description: string,
	targetType: AbilityTarget,
	cooldown: number?,
	staminaCost: number?,
	level: number?,
	tags: {string}?,
	icon: string?,
	
	-- Active fields
	clientPreview: ((context: AbilityContext) -> boolean)?,
	range: number?,
	radius: number?,
	castTime: number?,
	channelTime: number?,
	interruptible: boolean?,
	
	-- Passive fields
	onEquip: ((context: AbilityContext) -> ())?,
	onUnequip: ((context: AbilityContext) -> ())?,
	onTick: ((context: AbilityContext, deltaTime: number) -> ())?,
	modifiers: {[string]: number}?,
	
	-- Toggle fields
	onActivate: ((context: AbilityContext) -> AbilityResult)?,
	onDeactivate: ((context: AbilityContext) -> AbilityResult)?,
	staminaPerSecond: number?,
	maxDuration: number?,
}

-- Simplified ability definition for registry
export type SimpleAbilityDef = {
	id: AbilityId,
	type: AbilityType,
	name: string,
	description: string,
	cooldown: number?,
	staminaCost: number?,
}

-- Legacy compatibility types
export type AnyAbilityDef = {
	id: AbilityId,
	kind: "Active" | "Passive" | "Primary",
	name: string,
	description: string?,
	cooldown: number?,
	staminaCost: number?,
}

export type Loadout = {
	primaryAttacks: {AbilityId},
	actives: {AbilityId},
	passive: AbilityId?,
	animationPack: string?,
}

export type PerCharacterAbilityState = {
	cooldowns: {[AbilityId]: number},
	loadout: Loadout,
}

export type IAbilityService = {
	Initialize: (self: IAbilityService, character: CharacterRef, loadout: Loadout?) -> (),
	Update: (self: IAbilityService, character: CharacterRef, dt: number) -> (),
	Activate: (self: IAbilityService, entity: EntityRef | Player, abilityId: AbilityId, ctxExtra: {[string]: any}?) -> boolean,
	PrimaryAttack: (self: IAbilityService, entity: EntityRef | Player, attackType: string?) -> boolean,
}

return 0
