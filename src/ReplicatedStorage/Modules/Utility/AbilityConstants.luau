--!strict
-- Static constants for ability defaults (cooldowns, stamina costs, etc.)

local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)

type AbilityId = Enums.AbilityId

export type AbilityConfig = {
	cooldown: number?,
	staminaCost: number?,
}

local AbilityDefaults: {[AbilityId]: AbilityConfig} = {
	[Enums.AbilityId.Dash] = { cooldown = 3, staminaCost = 15 },
	[Enums.AbilityId.Keen] = {},
}

return {
	Defaults = AbilityDefaults,
}
