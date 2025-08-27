--!strict
-- Fortify effect - reduces incoming damage and increases guard regen

local _ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local EffectTypes = require(game.ServerStorage.Modules.Types.EffectTypes)
local EffectBase = require(game.ServerStorage.Modules.BaseClasses.EffectBase)

-- Export the effect definition
return EffectBase.Buff:define({
    id = Enums.EffectId.Fortify,
    name = "Fortify",
    duration = 20, -- 20 seconds
    maxStacks = 1,
    onApply = function(ctx: EffectTypes.EffectContext)
        -- Fortify visual effect
    end,
    onRemove = function(ctx: EffectTypes.EffectContext)
        -- Cleanup
    end,
    compute = function(ctx: EffectTypes.EffectContext, accum: EffectTypes.Modifiers, stacks: number)
        -- Reduce incoming damage by 20% and increase guard regen by 50%
        accum.incomingDamageMult = (accum.incomingDamageMult or 1) * .8
        accum.guardRegenMult = (accum.guardRegenMult or 1) * 1.5
    end,
}) :: EffectTypes.EffectDef
