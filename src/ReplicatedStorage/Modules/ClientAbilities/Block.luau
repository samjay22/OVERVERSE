--!strict
-- Client Block ability module implementing the static interface

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

local Block: any = {}

function Block.onRequest(ctx: SharedAbilityContext): AbilityResult
	local cdUntil = ctx.characterState.cooldowns and ctx.characterState.cooldowns[tostring(ctx.abilityId)]
	if cdUntil and cdUntil - ctx.timestamp > 0 then
		return { success = false }
	end
	return {
		success = true,
		cooldowns = { [tostring(ctx.abilityId)] = ctx.timestamp + 0.5 },
	}
end

function Block.onCast(ctx: SharedAbilityContext, serverData: any?)
end

function Block.OnCancel(ctx: SharedAbilityContext, reason: string?)
end

return Block
