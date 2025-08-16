--!strict
-- Client Heal ability module implementing the static interface

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

local Heal: any = {}

local CONSTANTS = {
	COOLDOWN = 6.0,
	STAMINA_COST = 25,
	HEAL_AMOUNT = 30,
	CAST_TIME = 0.8,
}

local function _createCooldownTable(abilityId: string, timestamp: number, duration: number)
	return { [abilityId] = timestamp + duration }
end

function Heal.onRequest(ctx: SharedAbilityContext): AbilityResult
	-- Minimal validation: off cooldown only
	local cdUntil = ctx.characterState.cooldowns and ctx.characterState.cooldowns[tostring(ctx.abilityId)]
	if cdUntil and cdUntil - ctx.timestamp > 0 then
		return { success = false }
	end

	return {
		success = true,
		cooldowns = _createCooldownTable(ctx.abilityId :: any, ctx.timestamp, CONSTANTS.COOLDOWN),
	}
end

function Heal.onCast(ctx: SharedAbilityContext, serverData: any?)
end

function Heal.OnCancel(ctx: SharedAbilityContext, reason: string?)
end

return Heal
