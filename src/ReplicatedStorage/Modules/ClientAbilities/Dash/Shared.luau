--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local Config = require(script.Parent.Config)

local Shared = {}

function Shared.IsValid(ctx: Types.SharedAbilityContext): boolean
    -- Basic validation for healing ability
    if not ctx or not ctx.inputData then
        return false
    end
    
    -- Must have target position for healing
    if not ctx.inputData.target then
        return false
    end
    
    return true
end

function Shared.GetConfig(): Types.AbilityConfig
    return {
        ABILITY_CATEGORY = Config.ABILITY_CATEGORY,
        REQUIRES_TARGET = Config.REQUIRES_TARGET,
        COOLDOWN_TIME = Config.COOLDOWN_TIME,
        ATTACK_RANGE = Config.ATTACK_RANGE,
        HEAL_AMOUNT = Config.HEAL_AMOUNT,
        MANA_COST = Config.MANA_COST,
    }
end

function Shared.GetAssets(): Folder
    return script.Parent.Assets
end

return Shared