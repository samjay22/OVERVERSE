--!strict
-- Rally effect - increases damage output

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage.Modules.Types.Enums)
local EffectTypes = require(game.ServerStorage.Modules.Types.EffectTypes)
local EffectBase = require(game.ServerStorage.Modules.BaseClasses.EffectBase)

-- Export the effect definition
return EffectBase.Buff:define({
    id = Enums.EffectId.Rally,
    name = "Rally",
    duration = 15, -- 15 seconds
    maxStacks = 1,
    onApply = function(ctx: EffectTypes.EffectContext)
        -- Rally cry visual/audio feedback
    end,
    onRemove = function(ctx: EffectTypes.EffectContext)
        -- Cleanup
    end,
    compute = function(ctx: EffectTypes.EffectContext, accum: EffectTypes.Modifiers, stacks: number)
        -- Increase outgoing damage by 25%
        accum.outgoingDamageMult = (accum.outgoingDamageMult or 1) * 1.25
    end,
}) :: EffectTypes.EffectDef
