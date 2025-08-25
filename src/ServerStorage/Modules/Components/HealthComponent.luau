--!strict
-- Health Component - Manages character health and death

local BaseComponent = require(script.Parent.BaseComponent)
local StateHelpers = require(game.ServerStorage.Modules.Types.CharacterStateTypes)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

type HealthComponentData = {
    CurrentHealth: number,
    MaxHealth: number,
    HealthRegen: number,
    LastDamageTime: number,
    LastHealTime: number,
    IsRegenerating: boolean,
    DamageReduction: number,
    _healthUpdating: boolean,
}

export type HealthComponent = BaseComponent.BaseComponent & {
    Damage: (self: HealthComponent, characterData: CharacterTypes.internalCharacter, amount: number, source: string?) -> number,
    Heal: (self: HealthComponent, characterData: CharacterTypes.internalCharacter, amount: number, source: string?) -> number,
    SetHealth: (self: HealthComponent, characterData: CharacterTypes.internalCharacter, health: number) -> (),
    SetMaxHealth: (self: HealthComponent, characterData: CharacterTypes.internalCharacter, maxHealth: number) -> (),
    GetHealth: (self: HealthComponent, characterData: CharacterTypes.internalCharacter) -> number,
    GetMaxHealth: (self: HealthComponent, characterData: CharacterTypes.internalCharacter) -> number,
    GetHealthPercent: (self: HealthComponent, characterData: CharacterTypes.internalCharacter) -> number,
    IsAlive: (self: HealthComponent, characterData: CharacterTypes.internalCharacter) -> boolean,
    Revive: (self: HealthComponent, characterData: CharacterTypes.internalCharacter, healthPercent: number?) -> (),
}

local HEALTH_REGEN_DELAY = 3 -- Seconds before health regen starts after damage
local DEFAULT_HEALTH_REGEN = 5 -- Health per second

local HealthComponent = BaseComponent:extend("Health") :: any

function HealthComponent:Initialize(characterData: CharacterTypes.internalCharacter, config: any?)
    BaseComponent.Initialize(self, characterData, config)
    
    local stateManager = characterData.StateManager
    local humanoid = characterData.Humanoid
    
    local componentData: HealthComponentData = {
        CurrentHealth = config and config.Health or 100,
        MaxHealth = config and config.MaxHealth or 100,
        HealthRegen = config and config.HealthRegen or DEFAULT_HEALTH_REGEN,
        LastDamageTime = 0,
        LastHealTime = 0,
        IsRegenerating = false,
        DamageReduction = config and config.DamageReduction or 0,
        _healthUpdating = false,
    }
    
    characterData.Components.Health = componentData :: any
    
    -- Set up health state change handler
    stateManager:OnStateChange("Health", function(newHealth, oldHealth)
        local component = characterData.Components.Health :: HealthComponentData
        if component._healthUpdating then return end
        
        component._healthUpdating = true
        local healthValue = StateHelpers.asNumber(newHealth, 100)
        humanoid.Health = healthValue
        component._healthUpdating = false
        
        -- Check for death
        local isDead = StateHelpers.asBoolean(stateManager:Get("IsDead"), false)
        if healthValue <= 0 and not isDead then
            self:_HandleDeath(characterData)
        end
        
        -- Health change effects could be added here
        local oldHealthValue = StateHelpers.asNumber(oldHealth, 100)
        if healthValue < oldHealthValue then
            local dmg = oldHealthValue - healthValue
            self:_OnDamage(characterData, dmg)
            if characterData.Signals and characterData.Signals.OnDamage then
                characterData.Signals.OnDamage:Fire(dmg, false)
            end
            stateManager:Set("LastDamage", dmg)
        end
    end)
    
    stateManager:OnStateChange("MaxHealth", function(newMaxHealth, _oldMaxHealth)
        local component = characterData.Components.Health :: HealthComponentData
        if component._healthUpdating then return end
        
        component._healthUpdating = true
        local maxHealthValue = StateHelpers.asNumber(newMaxHealth, 100)
        humanoid.MaxHealth = maxHealthValue
        -- Clamp current health to max
        local currentHealth = StateHelpers.asNumber(stateManager:Get("Health"), 100)
        if currentHealth > maxHealthValue then
            stateManager:Set("Health", maxHealthValue)
        end
        component._healthUpdating = false
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
            component._healthUpdating = false
        end
    end)
    table.insert(characterData._connections, connection)
    -- Set up humanoid died connection
    local diedConnection = humanoid.Died:Connect(function()
        HealthComponent._HandleDeath(characterData)
    end)
    table.insert(characterData._connections, diedConnection)
end

function HealthComponent:_HandleDeath(characterData: CharacterTypes.internalCharacter)
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

function HealthComponent:_OnDamage(characterData: CharacterTypes.internalCharacter, damage: number)
    local component = characterData.Components.Health :: HealthComponentData
    if component then
        component.LastDamageTime = tick()
        component.IsRegenerating = false
    end
    
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

function HealthComponent:Update(characterData: CharacterTypes.internalCharacter, dt: number)
    if not self:IsEnabled(characterData) then
        return
    end
    
    local component = characterData.Components.Health :: HealthComponentData
    if not component then
        return
    end
    
    -- Handle health regeneration
    local stateManager = characterData.StateManager
    
    local isDead = StateHelpers.asBoolean(stateManager:Get("IsDead"), false)
    if isDead then return end
    
    -- Check if regeneration should start
    local currentTime = tick()
    if component.LastDamageTime > 0 and (currentTime - component.LastDamageTime) >= HEALTH_REGEN_DELAY then
        component.IsRegenerating = true
    end
    
    -- Apply regeneration
    if component.IsRegenerating then
        local currentHealth = StateHelpers.asNumber(stateManager:Get("Health"), component.CurrentHealth)
        local maxHealth = StateHelpers.asNumber(stateManager:Get("MaxHealth"), component.MaxHealth)
        
        if currentHealth < maxHealth and currentHealth > 0 then
            local regenAmount = component.HealthRegen * dt
            local newHealth = math.min(maxHealth, currentHealth + regenAmount)
            self:SetHealth(characterData, newHealth)
        end
    end
end

function HealthComponent:Cleanup(characterData: CharacterTypes.internalCharacter)
    BaseComponent.Cleanup(self, characterData)
end

function HealthComponent:Damage(characterData: CharacterTypes.internalCharacter, amount: number, source: string?): number
    local component = characterData.Components.Health :: HealthComponentData
    if not component then
        return 0
    end
    
    -- Apply damage reduction
    local actualDamage = amount * (1 - component.DamageReduction)
    
    local currentHealth = self:GetHealth(characterData)
    local newHealth = math.max(0, currentHealth - actualDamage)
    
    self:SetHealth(characterData, newHealth)
    
    return actualDamage
end

function HealthComponent:Heal(characterData: CharacterTypes.internalCharacter, amount: number, source: string?): number
    local component = characterData.Components.Health :: HealthComponentData
    if not component then
        return 0
    end
    
    local currentHealth = self:GetHealth(characterData)
    local maxHealth = self:GetMaxHealth(characterData)
    local actualHeal = math.min(amount, maxHealth - currentHealth)
    
    if actualHeal > 0 then
        component.LastHealTime = tick()
        self:SetHealth(characterData, currentHealth + actualHeal)
    end
    
    return actualHeal
end

function HealthComponent:SetHealth(characterData: CharacterTypes.internalCharacter, health: number)
    local component = characterData.Components.Health :: HealthComponentData
    if component then
        component.CurrentHealth = health
        characterData.StateManager:Set("Health", health)
    end
end

function HealthComponent:SetMaxHealth(characterData: CharacterTypes.internalCharacter, maxHealth: number)
    local component = characterData.Components.Health :: HealthComponentData
    if component then
        component.MaxHealth = maxHealth
        characterData.StateManager:Set("MaxHealth", maxHealth)
        
        -- Clamp current health if needed
        if component.CurrentHealth > maxHealth then
            self:SetHealth(characterData, maxHealth)
        end
    end
end

function HealthComponent:GetHealth(characterData: CharacterTypes.internalCharacter): number
    local component = characterData.Components.Health :: HealthComponentData
    return component and component.CurrentHealth or 0
end

function HealthComponent:GetMaxHealth(characterData: CharacterTypes.internalCharacter): number
    local component = characterData.Components.Health :: HealthComponentData
    return component and component.MaxHealth or 100
end

function HealthComponent:GetHealthPercent(characterData: CharacterTypes.internalCharacter): number
    local health = self:GetHealth(characterData)
    local maxHealth = self:GetMaxHealth(characterData)
    return maxHealth > 0 and (health / maxHealth) or 0
end

function HealthComponent:IsAlive(characterData: CharacterTypes.internalCharacter): boolean
    local isDead = StateHelpers.asBoolean(characterData.StateManager:Get("IsDead"), false)
    return not isDead and self:GetHealth(characterData) > 0
end

function HealthComponent:Revive(characterData: CharacterTypes.internalCharacter, healthPercent: number?)
    local percent = healthPercent or 1
    local maxHealth = self:GetMaxHealth(characterData)
    
    characterData.StateManager:Set("IsDead", false)
    self:SetHealth(characterData, maxHealth * percent)
    
    local component = characterData.Components.Health :: HealthComponentData
    if component then
        component.LastDamageTime = 0
        component.IsRegenerating = false
    end
    
    -- Fire revival signal if available
    if characterData.Signals and characterData.Signals.OnRevive then
        characterData.Signals.OnRevive:Fire()
    end
end

-- Create singleton instance for backward compatibility
local instance = HealthComponent.new()

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