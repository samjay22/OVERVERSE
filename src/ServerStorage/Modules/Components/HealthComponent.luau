--!nonstrict
-- Health Component - Manages character health and death

local _Constants = require(game.ReplicatedStorage.Modules.Utility.Constants)

local HealthComponent = {}

function HealthComponent.Initialize(characterData, config)
    local stateManager = characterData.StateManager
    local humanoid = characterData.Humanoid
    
    -- Add re-entrancy protection flag
    characterData._healthUpdating = false
    
    -- Set up health state change handler
    stateManager:OnStateChange("Health", function(newHealth: any, oldHealth: any)
        if characterData._healthUpdating then return end
        
        characterData._healthUpdating = true
        humanoid.Health = newHealth
        characterData._healthUpdating = false
        
        -- Check for death
        if newHealth <= 0 and not stateManager:Get("IsDead") then
            HealthComponent._HandleDeath(characterData)
        end
        
        -- Health change effects could be added here
        if newHealth < oldHealth then
            local dmg = oldHealth - newHealth
            HealthComponent._OnDamage(characterData, dmg)
            if characterData.Signals and characterData.Signals.OnDamage then
                characterData.Signals.OnDamage:Fire(dmg, false)
            end
            stateManager:Set("LastDamage", dmg)
        end
    end)
    
    stateManager:OnStateChange("MaxHealth", function(newMaxHealth: any)
        if characterData._healthUpdating then return end
        
        characterData._healthUpdating = true
        humanoid.MaxHealth = newMaxHealth
        -- Clamp current health to max
        local currentHealth = stateManager:Get("Health")
        if currentHealth > newMaxHealth then
            stateManager:Set("Health", newMaxHealth)
        end
        characterData._healthUpdating = false
    end)
    
    stateManager:OnStateChange("IsDead", function(isDead: any)
        if isDead then
            humanoid.PlatformStand = true
            -- Could add death animation here
        else
            humanoid.PlatformStand = false
        end
    end)
    
    -- Set up humanoid health changed connection with re-entrancy protection
    local connection = humanoid.HealthChanged:Connect(function(newHealth: number)
        if not stateManager:Get("IsDead") and not characterData._healthUpdating then
            characterData._healthUpdating = true
            stateManager:Set("Health", newHealth)
            characterData._healthUpdating = false
        end
    end)
    table.insert(characterData._connections, connection)
    -- Set up humanoid died connection
    local diedConnection = humanoid.Died:Connect(function()
        HealthComponent._HandleDeath(characterData)
    end)
    table.insert(characterData._connections, diedConnection)
end

function HealthComponent._HandleDeath(characterData)
    local stateManager = characterData.StateManager
    if stateManager:Get("IsDead") then return end
    
    stateManager:Set("IsDead", true)
    stateManager:Set("Health", 0)
    
    -- Fire character-level death signal if provided
    local signals = characterData.Signals
    if signals and signals.OnDeath then
        signals.OnDeath:Fire()
    end
end

function HealthComponent._OnDamage(characterData, damage: number)
    -- Could add damage effects, sounds, etc.
    local stateManager = characterData.StateManager
    
    -- Example: Stun on heavy damage
    local maxHealth = stateManager:Get("MaxHealth") or 100
    if damage >= maxHealth * 0.3 then -- 30% of max health
        stateManager:Set("IsStunned", true)
        
        -- Remove stun after delay
        task.spawn(function()
            task.wait(1)
            if not stateManager:Get("IsDead") then
                stateManager:Set("IsStunned", false)
            end
        end)
    end
end

function HealthComponent.Update(characterData, dt: number)
    -- Health regeneration could be added here
    local stateManager = characterData.StateManager
    
    if stateManager:Get("IsDead") then return end
    
    -- Note: Constants.REGEN_RATES.Health doesn't exist in current constants
    -- This would need to be implemented if health regeneration is desired
    --[[
    local regenRates = Constants.REGEN_RATES
    if regenRates and regenRates.Health then
        local currentHealth = stateManager:Get("Health") or 0
        local maxHealth = stateManager:Get("MaxHealth") or 100
        
        if currentHealth < maxHealth and currentHealth > 0 then
            local regenAmount = regenRates.Health.regenRate * dt
            local newHealth = math.min(maxHealth, currentHealth + regenAmount)
            stateManager:Set("Health", newHealth)
        end
    end
    --]]
end

function HealthComponent.Cleanup(characterData)
    -- No specific cleanup needed, connections are handled by CharacterManager
end

return HealthComponent