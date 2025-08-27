--!strict
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

export type Loadout = AbilityTypes.Loadout

-- Use the new ability IDs from the definition system
return {
    assetKey = "Rem",
    loadout = {
        primaryAttacks = {"Rem_M1"}, -- Using new ability IDs
        actives = {"Rem_E", "Rem_F"}, -- E, F slots (Q and R not implemented yet)
        passive = "Rem_Passive",
        animationPack = "Rem",
    }
} :: {assetKey : string, loadout : Loadout}