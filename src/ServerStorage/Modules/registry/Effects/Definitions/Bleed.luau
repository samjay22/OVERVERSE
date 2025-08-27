--!strict
-- Bleed effect - deals damage over time

local _ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local EffectTypes = require(game.ServerStorage.Modules.Types.EffectTypes)
local EffectBase = require(game.ServerStorage.Modules.BaseClasses.EffectBase)

-- Export the effect definition
return EffectBase.DoT:define({
    id = Enums.EffectId.Bleed,
    name = "Bleed",
    duration = 10,
    maxStacks = 3,
    -- Defaults if caller doesn't provide ctx.extra.dps/total
    defaultTotalPerStack = 2,
}) :: EffectTypes.EffectDef
