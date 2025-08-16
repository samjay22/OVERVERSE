--!strict
-- Strongly-typed ability system definitions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage.Modules.Types.Enums)

-- Core ability types
-- Use broad string ID to align with registry keys and ease authoring
export type AbilityId = string
export type AbilityType = Enums.AbilityType
export type AbilityTarget = Enums.AbilityTarget

-- Character reference (strongly typed)
export type CharacterRef = {
	PlayerId: number,
	Player: Player,
	Character: Model?,
	Humanoid: Humanoid?,
	StateManager: any, -- Will be properly typed once StateManager is refactored
	Components: {[string]: any},
	Events: {[string]: BindableEvent},
}

-- Ability context for activation
export type AbilityContext = {
	player: Player,
	character: CharacterRef,
	abilityId: AbilityId,
	targetPosition: Vector3?,
	targetPlayer: Player?,
	direction: Vector3?,
	extra: {[string]: any}?,
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
	manaCost: number?,
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

-- Passive ability definition  
export type PassiveAbilityDef = BaseAbilityDef & {
	type: "Passive",
	onEquip: ((context: AbilityContext) -> ())?,
	onUnequip: ((context: AbilityContext) -> ())?,
	onTick: ((context: AbilityContext, deltaTime: number) -> ())?,
	modifiers: {[string]: number}?,
}

-- Toggle ability definition
export type ToggleAbilityDef = BaseAbilityDef & {
	type: "Toggle",
	onActivate: (context: AbilityContext) -> AbilityResult,
	onDeactivate: (context: AbilityContext) -> AbilityResult,
	staminaPerSecond: number?,
	manaPerSecond: number?,
	maxDuration: number?,
}

-- Union type for all ability definitions (improved)
export type AbilityDef = {
	-- Base fields (always present)
	id: AbilityId,
	type: "Active" | "Passive" | "Toggle",
	name: string,
	description: string,
	targetType: AbilityTarget,
	cooldown: number?,
	staminaCost: number?,
	manaCost: number?,
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
	manaPerSecond: number?,
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
	kind: "Active" | "Passive",
	name: string,
	description: string?,
	cooldown: number?,
	staminaCost: number?,
}

export type Loadout = {
	primaryAttack: string?,
	actives: {AbilityId},
	passive: AbilityId?,
}

export type PerCharacterAbilityState = {
	cooldowns: {[AbilityId]: number},
	loadout: Loadout,
}

export type IAbilityService = {
	Initialize: (self: IAbilityService, character: CharacterRef, loadout: Loadout?) -> (),
	Update: (self: IAbilityService, character: CharacterRef, dt: number) -> (),
	Activate: (self: IAbilityService, player: Player, abilityId: AbilityId, ctxExtra: {[string]: any}?) -> boolean,
	PrimaryAttack: (self: IAbilityService, player: Player, attackType: string?) -> boolean,
}

return 0
