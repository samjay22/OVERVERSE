--!strict
-- Combat Component - Manages character combat mechanics

local BaseComponent = require(script.Parent.BaseComponent)
local CombatService = require(game.ServerStorage.Modules.Services.CombatService)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

type CombatComponentData = {
    Service: any,
    AttackCooldown: number,
    BlockCooldown: number,
    ComboCount: number,
    LastAttackTime: number,
    IsBlocking: boolean,
    BlockEfficiency: number,
    DamageMultiplier: number,
}

export type CombatComponent = BaseComponent.BaseComponent & {
    PerformAttack: (self: CombatComponent, characterData: CharacterTypes.internalCharacter, attackType: string?) -> boolean,
    PerformBlock: (self: CombatComponent, characterData: CharacterTypes.internalCharacter, shouldBlock: boolean) -> boolean,
    TakeDamage: (self: CombatComponent, characterData: CharacterTypes.internalCharacter, damage: number, canBlock: boolean?) -> number,
    ApplyDamage: (self: CombatComponent, attackerCharacter: CharacterTypes.internalCharacter, targetCharacter: CharacterTypes.internalCharacter, baseDamage: number, canBlock: boolean?) -> number,
    GetEventBus: (self: CombatComponent, characterData: CharacterTypes.internalCharacter) -> any,
    ResetCombo: (self: CombatComponent, characterData: CharacterTypes.internalCharacter) -> (),
    GetComboCount: (self: CombatComponent, characterData: CharacterTypes.internalCharacter) -> number,
}

local COMBO_TIMEOUT = 2 -- Seconds before combo resets
local BASE_BLOCK_EFFICIENCY = 0.5 -- 50% damage reduction when blocking

local CombatComponent = BaseComponent:extend("Combat") :: any

function CombatComponent:Initialize(characterData: CharacterTypes.internalCharacter, config: any?)
    BaseComponent.Initialize(self, characterData, config)
    
    local service = CombatService.New()
    
    local componentData: CombatComponentData = {
        Service = service,
        AttackCooldown = 0,
        BlockCooldown = 0,
        ComboCount = 0,
        LastAttackTime = 0,
        IsBlocking = false,
        BlockEfficiency = config and config.BlockEfficiency or BASE_BLOCK_EFFICIENCY,
        DamageMultiplier = config and config.DamageMultiplier or 1,
    }
    
    characterData.Components.Combat = componentData :: any
    
    -- Initialize state manager values
    characterData.StateManager:Set("IsBlocking", false)
    characterData.StateManager:Set("ComboCount", 0)
    characterData.StateManager:Set("CanAttack", true)
    
    service:Initialize(characterData, config)
end

function CombatComponent:Update(characterData: CharacterTypes.internalCharacter, dt: number)
    if not self:IsEnabled(characterData) then
        return
    end
    
    local component = characterData.Components.Combat :: CombatComponentData
    if not component then
        return
    end
    
    -- Update cooldowns
    if component.AttackCooldown > 0 then
        component.AttackCooldown = math.max(0, component.AttackCooldown - dt)
        characterData.StateManager:Set("CanAttack", component.AttackCooldown <= 0)
    end
    
    if component.BlockCooldown > 0 then
        component.BlockCooldown = math.max(0, component.BlockCooldown - dt)
    end
    
    -- Reset combo if timeout reached
    local currentTime = tick()
    if component.ComboCount > 0 and (currentTime - component.LastAttackTime) > COMBO_TIMEOUT then
        self:ResetCombo(characterData)
    end
    
    -- Update service
    if component.Service then
        component.Service:Update(characterData, dt)
    end
end

function CombatComponent:Cleanup(characterData: CharacterTypes.internalCharacter)
    local component = characterData.Components.Combat :: CombatComponentData
    if component and component.Service then
        if component.Service.Cleanup then
            component.Service:Cleanup(characterData)
        end
    end
    
    BaseComponent.Cleanup(self, characterData)
end

function CombatComponent:PerformAttack(characterData: CharacterTypes.internalCharacter, attackType: string?): boolean
    if not self:IsEnabled(characterData) then
        return false
    end
    
    local component = characterData.Components.Combat :: CombatComponentData
    if not component or component.AttackCooldown > 0 then
        return false
    end
    
    -- Check if stunned or other conditions
    local isStunned = characterData.StateManager:Get("IsStunned")
    if isStunned then
        return false
    end
    
    local success = false
    if component.Service then
        success = component.Service:PerformAttack(characterData, attackType)
    end
    
    if success then
        component.ComboCount = component.ComboCount + 1
        component.LastAttackTime = tick()
        component.AttackCooldown = 0.5 -- Default cooldown, can be adjusted
        
        characterData.StateManager:Set("ComboCount", component.ComboCount)
        characterData.StateManager:Set("CanAttack", false)
    end
    
    return success
end

function CombatComponent:PerformBlock(characterData: CharacterTypes.internalCharacter, shouldBlock: boolean): boolean
    if not self:IsEnabled(characterData) then
        return false
    end
    
    local component = characterData.Components.Combat :: CombatComponentData
    if not component then
        return false
    end
    
    if shouldBlock and component.BlockCooldown > 0 then
        return false
    end
    
    local success = false
    if component.Service then
        success = component.Service:PerformBlock(characterData, shouldBlock)
    end
    
    if success then
        component.IsBlocking = shouldBlock
        characterData.StateManager:Set("IsBlocking", shouldBlock)
        
        if not shouldBlock then
            component.BlockCooldown = 0.3 -- Small cooldown after releasing block
        end
    end
    
    return success
end

function CombatComponent:TakeDamage(characterData: CharacterTypes.internalCharacter, damage: number, canBlock: boolean?): number
    if not self:IsEnabled(characterData) then
        return 0
    end
    
    local component = characterData.Components.Combat :: CombatComponentData
    if not component then
        return 0
    end
    
    local actualDamage = damage
    
    -- Apply block reduction if applicable
    if canBlock ~= false and component.IsBlocking then
        actualDamage = damage * (1 - component.BlockEfficiency)
        
        -- Trigger block effect
        if characterData.Signals and characterData.Signals.OnBlock then
            characterData.Signals.OnBlock:Fire(damage - actualDamage)
        end
    end
    
    if component.Service then
        actualDamage = component.Service:TakeDamage(characterData, actualDamage, canBlock)
    end
    
    return actualDamage
end

function CombatComponent:ApplyDamage(attackerCharacter: CharacterTypes.internalCharacter, targetCharacter: CharacterTypes.internalCharacter, baseDamage: number, canBlock: boolean?): number
    local attackerComponent = attackerCharacter.Components.Combat :: CombatComponentData
    if not attackerComponent or not attackerComponent.Service then
        return 0
    end
    
    -- Apply attacker's damage multiplier
    local modifiedDamage = baseDamage * (attackerComponent.DamageMultiplier or 1)
    
    -- Apply combo multiplier
    local comboMultiplier = 1 + (attackerComponent.ComboCount * 0.1) -- 10% increase per combo
    modifiedDamage = modifiedDamage * comboMultiplier
    
    return attackerComponent.Service:ApplyDamage(attackerCharacter, targetCharacter, modifiedDamage, canBlock)
end

function CombatComponent:GetEventBus(characterData: CharacterTypes.internalCharacter)
    local component = characterData.Components.Combat :: CombatComponentData
    if component and component.Service then
        -- Access service's internal event bus if available
        local service = component.Service :: any
        if service._buses and characterData.PlayerId then
            return service._buses[characterData.PlayerId]
        end
    end
    return nil
end

function CombatComponent:ResetCombo(characterData: CharacterTypes.internalCharacter)
    local component = characterData.Components.Combat :: CombatComponentData
    if component then
        component.ComboCount = 0
        characterData.StateManager:Set("ComboCount", 0)
    end
end

function CombatComponent:GetComboCount(characterData: CharacterTypes.internalCharacter): number
    local component = characterData.Components.Combat :: CombatComponentData
    return component and component.ComboCount or 0
end

-- Create singleton instance for backward compatibility
local instance = CombatComponent.new()

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
    
    PerformAttack = function(characterData, attackType)
        return instance:PerformAttack(characterData, attackType)
    end,
    
    PerformBlock = function(characterData, shouldBlock)
        return instance:PerformBlock(characterData, shouldBlock)
    end,
    
    TakeDamage = function(characterData, damage, canBlock)
        return instance:TakeDamage(characterData, damage, canBlock)
    end,
    
    ApplyDamage = function(attackerCharacter, targetCharacter, baseDamage, canBlock)
        return instance:ApplyDamage(attackerCharacter, targetCharacter, baseDamage, canBlock)
    end,
    
    GetEventBus = function(characterData)
        return instance:GetEventBus(characterData)
    end,
    
    ResetCombo = function(characterData)
        return instance:ResetCombo(characterData)
    end,
    
    GetComboCount = function(characterData)
        return instance:GetComboCount(characterData)
    end,
}

return exports