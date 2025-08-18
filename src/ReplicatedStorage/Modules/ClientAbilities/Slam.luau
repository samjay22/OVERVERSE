--!strict
-- Client Slam ability module implementing the static interface

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

local Slam: any = {}

local CONSTANTS = {
	COOLDOWN = 12.0,
	STAMINA_COST = 50,
	DAMAGE = 75,
	RADIUS = 15,
	CAST_TIME = 1.2,
}

local function _createCooldownTable(abilityId: string, timestamp: number, duration: number)
	return { [abilityId] = timestamp + duration }
end

function Slam.onRequest(ctx: SharedAbilityContext): AbilityResult
	local cdUntil = ctx.characterState.cooldowns and ctx.characterState.cooldowns[tostring(ctx.abilityId)]
	if cdUntil and cdUntil - ctx.timestamp > 0 then
		return { success = false }
	end
	return {
		success = true,
		cooldowns = _createCooldownTable(ctx.abilityId :: any, ctx.timestamp, CONSTANTS.COOLDOWN),
	}
end

function Slam.onCast(ctx: SharedAbilityContext, serverData: any?)
end

function Slam.OnCancel(ctx: SharedAbilityContext, reason: string?)
end

function Slam.getAbilityInputRequired()
	-- Default mapping: V key
	return Enum.KeyCode.V
end

function Slam.getAbilityClassId()
	return nil
end

return Slam
