--!strict
-- Client Dash ability module implementing the static interface

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

local Dash: any = {}

local CONSTANTS = {
	COOLDOWN = 2.0,
	STAMINA_COST = 15,
	DISTANCE = 20,
	SPEED = 80,
	DURATION = 0.25,
	SMOOTH_FACTOR = 0.8,
}

local function _createCooldownTable(abilityId: string, timestamp: number, duration: number)
	return { [abilityId] = timestamp + duration }
end

function Dash.onRequest(ctx: SharedAbilityContext): AbilityResult
	-- Minimal validation: direction present and off cooldown
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

function Dash.onCast(ctx: SharedAbilityContext, serverData: any?)
	-- Optional: hook for authoritative confirmation (play stronger VFX)
	-- e.g., create a burst, camera shake, etc.
end

function Dash.OnCancel(ctx: SharedAbilityContext, reason: string?)
	-- Optional: revert local prediction if needed
end

function Dash.getAbilityInputRequired()
	return Enum.KeyCode.Q
end

return Dash
