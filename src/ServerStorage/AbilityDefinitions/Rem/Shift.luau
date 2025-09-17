--!strict
-- Shift Ability Definition - Fast movement ability that teleports the player forward

local AbilitySystemPath = game.ServerStorage.Modules.Core.AbilitySystem
local Types = require(AbilitySystemPath.Types)
local AbilityDefinition = require(AbilitySystemPath.AbilityDefinition)

type AbilityDefinition = Types.AbilityDefinition

-- Create the Shift ability definition using the builder pattern
local ShiftDefinition = (AbilityDefinition.builder())
    :setId("Rem_Shift")
    :setName("Shift")
    :setType("Instant")
    :setCooldown({ base = 3.0, modifiable = true }) -- 3 second cooldown
    :setTargeting({
        type = "Self",
        range = 0,
        requireLineOfSight = false,
        filter = {
            team = "All",
            status = "Alive"
        }
    })
    
    -- Tags for categorization and effects
    :addTag("Movement")
    :addTag("Dash")
    :addTag("Instant")
    
    -- Main dash effect
    :addEffect({
        type = "Dash",
        trigger = "OnCast",
        distance = 25, -- Dash 25 studs forward
        speed = 200, -- Fast movement speed
        direction = "Forward" -- Dash in the direction the player is facing
    })
    
    -- Add resource requirement (stamina cost)
    :addResource({
        type = "Stamina",
        amount = 20,
        consumeOnUse = true
    })
    
    -- Custom data for specific implementation details
    :setCustomData({
        dashDistance = 25,
        dashSpeed = 200,
        canPassThroughEnemies = false,
        stunOnWall = false,
        maxHeight = 5 -- Maximum height difference the dash can traverse
    })
    :build()

return ShiftDefinition
