--!strict
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
return {
    assetKey = "Human",
    loadout = {
        primaryAttack = "Default",
        actives = { Enums.AbilityId.Dash, Enums.AbilityId.Heal },
        passive = Enums.AbilityId.Keen,
    }
}
