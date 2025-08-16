--!strict
-- Client Charge ability module implementing the static interface

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

local Charge: any = {}

local CONSTANTS = {
	COOLDOWN = 8.0,
	STAMINA_COST = 40,
	DISTANCE = 30,
	DAMAGE = 50,
	SPEED = 120,
}

local function _createCooldownTable(abilityId: string, timestamp: number, duration: number)
	return { [abilityId] = timestamp + duration }
end

function Charge.onRequest(ctx: SharedAbilityContext): AbilityResult
	local dir = ctx.inputData.direction
	if not dir or dir.Magnitude < 0.1 then
		return { success = false }
	end
	local cdUntil = ctx.characterState.cooldowns and ctx.characterState.cooldowns[tostring(ctx.abilityId)]
	if cdUntil and cdUntil - ctx.timestamp > 0 then
		return { success = false }
	end
	return {
		success = true,
		cooldowns = _createCooldownTable(ctx.abilityId :: any, ctx.timestamp, CONSTANTS.COOLDOWN),
	}
end

function Charge.onCast(ctx: SharedAbilityContext, serverData: any?)
end

function Charge.OnCancel(ctx: SharedAbilityContext, reason: string?)
end

return Charge
