--!strict
-- Client Keen ability module implementing the static interface

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

local Keen: any = {}

function Keen.onRequest(ctx: SharedAbilityContext): AbilityResult
	local cdUntil = ctx.characterState.cooldowns and ctx.characterState.cooldowns[tostring(ctx.abilityId)]
	if cdUntil and cdUntil - ctx.timestamp > 0 then
		return { success = false }
	end
	return {
		success = true,
		cooldowns = { [tostring(ctx.abilityId)] = ctx.timestamp + 1.5 },
	}
end

function Keen.onCast(ctx: SharedAbilityContext, serverData: any?)
end

function Keen.OnCancel(ctx: SharedAbilityContext, reason: string?)
end

return Keen
