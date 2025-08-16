--!strict
-- Regeneration effect - heals health over time (HoT)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage.Modules.Types.Enums)
local EffectTypes = require(game.ServerStorage.Modules.Types.EffectTypes)
local EffectBase = require(game.ServerStorage.Modules.BaseClasses.EffectBase)

-- Export the effect definition
return EffectBase.HoT:define({
    id = Enums.EffectId.Regeneration,
    name = "Regeneration",
    duration = 10,
    maxStacks = 1,
    -- Defaults if caller doesn't provide ctx.extra.amountPerSecond/total
    defaultAmountPerSecondPerStack = 5,
}) :: EffectTypes.EffectDef
