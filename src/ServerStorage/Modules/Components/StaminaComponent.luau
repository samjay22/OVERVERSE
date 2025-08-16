--!strict
-- Stamina Component - Manages character stamina and exhaustion

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Modules.Utility.Constants)

local StaminaComponent = {}

function StaminaComponent.Initialize(characterData, config)
    local stateManager = characterData.StateManager
    
    -- Set up stamina state change handlers
    stateManager:OnStateChange("Stamina", function(newStamina: number)
        -- Force stop running if stamina depleted
        if newStamina <= 0 and stateManager:Get("IsRunning") then
            stateManager:Set("IsRunning", false)
        end
        
        -- Handle exhaustion
        if newStamina <= 0 and not stateManager:Get("IsStunned") then
            StaminaComponent._HandleExhaustion(characterData)
        end
    end)
    
    stateManager:OnStateChange("MaxStamina", function(newMaxStamina: number)
        -- Clamp current stamina to max
        local currentStamina = stateManager:Get("Stamina")
        if currentStamina > newMaxStamina then
            stateManager:Set("Stamina", newMaxStamina)
        end
    end)
end

function StaminaComponent._HandleExhaustion(characterData)
    local stateManager = characterData.StateManager
    
    -- Apply brief stun from exhaustion
    stateManager:Set("IsStunned", true)
    
    -- Remove exhaustion stun after delay
    task.spawn(function()
        task.wait(0.5) -- Brief exhaustion stun
        if not stateManager:Get("IsDead") then
            stateManager:Set("IsStunned", false)
        end
    end)
end

function StaminaComponent.Update(characterData, dt: number)
    local stateManager = characterData.StateManager
    
    if stateManager:Get("IsDead") or stateManager:Get("IsStunned") then
        return
    end
    
    local regenRates = Constants.REGEN_RATES or {
        Stamina = {regenRate = 10, depleteRate = 20}
    }
    
    local stamina = stateManager:Get("Stamina")
    local maxStamina = stateManager:Get("MaxStamina")
    local isRunning = stateManager:Get("IsRunning")
    local isBlocking = stateManager:Get("IsBlocking")
    
    local staminaChange = 0
    
    -- Stamina depletion
    if isRunning then
        staminaChange = -dt * regenRates.Stamina.depleteRate
    elseif isBlocking then
        -- Blocking drains stamina slower
        staminaChange = -dt * (regenRates.Stamina.depleteRate * 0.3)
    elseif stamina < maxStamina then
        -- Stamina regeneration
        staminaChange = dt * regenRates.Stamina.regenRate
    end
    
    if staminaChange ~= 0 then
        local newStamina = math.clamp(stamina + staminaChange, 0, maxStamina)
        stateManager:Set("Stamina", newStamina)
    end
end

function StaminaComponent.Cleanup(characterData)
    -- No specific cleanup needed
end

return StaminaComponent