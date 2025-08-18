--!strict
-- Client Ability ability module implementing the static interface

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

local Ability: any = {}

function Ability.onRequest(ctx: SharedAbilityContext): AbilityResult
	warn("Called")
	return {
		success = true,
		cooldowns = { [tostring(ctx.abilityId)] = ctx.timestamp + 2 },
	}
end

function Ability.onCast(ctx: SharedAbilityContext, serverData: any?)
end

function Ability.OnCancel(ctx: SharedAbilityContext, reason: string?)
end


function Ability.getAbilityInputRequired()
	return Enum.UserInputType.MouseButton2
end

function Ability.getAbilityClassId()
	return "Rem"
end

return Ability
