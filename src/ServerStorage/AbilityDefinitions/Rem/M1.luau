--!strict
-- Rem M1 Ability Definition for the new scalable ability system

local AbilitySystemPath = game.ServerStorage.Modules.Core.AbilitySystem
local Types = require(AbilitySystemPath.Types)
local AbilityDefinition = require(AbilitySystemPath.AbilityDefinition)

type AbilityDefinition = Types.AbilityDefinition

-- Create the M1 ability definition using the builder pattern
local M1Definition = (AbilityDefinition.builder())
    :setId("Rem_M1")
    :setName("Spirit Burst")
    :setType("Instant")
    :setCooldown({ base = 0.65, modifiable = true }) -- Time between shots
    :setTargeting({
        type = "Aimed",
        range = 100,
        requireLineOfSight = true,
        filter = {
            team = "All",
            status = "Alive"
        }
    })
    
    -- Burst fire mechanics via charges
    :addTag("Burst")
    :addTag("Projectile")
    :addTag("Rem")
    :addEffect({
        type = "Damage",
        damageType = "Magical",
        trigger = "OnHit",
        amount = 25
    })
    :addCombo({
        id = "Rem_M1_Burst",
        name = "Spirit Burst",
        sequence = {"Rem_M1", "Rem_M1", "Rem_M1"},
        window = 2,
        requirements = {
            targetSame = true,
            minDamage = 50
        },
        effects = {
            {
                type = "Damage",
                damageType = "Magical",
                trigger = "OnHit",
                amount = 25
            }
        }
    })
    :addResource({
        type = "Ammo",
        amount = 12,
        consumeOnUse = true
    })
    :setCustomData(
        {
        ammoPerBurst = 4,
        maxAmmo = 12,
        reloadTime = 5,
        burstDelay = 0.1 -- Delay between shots in a burst
        }
    )
    :build()

return M1Definition