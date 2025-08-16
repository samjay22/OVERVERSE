--!strict
-- Strongly-typed network message definitions

local Enums = require(script.Parent.Enums)

-- Base network message structure
export type NetworkMessage<T> = {
	type: Enums.NetworkEventType,
	messageType: Enums.NetworkMessageType,
	timestamp: number,
	playerId: number?,
	data: T,
}

-- Ability messages
export type AbilityActivateData = {
	abilityId: Enums.AbilityId,
	targetPosition: Vector3?,
	targetPlayerId: number?,
	extra: {[string]: any}?,
}

export type AbilityActivateMessage = NetworkMessage<AbilityActivateData>

export type AbilityResultData = {
	abilityId: Enums.AbilityId,
	success: boolean,
	errorMessage: string?,
	cooldownRemaining: number?,
}

export type AbilityResultMessage = NetworkMessage<AbilityResultData>

-- Weapon messages
export type WeaponActionData = {
	weaponId: Enums.WeaponId,
	action: Enums.WeaponAction,
	targetPosition: Vector3?,
	targetPlayerId: number?,
	direction: Vector3?,
}

export type WeaponActionMessage = NetworkMessage<WeaponActionData>

export type WeaponHitData = {
	weaponId: Enums.WeaponId,
	targetPlayerId: number,
	damage: number,
	damageType: Enums.DamageType,
	hitPosition: Vector3,
	knockback: Vector3?,
}

export type WeaponHitMessage = NetworkMessage<WeaponHitData>

-- Combat messages
export type DamageData = {
	sourcePlayerId: number?,
	targetPlayerId: number,
	damage: number,
	damageType: Enums.DamageType,
	sourceWeaponId: Enums.WeaponId?,
	sourceAbilityId: Enums.AbilityId?,
	position: Vector3?,
}

export type DamageMessage = NetworkMessage<DamageData>

export type HealData = {
	sourcePlayerId: number?,
	targetPlayerId: number,
	healAmount: number,
	sourceAbilityId: Enums.AbilityId?,
}

export type HealMessage = NetworkMessage<HealData>

-- Character messages
export type CharacterSpawnData = {
	playerId: number,
	characterClass: Enums.CharacterClass?,
	position: Vector3,
	loadout: {
		weaponId: Enums.WeaponId,
		abilities: {Enums.AbilityId},
	}?,
}

export type CharacterSpawnMessage = NetworkMessage<CharacterSpawnData>

export type CharacterStateData = {
	playerId: number,
	state: Enums.CharacterState,
	duration: number?,
	extra: {[string]: any}?,
}

export type CharacterStateMessage = NetworkMessage<CharacterStateData>

-- Effect messages
export type EffectApplyData = {
	effectId: Enums.EffectId,
	targetPlayerId: number,
	sourcePlayerId: number?,
	duration: number?,
	stacks: number?,
	power: number?,
}

export type EffectApplyMessage = NetworkMessage<EffectApplyData>

export type EffectRemoveData = {
	effectId: Enums.EffectId,
	targetPlayerId: number,
	reason: "Expired" | "Cleansed" | "Death" | "Manual",
}

export type EffectRemoveMessage = NetworkMessage<EffectRemoveData>

-- Movement messages
export type MovementData = {
	playerId: number,
	position: Vector3,
	velocity: Vector3?,
	rotation: CFrame?,
	movementType: "Normal" | "Teleport" | "Dash" | "Jump",
}

export type MovementMessage = NetworkMessage<MovementData>

-- System messages
export type SystemNotificationData = {
	notificationType: "Info" | "Warning" | "Error" | "Success",
	title: string,
	message: string,
	duration: number?,
}

export type SystemNotificationMessage = NetworkMessage<SystemNotificationData>

-- Union types for all message data
export type GameMessageData = 
	AbilityActivateData | AbilityResultData |
	WeaponActionData | WeaponHitData |
	DamageData | HealData |
	CharacterSpawnData | CharacterStateData |
	EffectApplyData | EffectRemoveData |
	MovementData | SystemNotificationData

-- Legacy message types (for backwards compatibility)
export type PrimaryWeaponMsg = {
	t: Enums.CoreMessageType,
	action: Enums.WeaponAction,
}

export type AbilityMsg = {
	t: Enums.CoreMessageType,
	id: Enums.AbilityId,
	extra: {[string]: any}?,
}

export type CoreMessage = PrimaryWeaponMsg | AbilityMsg

-- Helper functions for creating messages
local NetworkTypes = {}

function NetworkTypes.CreateAbilityActivateMessage(
	playerId: number,
	abilityId: Enums.AbilityId,
	data: {
		targetPosition: Vector3?,
		targetPlayerId: number?,
		extra: {[string]: any}?,
	}?
): AbilityActivateMessage
	return {
		type = Enums.NetworkEventType.Ability,
		messageType = Enums.NetworkMessageType.Request,
		timestamp = tick(),
		playerId = playerId,
		data = {
			abilityId = abilityId,
			targetPosition = data and data.targetPosition,
			targetPlayerId = data and data.targetPlayerId,
			extra = data and data.extra,
		},
	}
end

function NetworkTypes.CreateWeaponActionMessage(
	playerId: number,
	weaponId: Enums.WeaponId,
	action: Enums.WeaponAction,
	data: {
		targetPosition: Vector3?,
		targetPlayerId: number?,
		direction: Vector3?,
	}?
): WeaponActionMessage
	return {
		type = Enums.NetworkEventType.Weapon,
		messageType = Enums.NetworkMessageType.Request,
		timestamp = tick(),
		playerId = playerId,
		data = {
			weaponId = weaponId,
			action = action,
			targetPosition = data and data.targetPosition,
			targetPlayerId = data and data.targetPlayerId,
			direction = data and data.direction,
		},
	}
end

function NetworkTypes.CreateDamageMessage(
	sourcePlayerId: number?,
	targetPlayerId: number,
	damage: number,
	damageType: Enums.DamageType,
	data: {
		sourceWeaponId: Enums.WeaponId?,
		sourceAbilityId: Enums.AbilityId?,
		position: Vector3?,
	}?
): DamageMessage
	return {
		type = Enums.NetworkEventType.Combat,
		messageType = Enums.NetworkMessageType.Notification,
		timestamp = tick(),
		playerId = sourcePlayerId,
		data = {
			sourcePlayerId = sourcePlayerId,
			targetPlayerId = targetPlayerId,
			damage = damage,
			damageType = damageType,
			sourceWeaponId = data and data.sourceWeaponId,
			sourceAbilityId = data and data.sourceAbilityId,
			position = data and data.position,
		},
	}
end

return NetworkTypes
