--!strict
-- Stamina Component - Manages character stamina and exhaustion

local BaseComponent = require(script.Parent.BaseComponent)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)
local Constants = require(game.ReplicatedStorage.Modules.Utility.Constants)

type StaminaComponentData = {
    CurrentStamina: number,
    MaxStamina: number,
    RegenRate: number,
    DepleteRate: number,
    LastUpdateTime: number,
    IsRegenerating: boolean,
    ExhaustionThreshold: number,
    ExhaustionCooldown: number,
}

export type StaminaComponent = BaseComponent.BaseComponent & {
    ConsumeStamina: (self: StaminaComponent, characterData: CharacterTypes.internalCharacter, amount: number) -> boolean,
    RestoreStamina: (self: StaminaComponent, characterData: CharacterTypes.internalCharacter, amount: number) -> number,
    SetStamina: (self: StaminaComponent, characterData: CharacterTypes.internalCharacter, stamina: number) -> (),
    SetMaxStamina: (self: StaminaComponent, characterData: CharacterTypes.internalCharacter, maxStamina: number) -> (),
    GetStamina: (self: StaminaComponent, characterData: CharacterTypes.internalCharacter) -> number,
    GetMaxStamina: (self: StaminaComponent, characterData: CharacterTypes.internalCharacter) -> number,
    GetStaminaPercent: (self: StaminaComponent, characterData: CharacterTypes.internalCharacter) -> number,
    HasStamina: (self: StaminaComponent, characterData: CharacterTypes.internalCharacter, amount: number) -> boolean,
}

local DEFAULT_REGEN_RATE = 10
local DEFAULT_DEPLETE_RATE = 20
local EXHAUSTION_THRESHOLD = 5 -- Stamina level that triggers exhaustion
local EXHAUSTION_STUN_DURATION = 0.5

local StaminaComponent = BaseComponent:extend("Stamina") :: any

function StaminaComponent:Initialize(characterData: CharacterTypes.internalCharacter, config: any?)
    BaseComponent.Initialize(self, characterData, config)
    local stateManager = characterData.StateManager
    
    local regenRates = Constants.REGEN_RATES or {
        Stamina = {regenRate = DEFAULT_REGEN_RATE, depleteRate = DEFAULT_DEPLETE_RATE}
    }
    
    local componentData: StaminaComponentData = {
        CurrentStamina = config and config.Stamina or 100,
        MaxStamina = config and config.MaxStamina or 100,
        RegenRate = config and config.StaminaRegenRate or regenRates.Stamina.regenRate,
        DepleteRate = config and config.StaminaDepleteRate or regenRates.Stamina.depleteRate,
        LastUpdateTime = tick(),
        IsRegenerating = true,
        ExhaustionThreshold = EXHAUSTION_THRESHOLD,
        ExhaustionCooldown = 0,
    }
    
    characterData.Components.Stamina = componentData :: any
    
    -- Initialize state values
    stateManager:Set("Stamina", componentData.CurrentStamina)
    stateManager:Set("MaxStamina", componentData.MaxStamina)
    
    -- Set up stamina state change handlers
    stateManager:OnStateChange("Stamina", function(newStamina: number)
        local component = characterData.Components.Stamina :: StaminaComponentData
        if component then
            component.CurrentStamina = newStamina
            
            -- Force stop running if stamina depleted
            if newStamina <= 0 and stateManager:Get("IsRunning") then
                stateManager:Set("IsRunning", false)
            end
            
            -- Handle exhaustion
            if newStamina <= component.ExhaustionThreshold and not stateManager:Get("IsStunned") then
                self:_HandleExhaustion(characterData)
            end
        end
    end)
    
    stateManager:OnStateChange("MaxStamina", function(newMaxStamina: number)
        local component = characterData.Components.Stamina :: StaminaComponentData
        if component then
            component.MaxStamina = newMaxStamina
            
            -- Clamp current stamina to max
            if component.CurrentStamina > newMaxStamina then
                self:SetStamina(characterData, newMaxStamina)
            end
        end
    end)
end

function StaminaComponent:_HandleExhaustion(characterData: CharacterTypes.internalCharacter)
    local stateManager = characterData.StateManager
    
    local component = characterData.Components.Stamina :: StaminaComponentData
    if not component or component.ExhaustionCooldown > 0 then
        return
    end
    
    -- Apply brief stun from exhaustion
    stateManager:Set("IsStunned", true)
    component.ExhaustionCooldown = EXHAUSTION_STUN_DURATION
    
    -- Remove exhaustion stun after delay
    task.spawn(function()
        task.wait(EXHAUSTION_STUN_DURATION)
        if not stateManager:Get("IsDead") then
            stateManager:Set("IsStunned", false)
        end
    end)
end

function StaminaComponent:Update(characterData: CharacterTypes.internalCharacter, dt: number)
    if not self:IsEnabled(characterData) then
        return
    end
    
    local component = characterData.Components.Stamina :: StaminaComponentData
    if not component then
        return
    end
    local stateManager = characterData.StateManager
    
    -- Update exhaustion cooldown
    if component.ExhaustionCooldown > 0 then
        component.ExhaustionCooldown = math.max(0, component.ExhaustionCooldown - dt)
    end
    
    if stateManager:Get("IsDead") or stateManager:Get("IsStunned") then
        return
    end
    
    local stamina = component.CurrentStamina
    local maxStamina = component.MaxStamina
    local isRunning = stateManager:Get("IsRunning") :: boolean
    local isBlocking = stateManager:Get("IsBlocking") :: boolean
    
    local staminaChange = 0
    
    -- Stamina depletion/regeneration calculations
    if isRunning then
        staminaChange = -dt * component.DepleteRate
        component.IsRegenerating = false
    elseif isBlocking then
        -- Blocking drains stamina slower
        staminaChange = -dt * (component.DepleteRate * 0.3)
        component.IsRegenerating = false
    elseif stamina < maxStamina then
        -- Stamina regeneration
        staminaChange = dt * component.RegenRate
        component.IsRegenerating = true
    end
    
    -- Only update if there's a meaningful change (avoid micro-updates)
    if math.abs(staminaChange) > 0.01 then
        local newStamina = math.clamp(stamina + staminaChange, 0, maxStamina)
        -- Only set if the change is significant enough to matter
        if math.abs(newStamina - stamina) > 0.1 then
            self:SetStamina(characterData, newStamina)
        end
    end
end

function StaminaComponent:Cleanup(characterData: CharacterTypes.internalCharacter)
    BaseComponent.Cleanup(self, characterData)
end

function StaminaComponent:ConsumeStamina(characterData: CharacterTypes.internalCharacter, amount: number): boolean
    local component = characterData.Components.Stamina :: StaminaComponentData
    if not component then
        return false
    end
    
    if component.CurrentStamina >= amount then
        self:SetStamina(characterData, component.CurrentStamina - amount)
        component.IsRegenerating = false
        return true
    end
    
    return false
end

function StaminaComponent:RestoreStamina(characterData: CharacterTypes.internalCharacter, amount: number): number
    local component = characterData.Components.Stamina :: StaminaComponentData
    if not component then
        return 0
    end
    
    local currentStamina = component.CurrentStamina
    local maxStamina = component.MaxStamina
    local actualRestore = math.min(amount, maxStamina - currentStamina)
    
    if actualRestore > 0 then
        self:SetStamina(characterData, currentStamina + actualRestore)
    end
    
    return actualRestore
end

function StaminaComponent:SetStamina(characterData: CharacterTypes.internalCharacter, stamina: number)
    local component = characterData.Components.Stamina :: StaminaComponentData
    if component then
        component.CurrentStamina = math.clamp(stamina, 0, component.MaxStamina)
        characterData.StateManager:Set("Stamina", component.CurrentStamina)
    end
end

function StaminaComponent:SetMaxStamina(characterData: CharacterTypes.internalCharacter, maxStamina: number)
    local component = characterData.Components.Stamina :: StaminaComponentData
    if component then
        component.MaxStamina = maxStamina
        characterData.StateManager:Set("MaxStamina", maxStamina)
        
        -- Clamp current stamina if needed
        if component.CurrentStamina > maxStamina then
            self:SetStamina(characterData, maxStamina)
        end
    end
end

function StaminaComponent:GetStamina(characterData: CharacterTypes.internalCharacter): number
    local component = characterData.Components.Stamina :: StaminaComponentData
    return component and component.CurrentStamina or 0
end

function StaminaComponent:GetMaxStamina(characterData: CharacterTypes.internalCharacter): number
    local component = characterData.Components.Stamina :: StaminaComponentData
    return component and component.MaxStamina or 100
end

function StaminaComponent:GetStaminaPercent(characterData: CharacterTypes.internalCharacter): number
    local stamina = self:GetStamina(characterData)
    local maxStamina = self:GetMaxStamina(characterData)
    return maxStamina > 0 and (stamina / maxStamina) or 0
end

function StaminaComponent:HasStamina(characterData: CharacterTypes.internalCharacter, amount: number): boolean
    return self:GetStamina(characterData) >= amount
end

-- Create singleton instance for backward compatibility
local instance = StaminaComponent.new()

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
}

return exports