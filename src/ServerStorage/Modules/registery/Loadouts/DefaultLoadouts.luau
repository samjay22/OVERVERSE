--!strict
-- Default loadouts in declarative format

local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)

local M = {}

M.Definitions = {
    {
        assetKey = "Default",
        loadout = {
            primaryAttack = "Default",
            actives = { Enums.AbilityId.Dash },
            passive = Enums.AbilityId.Keen,
        }
    }
}

return M
