--!strict
-- Default loadout for testing - individual module approach

local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)

-- Export the loadout definition
return {
    assetKey = "Default",
    loadout = {
        primaryAttack = "Default",
        actives = { Enums.AbilityId.Dash },
        passive = Enums.AbilityId.Keen,
    }
}
