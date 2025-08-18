--!strict
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

export type Loadout = AbilityTypes.Loadout

local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
return {
    assetKey = "Rem",
    loadout = {
        primaryAttacks = {Enums.AbilityId.RemM1, Enums.AbilityId.RemM2},
        actives = { Enums.AbilityId.Dash, Enums.AbilityId.Heal },
        passive = Enums.AbilityId.Keen,
    animationPack = "Rem",
    }
} :: {assetKey : string, loadout : Loadout}
