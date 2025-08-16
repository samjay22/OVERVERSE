--!strict
-- Status / Buff / Debuff effect types

local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

export type EffectId = Enums.EffectId
export type EffectCategory = "Buff" | "Debuff" | "DoT" | "HoT" | "Other" | string

export type EffectMagnitude = number

export type EffectContext = AbilityTypes.AbilityContext & {
	-- effect-specific fields can be passed via ctx.extra
}

export type EffectDef = {
	id: EffectId,
	name: string,
	duration: number?,
	maxStacks: number?,
	isBuff: boolean?,
	category: EffectCategory?,
	-- optional fixed tick interval; when > 0, onTick fires at this cadence
	tickInterval: number?,
	-- lifecycle
	onApply: (ctx: EffectContext) -> (),
	onRemove: (ctx: EffectContext) -> (),
	onTick: ((ctx: EffectContext, dt: number, stacks: number) -> ())?,
	-- optional compute hook to contribute to combat modifiers
	compute: ((ctx: EffectContext, accum: Modifiers, stacks: number) -> ())?,
}

export type ActiveEffect = {
	id: EffectId,
	stacks: number,
	expiresAt: number?,
	extra: {[string]: any}?,
	def: EffectDef,
	_tickAccum: number?,
}

export type PerCharacterEffects = {
	byId: {[EffectId]: ActiveEffect},
}

export type Modifiers = {
	outgoingDamageMult: number?,
	incomingDamageMult: number?,
	staminaCostMult: number?,
	attackCooldownMult: number?,
	guardRegenMult: number?,
	staminaRegenBonus: number?, -- additive per second
	critChance: number?, -- additive chance (0..1)
	critDamage: number?, -- additive multiplier (e.g., +0.25)
}

return 0
