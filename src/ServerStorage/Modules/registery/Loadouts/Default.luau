--!strict
-- Default loadout for characters without a specific class

local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

export type Loadout = AbilityTypes.Loadout

local Default = {}

Default.assetKey = "Default"

Default.loadout = {
    primaryAttacks = {},
    actives = {},
    passive = nil,
    animationPack = "Default",
} :: Loadout

return Default