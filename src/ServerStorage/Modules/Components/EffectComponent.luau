--!strict
-- Effect Component - Manages character effects and modifiers

local BaseComponent = require(script.Parent.BaseComponent)
local EffectService = require(game.ServerStorage.Modules.Services.EffectService)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)
local Constants = require(game.ReplicatedStorage.Modules.Utility.Constants)

type ActiveEffect = {
    Id: string,
    Name: string,
    Duration: number?,
    Stacks: number,
    Source: string?,
    AppliedAt: number,
    Modifiers: {[string]: number},
}

type EffectComponentData = {
    Service: any,
    ActiveEffects: {[string]: ActiveEffect},
    ModifierCache: {[string]: number},
    LastUpdateTime: number,
}

export type EffectComponent = BaseComponent.BaseComponent & {
    ApplyEffect: (self: EffectComponent, characterData: CharacterTypes.internalCharacter, effectName: string, duration: number?, source: string?) -> boolean,
    RemoveEffect: (self: EffectComponent, characterData: CharacterTypes.internalCharacter, effectId: string) -> boolean,
    ClearAllEffects: (self: EffectComponent, characterData: CharacterTypes.internalCharacter) -> (),
    GetActiveEffects: (self: EffectComponent, characterData: CharacterTypes.internalCharacter) -> {[string]: ActiveEffect},
    GetModifier: (self: EffectComponent, characterData: CharacterTypes.internalCharacter, modifierName: string) -> number,
    HasEffect: (self: EffectComponent, characterData: CharacterTypes.internalCharacter, effectName: string) -> boolean,
    GetService: (self: EffectComponent) -> any,
}

local MODIFIER_DEFAULTS = {
    OutgoingDamageMult = 1,
    IncomingDamageMult = 1,
    StaminaCostMult = 1,
    AttackCooldownMult = 1,
    GuardRegenMult = 1,
    StaminaRegenBonus = 0,
    CritChance = 0,
    CritDamage = 0,
    MovementSpeedMult = 1,
    JumpPowerMult = 1,
}

local EffectComponent = BaseComponent:extend("Effect") :: any

function EffectComponent:Initialize(characterData: CharacterTypes.internalCharacter, config: any?)
    BaseComponent.Initialize(self, characterData, config)
    
    local service = EffectService.New()
    
    local componentData: EffectComponentData = {
        Service = service,
        ActiveEffects = {},
        ModifierCache = table.clone(MODIFIER_DEFAULTS),
        LastUpdateTime = tick(),
    }
    
    characterData.Components.Effect = componentData :: any
    
    -- Initialize modifiers in state manager
    for modifier, defaultValue in pairs(MODIFIER_DEFAULTS) do
        characterData.StateManager:Set(modifier, defaultValue)
    end
    
    -- Effects are applied by weapons/abilities/passives after initialization
end

function EffectComponent:Update(characterData: CharacterTypes.internalCharacter, dt: number)
    if not self:IsEnabled(characterData) then
        return
    end
    
    local component = characterData.Components.Effect :: EffectComponentData
    if not component then
        return
    end
    
    -- Update service
    if component.Service then
        component.Service:Tick(characterData, dt)
    end
    
    -- Update active effects durations
    local currentTime = tick()
    local effectsToRemove = {}
    
    for effectId, effect in pairs(component.ActiveEffects) do
        if effect.Duration then
            effect.Duration = effect.Duration - dt
            if effect.Duration <= 0 then
                table.insert(effectsToRemove, effectId)
            end
        end
    end
    
    -- Remove expired effects
    for _, effectId in ipairs(effectsToRemove) do
        self:RemoveEffect(characterData, effectId)
    end
    
    -- Compute and apply modifiers
    self:_UpdateModifiers(characterData)
end

function EffectComponent:Cleanup(characterData: CharacterTypes.internalCharacter)
    self:ClearAllEffects(characterData)
    
    local component = characterData.Components.Effect :: EffectComponentData
    if component and component.Service then
        if component.Service.Cleanup then
            component.Service:Cleanup(characterData)
        end
    end
    
    BaseComponent.Cleanup(self, characterData)
end

function EffectComponent:ApplyEffect(characterData: CharacterTypes.internalCharacter, effectName: string, duration: number?, source: string?): boolean
    if not self:IsEnabled(characterData) then
        return false
    end
    
    local component = characterData.Components.Effect :: EffectComponentData
    if not component then
        return false
    end
    
    -- Generate unique effect ID
    local effectId = effectName .. "_" .. tostring(tick())
    
    -- Create effect instance
    local effect: ActiveEffect = {
        Id = effectId,
        Name = effectName,
        Duration = duration,
        Stacks = 1,
        Source = source,
        AppliedAt = tick(),
        Modifiers = {},
    }
    
    -- Check for stacking
    for existingId, existingEffect in pairs(component.ActiveEffects) do
        if existingEffect.Name == effectName and existingEffect.Source == source then
            existingEffect.Stacks = existingEffect.Stacks + 1
            existingEffect.Duration = duration or existingEffect.Duration
            self:_UpdateModifiers(characterData)
            return true
        end
    end
    
    component.ActiveEffects[effectId] = effect
    
    -- Notify state manager
    local activeEffectNames = {}
    for _, activeEffect in pairs(component.ActiveEffects) do
        table.insert(activeEffectNames, activeEffect.Name)
    end
    characterData.StateManager:Set("ActiveEffects", activeEffectNames)
    
    self:_UpdateModifiers(characterData)
    return true
end

function EffectComponent:RemoveEffect(characterData: CharacterTypes.internalCharacter, effectId: string): boolean
    local component = characterData.Components.Effect :: EffectComponentData
    if not component or not component.ActiveEffects[effectId] then
        return false
    end
    
    component.ActiveEffects[effectId] = nil
    
    -- Update state manager
    local activeEffectNames = {}
    for _, effect in pairs(component.ActiveEffects) do
        table.insert(activeEffectNames, effect.Name)
    end
    characterData.StateManager:Set("ActiveEffects", activeEffectNames)
    
    self:_UpdateModifiers(characterData)
    return true
end

function EffectComponent:ClearAllEffects(characterData: CharacterTypes.internalCharacter)
    local component = characterData.Components.Effect :: EffectComponentData
    if not component then
        return
    end
    
    component.ActiveEffects = {}
    component.ModifierCache = table.clone(MODIFIER_DEFAULTS)
    
    -- Clear from service
    if component.Service and component.Service.ClearAll then
        component.Service:ClearAll(characterData)
    end
    
    -- Reset modifiers in state manager
    for modifier, defaultValue in pairs(MODIFIER_DEFAULTS) do
        characterData.StateManager:Set(modifier, defaultValue)
    end
    
    characterData.StateManager:Set("ActiveEffects", {})
end

function EffectComponent:GetActiveEffects(characterData: CharacterTypes.internalCharacter): {[string]: ActiveEffect}
    local component = characterData.Components.Effect :: EffectComponentData
    return component and component.ActiveEffects or {}
end

function EffectComponent:GetModifier(characterData: CharacterTypes.internalCharacter, modifierName: string): number
    local component = characterData.Components.Effect :: EffectComponentData
    if not component then
        return MODIFIER_DEFAULTS[modifierName] or 0
    end
    
    return component.ModifierCache[modifierName] or MODIFIER_DEFAULTS[modifierName] or 0
end

function EffectComponent:HasEffect(characterData: CharacterTypes.internalCharacter, effectName: string): boolean
    local component = characterData.Components.Effect :: EffectComponentData
    if not component then
        return false
    end
    
    for _, effect in pairs(component.ActiveEffects) do
        if effect.Name == effectName then
            return true
        end
    end
    
    return false
end

function EffectComponent:GetService()
    -- Return a shared service instance for compatibility
    return EffectService.New()
end

function EffectComponent:_UpdateModifiers(characterData: CharacterTypes.internalCharacter)
    local component = characterData.Components.Effect :: EffectComponentData
    if not component then
        return
    end
    
    -- Compute aggregated modifiers from service
    local mods = {}
    if component.Service and component.Service.ComputeModifiers then
        mods = component.Service:ComputeModifiers(characterData) or {}
    end
    
    -- Get defaults from constants if available
    local defs = Constants.CHARACTER_STATE_DEFINITIONS
    local function getDefault(key: string)
        if defs and defs[key] then
            return defs[key].default
        end
        return MODIFIER_DEFAULTS[key]
    end
    
    -- Build modifier patch
    local patch = {}
    for modifier, _ in pairs(MODIFIER_DEFAULTS) do
        local modKey = modifier:sub(1, 1):lower() .. modifier:sub(2)
        patch[modifier] = mods[modKey] or getDefault(modifier) or MODIFIER_DEFAULTS[modifier]
    end
    
    -- Update cache
    component.ModifierCache = patch
    
    -- Push to state manager
    local sm = characterData.StateManager
    if sm.SetMultiple then
        sm:SetMultiple(patch)
    else
        for k, v in pairs(patch) do
            sm:Set(k, v)
        end
    end
end

-- Create singleton instance for backward compatibility
local instance = EffectComponent.new()

-- Export both instance methods and static interface for backward compatibility
local exports = {
    -- Instance (for new usage)
    Instance = instance,
    
    -- Static methods (for backward compatibility)
    Initialize = function(characterData, config)
        return instance:Initialize(characterData, config)
    end,
    
    Update = function(characterData, dt)
        return instance:Update(characterData, dt)
    end,
    
    Cleanup = function(characterData)
        return instance:Cleanup(characterData)
    end,
    
    GetService = function()
        return instance:GetService()
    end,
}

return exports
