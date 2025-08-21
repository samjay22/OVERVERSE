--!strict
local EffectService = require(game.ServerStorage.Modules.Services.EffectService)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(game.ReplicatedStorage.Modules.Utility.Constants)

local _service = EffectService.New()

local EffectComponent = {}

function EffectComponent.Initialize(characterData, config)
    -- No-op on init; effects applied by weapons/abilities/passives
end

function EffectComponent.Update(characterData, dt: number)
    -- Cast to any to avoid cross-module structural type noise
    (_service :: any):Tick(characterData, dt)

    -- Compute aggregated modifiers, then project them into character state
    local mods = (_service :: any):ComputeModifiers(characterData) or {}
    local sm = characterData.StateManager

    -- Defaults from constants
    local defs = Constants.CHARACTER_STATE_DEFINITIONS
    local function defOf(k)
        local d = defs and defs[k]
        return d and d.default
    end

    -- Build a patch table and set atomically
    local patch = {
        OutgoingDamageMult = mods.outgoingDamageMult or defOf("OutgoingDamageMult") or 1,
        IncomingDamageMult = mods.incomingDamageMult or defOf("IncomingDamageMult") or 1,
        StaminaCostMult = mods.staminaCostMult or defOf("StaminaCostMult") or 1,
        AttackCooldownMult = mods.attackCooldownMult or defOf("AttackCooldownMult") or 1,
        GuardRegenMult = mods.guardRegenMult or defOf("GuardRegenMult") or 1,
        StaminaRegenBonus = mods.staminaRegenBonus or defOf("StaminaRegenBonus") or 0,
        CritChance = mods.critChance or defOf("CritChance") or 0,
        CritDamage = mods.critDamage or defOf("CritDamage") or 0,
    }

    -- Push state (StateManager may no-op on unchanged values)
    if sm and sm.SetMultiple then
        sm:SetMultiple(patch)
    else
        for k, v in pairs(patch) do
            sm:Set(k, v)
        end
    end
end

function EffectComponent.Cleanup(characterData)
    -- Clear all active effects on cleanup/death so stacks reset
    (_service :: any):ClearAll(characterData)
end

function EffectComponent.GetService()
    return _service
end

return EffectComponent
