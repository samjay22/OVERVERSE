--!strict
-- Keen - Passive ability that increases critical hit chance and damage

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(game.ReplicatedStorage.Modules.Types.ClientAbilityTypes)

type StateSnapshot = Types.StateSnapshot
type AbilityCategory = Types.AbilityCategory
type ClassId = Types.ClassId

local Keen = {}

-- Keen provides increased critical hit chance and critical hit damage
local CRIT_CHANCE_BONUS = 0.15 -- +15% crit chance
local CRIT_DAMAGE_BONUS = 0.25 -- +25% crit damage

function Keen.onEquip(playerId: number, characterState: StateSnapshot): {[string]: number}?
    -- Return stat modifiers that should be applied when this passive is equipped
    return {
        CriticalChance = CRIT_CHANCE_BONUS,
        CriticalDamage = CRIT_DAMAGE_BONUS,
    }
end

function Keen.onUnequip(playerId: number, characterState: StateSnapshot)
    -- Called when the passive is removed - no special cleanup needed for Keen
end

-- Optional: periodic tick for passives that need continuous updates
function Keen.onTick(playerId: number, characterState: StateSnapshot, deltaTime: number)
    warn("test")
    -- Keen doesn't need periodic updates, but this could be used for
    -- passives that need to check conditions or apply effects over time
end

function Keen.getAbilityClassId(): ClassId?
    return nil -- Available to all classes
end

function Keen.getAbilityCategory(): AbilityCategory
    return "Passive"
end

function Keen.getStatModifiers(): {[string]: number}?
    return {
        CriticalChance = CRIT_CHANCE_BONUS,
        CriticalDamage = CRIT_DAMAGE_BONUS,
    }
end

return Keen
