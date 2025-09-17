--!strict
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

export type Loadout = AbilityTypes.Loadout

-- Use the new ability IDs from the definition system
return {
    assetKey = "Rem",
    loadout = {
        primaryAttacks = {"Rem_M1"}, -- Using new ability IDs
        actives = {"Rem_Shift", "Rem_E", "Rem_F"}, -- Q (Shift), E, F slots 
        passive = "Rem_Passive",
        animationPack = "Rem",
    }
} :: {assetKey : string, loadout : Loadout}