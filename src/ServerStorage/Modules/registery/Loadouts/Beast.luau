--!strict
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
return {
    assetKey = "Beast",
    loadout = {
        primaryAttack = "Default",
        actives = { Enums.AbilityId.Slam, Enums.AbilityId.Thrust },
        passive = Enums.AbilityId.Keen,
    }
}
