--!strict
-- Strongly-typed weapon system definitions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage.Modules.Types.Enums)

-- Core weapon types
export type WeaponId = Enums.WeaponId
export type WeaponType = Enums.WeaponType
export type WeaponAction = Enums.WeaponAction
export type DamageType = Enums.DamageType

-- Character reference (simplified to avoid circular imports)
export type CharacterRef = {
	PlayerId: number,
	Player: Player,
	Character: Model?,
	Humanoid: Humanoid?,
	StateManager: any,
	Components: {[string]: any},
}

-- Weapon context for actions
export type WeaponContext = {
	player: Player,
	character: CharacterRef,
	weaponId: WeaponId,
	action: WeaponAction,
	targetPosition: Vector3?,
	targetPlayer: Player?,
	direction: Vector3?,
	extra: {[string]: any}?,
}

-- Weapon action result
export type WeaponResult = {
	success: boolean,
	errorMessage: string?,
	damage: number?,
	targets: {Player}?,
	data: {[string]: any}?,
}

-- Base weapon definition
export type BaseWeaponDef = {
	id: WeaponId,
	type: WeaponType,
	name: string,
	description: string,
	icon: string?,
	level: number?,
	tags: {string}?,
	
	-- Stats
	damage: number,
	range: number,
	speed: number,
	durability: number?,
	
	-- Requirements
	staminaCost: number?,
	manaCost: number?,
	cooldown: number?,
}

-- Weapon handler interface (simplified)
export type WeaponHandler = {
	id: WeaponId,
	config: {
		AttackType: string?,
		Damage: number?,
		Range: number?,
		CanBlock: boolean?,
		AttackCooldown: number?,
		StaminaCost: number?,
	}?,
	OnAttack: (ctx: any) -> (boolean, string?),
	OnHit: (ctx: any) -> (boolean, string?),
}

-- Service interface (maintaining backwards compatibility)
export type IWeaponService = {
	RegisterWeapon: (self: IWeaponService, id: WeaponId, handler: WeaponHandler) -> (),
	Equip: (self: IWeaponService, playerId: number, weaponId: WeaponId) -> (),
	GetEquipped: (self: IWeaponService, playerId: number) -> WeaponId,
	Primary: (self: IWeaponService, player: Player, action: WeaponAction) -> boolean,
	Hit: (self: IWeaponService, player: Player, target: Instance | Player, extra: {[string]: any}?) -> boolean,
}

-- Legacy compatibility types
export type WeaponConfig = {
	AttackType: string?,
	Damage: number?,
	Range: number?,
	CanBlock: boolean?,
	AttackCooldown: number?,
	StaminaCost: number?,
}

export type AttackContext = {
	character: any,
	action: WeaponAction,
	config: WeaponConfig?,
}

export type HitContext = {
	attacker: any,
	target: any,
	targetModel: Model?,
	hitPart: BasePart?,
	damageOverride: number?,
	canBlock: boolean?,
	config: WeaponConfig?,
}

return 0
