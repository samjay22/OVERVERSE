--!strict
-- Legacy Ability registry wrapper - delegates to new AbilityRegistry

local AbilityRegistry = require(script.AbilityRegistry)

-- Export the new registry with legacy compatibility
return AbilityRegistry
