--!strict
-- Strongly-typed enums and constants

-- Ability system
export type AbilityId = "Dash" | "Keen" | "Heal" | "Block" | "Parry" | "Charge" | "Slam" | "Thrust" | "RemM1" | "RemM2" | "RemShift"
export type AbilityType = "Active" | "Passive" | "Toggle"
export type AbilityTarget = "Self" | "Target" | "Area" | "None"
export type AbilityCategory = "Primary" | "Active" | "Passive" | "Secondary" | "Ultimate"

local AbilityId = {
	Dash = "Dash" :: AbilityId,
	Keen = "Keen" :: AbilityId,
	Heal = "Heal" :: AbilityId,
	Block = "Block" :: AbilityId,
	Parry = "Parry" :: AbilityId,
	Charge = "Charge" :: AbilityId,
	Slam = "Slam" :: AbilityId,
	Thrust = "Thrust" :: AbilityId,
	RemM1 = "RemM1" :: AbilityId,
	RemM2 = "RemM2" :: AbilityId,
	RemShift = "RemShift" :: AbilityId,
} :: {[string]: AbilityId}

local AbilityType = {
	Active = "Active" :: AbilityType,
	Passive = "Passive" :: AbilityType,
	Toggle = "Toggle" :: AbilityType,
} :: {[string]: AbilityType}

local _AbilityCategory = {
	Primary = "Primary" :: AbilityCategory,
	Active = "Active" :: AbilityCategory,
	Passive = "Passive" :: AbilityCategory,
	Secondary = "Secondary" :: AbilityCategory,
	Ultimate = "Ultimate" :: AbilityCategory,
} :: {[string]: AbilityCategory}

local AbilityTarget = {
	Self = "Self" :: AbilityTarget,
	Target = "Target" :: AbilityTarget,
	Area = "Area" :: AbilityTarget,
	None = "None" :: AbilityTarget,
} :: {[string]: AbilityTarget}

-- Weapon system
export type WeaponId = "Default" | "Sword" | "Spear" | "Bow" | "Staff" | "Dagger" | "Hammer" | "Axe"
export type WeaponType = "Melee" | "Ranged" | "Magic"
export type WeaponAction = "M1" | "M2" | "Heavy" | "Light" | "Special" | "Block" | "Aim"
export type DamageType = "Physical" | "Magical" | "True" | "Poison" | "Fire" | "Ice" | "Lightning"

local WeaponId = {
	Default = "Default" :: WeaponId,
	Sword = "Sword" :: WeaponId,
	Spear = "Spear" :: WeaponId,
	Bow = "Bow" :: WeaponId,
	Staff = "Staff" :: WeaponId,
	Dagger = "Dagger" :: WeaponId,
	Hammer = "Hammer" :: WeaponId,
	Axe = "Axe" :: WeaponId,
} :: {[string]: WeaponId}

local WeaponType = {
	Melee = "Melee" :: WeaponType,
	Ranged = "Ranged" :: WeaponType,
	Magic = "Magic" :: WeaponType,
} :: {[string]: WeaponType}

local WeaponAction = {
	M1 = "M1" :: WeaponAction,
	M2 = "M2" :: WeaponAction,
	Heavy = "Heavy" :: WeaponAction,
	Light = "Light" :: WeaponAction,
	Special = "Special" :: WeaponAction,
	Block = "Block" :: WeaponAction,
	Aim = "Aim" :: WeaponAction,
} :: {[string]: WeaponAction}

local DamageType = {
	Physical = "Physical" :: DamageType,
	Magical = "Magical" :: DamageType,
	True = "True" :: DamageType,
	Poison = "Poison" :: DamageType,
	Fire = "Fire" :: DamageType,
	Ice = "Ice" :: DamageType,
	Lightning = "Lightning" :: DamageType,
} :: {[string]: DamageType}

-- Effect system
export type EffectId = "Bleed" | "Rally" | "Fortify" | "Regeneration" | "Poison" | "Burn" | "Freeze" | "Stun" | "Slow" | "Haste"
export type EffectType = "Buff" | "Debuff" | "Neutral"
export type EffectDuration = "Instant" | "Timed" | "Permanent" | "Conditional"

local EffectId = {
	Bleed = "Bleed" :: EffectId,
	Rally = "Rally" :: EffectId,
	Fortify = "Fortify" :: EffectId,
	Regeneration = "Regeneration" :: EffectId,
	Poison = "Poison" :: EffectId,
	Burn = "Burn" :: EffectId,
	Freeze = "Freeze" :: EffectId,
	Stun = "Stun" :: EffectId,
	Slow = "Slow" :: EffectId,
	Haste = "Haste" :: EffectId,
} :: {[string]: EffectId}

local EffectType = {
	Buff = "Buff" :: EffectType,
	Debuff = "Debuff" :: EffectType,
	Neutral = "Neutral" :: EffectType,
} :: {[string]: EffectType}

local EffectDuration = {
	Instant = "Instant" :: EffectDuration,
	Timed = "Timed" :: EffectDuration,
	Permanent = "Permanent" :: EffectDuration,
	Conditional = "Conditional" :: EffectDuration,
} :: {[string]: EffectDuration}

-- Character system
export type CharacterId = string
export type CharacterClass = "Warrior" | "Mage" | "Rogue" | "Archer" | "Paladin" | "Necromancer"
export type CharacterState = "Idle" | "Moving" | "Attacking" | "Blocking" | "Dashing" | "Stunned" | "Dead"

local CharacterClass = {
	Warrior = "Warrior" :: CharacterClass,
	Mage = "Mage" :: CharacterClass,
	Rogue = "Rogue" :: CharacterClass,
	Archer = "Archer" :: CharacterClass,
	Paladin = "Paladin" :: CharacterClass,
	Necromancer = "Necromancer" :: CharacterClass,
} :: {[string]: CharacterClass}

local CharacterState = {
	Idle = "Idle" :: CharacterState,
	Moving = "Moving" :: CharacterState,
	Attacking = "Attacking" :: CharacterState,
	Blocking = "Blocking" :: CharacterState,
	Dashing = "Dashing" :: CharacterState,
	Stunned = "Stunned" :: CharacterState,
	Dead = "Dead" :: CharacterState,
} :: {[string]: CharacterState}

-- Network system
export type NetworkEventType = "Ability" | "Weapon" | "Movement" | "Combat" | "Character" | "Effect" | "System"
export type NetworkMessageType = "Request" | "Response" | "Notification" | "Command"

local NetworkEventType = {
	Ability = "Ability" :: NetworkEventType,
	Weapon = "Weapon" :: NetworkEventType,
	Movement = "Movement" :: NetworkEventType,
	Combat = "Combat" :: NetworkEventType,
	Character = "Character" :: NetworkEventType,
	Effect = "Effect" :: NetworkEventType,
	System = "System" :: NetworkEventType,
} :: {[string]: NetworkEventType}

local NetworkMessageType = {
	Request = "Request" :: NetworkMessageType,
	Response = "Response" :: NetworkMessageType,
	Notification = "Notification" :: NetworkMessageType,
	Command = "Command" :: NetworkMessageType,
} :: {[string]: NetworkMessageType}

-- Legacy support (will be phased out)
export type CoreMessageType = "PrimaryWeapon" | "Ability"
export type AttackType = "Default"

local CoreMessageType = {
	PrimaryWeapon = "PrimaryWeapon" :: CoreMessageType,
	Ability = "Ability" :: CoreMessageType,
} :: {[string]: CoreMessageType}

local AttackType = {
	Default = "Default" :: AttackType,
} :: {[string]: AttackType}

return {
	AbilityId = AbilityId,
	AbilityType = AbilityType,
	AbilityTarget = AbilityTarget,
	WeaponId = WeaponId,
	WeaponType = WeaponType,
	WeaponAction = WeaponAction,
	DamageType = DamageType,
	EffectId = EffectId,
	EffectType = EffectType,
	EffectDuration = EffectDuration,
	CharacterClass = CharacterClass,
	CharacterState = CharacterState,
	NetworkEventType = NetworkEventType,
	NetworkMessageType = NetworkMessageType,
	-- Legacy support
	CoreMessageType = CoreMessageType,
	AttackType = AttackType,
}
