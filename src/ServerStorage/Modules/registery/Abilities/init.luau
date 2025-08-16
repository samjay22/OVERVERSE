--!strict
-- Legacy Ability registry wrapper - delegates to ImprovedAbilityRegistry

local ImprovedAbilityRegistry = require(game.ServerStorage.Modules.registery.ImprovedAbilityRegistry)

-- Export the improved registry with legacy compatibility
return ImprovedAbilityRegistry
