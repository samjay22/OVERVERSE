--!strict
-- Health Component - Manages character health and death

local StateHelpers = require(game.ServerStorage.Modules.Types.CharacterStateTypes)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

export type HealthComponent = {
    Initialize: (characterData: CharacterTypes.internalCharacter, config: any?) -> (),
    Update: (characterData: CharacterTypes.internalCharacter, dt: number) -> (),
    Cleanup: (characterData: CharacterTypes.internalCharacter) -> (),
}

local HealthComponent = {}

function HealthComponent.Initialize(characterData: CharacterTypes.internalCharacter, config: any?)
    local stateManager = characterData.StateManager
    local humanoid = characterData.Humanoid
    
    -- Add re-entrancy protection flag
    local char = characterData :: any
    char._healthUpdating = false
    
    -- Set up health state change handler
    stateManager:OnStateChange("Health", function(newHealth, oldHealth)
        if char._healthUpdating then return end
        
        char._healthUpdating = true
        local healthValue = StateHelpers.asNumber(newHealth, 100)
        humanoid.Health = healthValue
        char._healthUpdating = false
        
        -- Check for death
        local isDead = StateHelpers.asBoolean(stateManager:Get("IsDead"), false)
        if healthValue <= 0 and not isDead then
            HealthComponent._HandleDeath(characterData)
        end
        
        -- Health change effects could be added here
        local oldHealthValue = StateHelpers.asNumber(oldHealth, 100)
        if healthValue < oldHealthValue then
            local dmg = oldHealthValue - healthValue
            HealthComponent._OnDamage(characterData, dmg)
            if characterData.Signals and characterData.Signals.OnDamage then
                characterData.Signals.OnDamage:Fire(dmg, false)
            end
            stateManager:Set("LastDamage", dmg)
        end
    end)
    
    stateManager:OnStateChange("MaxHealth", function(newMaxHealth, _oldMaxHealth)
        if char._healthUpdating then return end
        
        char._healthUpdating = true
        local maxHealthValue = StateHelpers.asNumber(newMaxHealth, 100)
        humanoid.MaxHealth = maxHealthValue
        -- Clamp current health to max
        local currentHealth = StateHelpers.asNumber(stateManager:Get("Health"), 100)
        if currentHealth > maxHealthValue then
            stateManager:Set("Health", maxHealthValue)
        end
        char._healthUpdating = false
    end)
    
    stateManager:OnStateChange("IsDead", function(isDead, _oldIsDead)
        local isDeadValue = StateHelpers.asBoolean(isDead, false)
        if isDeadValue then
            humanoid.PlatformStand = true
            -- Could add death animation here
        else
            humanoid.PlatformStand = false
        end
    end)
    
    -- Set up humanoid health changed connection with re-entrancy protection
    local connection = humanoid.HealthChanged:Connect(function(newHealth: number)
        local isDead = StateHelpers.asBoolean(stateManager:Get("IsDead"), false)
        if not isDead and not char._healthUpdating then
            char._healthUpdating = true
            stateManager:Set("Health", newHealth)
            char._healthUpdating = false
        end
    end)
    table.insert(characterData._connections, connection)
    -- Set up humanoid died connection
    local diedConnection = humanoid.Died:Connect(function()
        HealthComponent._HandleDeath(characterData)
    end)
    table.insert(characterData._connections, diedConnection)
end

function HealthComponent._HandleDeath(characterData: CharacterTypes.internalCharacter)
    local stateManager = characterData.StateManager
    local isDead = StateHelpers.asBoolean(stateManager:Get("IsDead"), false)
    if isDead then return end
    
    stateManager:Set("IsDead", true)
    stateManager:Set("Health", 0)
    
    -- Fire character-level death signal if provided
    local signals = characterData.Signals
    if signals and signals.OnDeath then
        signals.OnDeath:Fire()
    end
end

function HealthComponent._OnDamage(characterData: CharacterTypes.internalCharacter, damage: number)
    -- Could add damage effects, sounds, etc.
    local stateManager = characterData.StateManager
    
    -- Example: Stun on heavy damage
    local maxHealth = StateHelpers.asNumber(stateManager:Get("MaxHealth"), 100)
    if damage >= maxHealth * 0.3 then -- 30% of max health
        stateManager:Set("IsStunned", true)
        
        -- Remove stun after delay
        task.spawn(function()
            task.wait(1)
            local isDead = StateHelpers.asBoolean(stateManager:Get("IsDead"), false)
            if not isDead then
                stateManager:Set("IsStunned", false)
            end
        end)
    end
end

function HealthComponent.Update(characterData: CharacterTypes.internalCharacter, dt: number)
    -- Health regeneration could be added here
    local stateManager = characterData.StateManager
    
    local isDead = StateHelpers.asBoolean(stateManager:Get("IsDead"), false)
    if isDead then return end
    
    -- Note: Constants.REGEN_RATES.Health doesn't exist in current constants
    -- This would need to be implemented if health regeneration is desired
    --[[
    local regenRates = Constants.REGEN_RATES
    if regenRates and regenRates.Health then
        local currentHealth = StateHelpers.asNumber(stateManager:Get("Health"), 0)
        local maxHealth = StateHelpers.asNumber(stateManager:Get("MaxHealth"), 100)
        
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