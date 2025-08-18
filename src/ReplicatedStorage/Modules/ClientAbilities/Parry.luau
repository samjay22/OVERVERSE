--!strict
-- Client Parry ability module implementing the static interface

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

local Parry: any = {}

function Parry.onRequest(ctx: SharedAbilityContext): AbilityResult
	local cdUntil = ctx.characterState.cooldowns and ctx.characterState.cooldowns[tostring(ctx.abilityId)]
	if cdUntil and cdUntil - ctx.timestamp > 0 then
		return { success = false }
	end
	return {
		success = true,
		cooldowns = { [tostring(ctx.abilityId)] = ctx.timestamp + 4.0 },
	}
end

function Parry.onCast(ctx: SharedAbilityContext, serverData: any?)
end

function Parry.OnCancel(ctx: SharedAbilityContext, reason: string?)
end

function Parry.getAbilityInputRequired()
	-- Default mapping: G key
	return Enum.KeyCode.G
end

function Parry.getAbilityClassId()
	return nil
end

return Parry
