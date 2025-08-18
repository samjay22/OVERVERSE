--!strict
-- Client Thrust ability module implementing the static interface

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

local Thrust: any = {}

local CONSTANTS = {
	COOLDOWN = 3.0,
	STAMINA_COST = 20,
	DAMAGE = 40,
	RANGE = 12,
	SPEED = 100,
}

local function _createCooldownTable(abilityId: string, timestamp: number, duration: number)
	return { [abilityId] = timestamp + duration }
end

function Thrust.onRequest(ctx: SharedAbilityContext): AbilityResult
	local dir = ctx.inputData.direction or Vector3.new(0, 0, 1)
	if dir.Magnitude < 0.1 then
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

function Thrust.onCast(ctx: SharedAbilityContext, serverData: any?)
end

function Thrust.OnCancel(ctx: SharedAbilityContext, reason: string?)
end

function Thrust.getAbilityInputRequired()
	-- Default mapping: X key
	return Enum.KeyCode.X
end

function Thrust.getAbilityClassId()
	return nil
end

return Thrust
