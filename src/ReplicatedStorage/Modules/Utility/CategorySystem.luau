--!strict
-- Optimized Category System - Ultra-Fast, Highly Configurable Ability Management
-- Single source of truth with minimal overhead and maximum flexibility

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- TYPES
export type AbilityCategory = "Primary" | "Active" | "Passive" | "Secondary" | "Ultimate"

export type ResourceState = {
    category: AbilityCategory,
    abilityId: string,
    lastUpdateTime: number,
    -- Ammo (Primary only)
    currentAmmo: number?,
    maxAmmo: number?,
    reloading: boolean?,
    reloadStartTime: number?,
    -- Cooldown (Active/Secondary/Ultimate only)
    nextUseTime: number?,
    cooldownDuration: number?,
    -- Passive (no resources)
    isActive: boolean?,
    lastTriggerTime: number?,
}

export type ResourceConfig = {
    ABILITY_CATEGORY: AbilityCategory,
    MAX_AMMO: number?,
    RELOAD_TIME: number?,
    COOLDOWN_TIME: number?,
    TRIGGER_INTERVAL: number?,
    -- Enhanced configurability
    AUTO_RELOAD: boolean?,
    INSTANT_RELOAD: boolean?,
    AMMO_REGEN_RATE: number?,
    REQUIRES_TARGET: boolean?,
    ATTACK_RANGE: number?,
}

export type ResourceDisplay = {
    category: AbilityCategory,
    resourceType: "ammo" | "cooldown" | "passive",
    ready: boolean,
    -- Ammo specific
    currentAmmo: number?,
    maxAmmo: number?,
    reloading: boolean?,
    reloadProgress: number?,
    -- Cooldown specific
    cooldownRemaining: number?,
    cooldownTotal: number?,
    -- Passive specific
    active: boolean?,
    lastTrigger: number?,
}

-- OPTIMIZED CATEGORY BEHAVIORS - Pre-computed for performance
local CATEGORY_BEHAVIORS = {
    Primary = {
        usesAmmo = true,
        usesCooldown = false,
        isPassive = false,
        canReload = true,
        resourceType = "ammo",
        defaultMaxAmmo = 6,
        defaultReloadTime = 2.0,
    },
    Active = {
        usesAmmo = false,
        usesCooldown = true,
        isPassive = false,
        canReload = false,
        resourceType = "cooldown",
        defaultCooldown = 8.0,
    },
    Secondary = {
        usesAmmo = false,
        usesCooldown = true,
        isPassive = false,
        canReload = false,
        resourceType = "cooldown",
        defaultCooldown = 5.0,
    },
    Ultimate = {
        usesAmmo = false,
        usesCooldown = true,
        isPassive = false,
        canReload = false,
        resourceType = "cooldown",
        defaultCooldown = 60.0,
    },
    Passive = {
        usesAmmo = false,
        usesCooldown = false,
        isPassive = true,
        canReload = false,
        resourceType = "passive",
        defaultTriggerInterval = 1.0,
    }
}

-- Global state cache for ultra-fast access
local playerResourceCache: {[number]: {[number]: ResourceState}} = {}

-- Cleanup on player disconnect
Players.PlayerRemoving:Connect(function(player)
    playerResourceCache[player.UserId] = nil
end)

local CategorySystem = {}

-- CONFIGURATION VALIDATION - Ensures configs are properly set up
function CategorySystem.ValidateConfig(config: ResourceConfig): (boolean, string?)
    if not config.ABILITY_CATEGORY then
        return false, "Missing ABILITY_CATEGORY"
    end
    
    local behavior = CATEGORY_BEHAVIORS[config.ABILITY_CATEGORY]
    if not behavior then
        return false, "Invalid ABILITY_CATEGORY: " .. tostring(config.ABILITY_CATEGORY)
    end
    
    if behavior.usesAmmo and not config.MAX_AMMO then
        return false, "Primary abilities require MAX_AMMO"
    end
    
    if behavior.usesCooldown and not config.COOLDOWN_TIME then
        return false, "Cooldown abilities require COOLDOWN_TIME"
    end
    
    return true
end

-- OPTIMIZED RESOURCE STATE INITIALIZATION
function CategorySystem.InitializeResourceState(category: AbilityCategory, abilityId: string, config: ResourceConfig): ResourceState
    local behavior = CATEGORY_BEHAVIORS[category]
    local currentTime = tick()
    
    local state: ResourceState = {
        category = category,
        abilityId = abilityId,
        lastUpdateTime = currentTime,
    }
    
    if behavior.usesAmmo then
        state.currentAmmo = config.MAX_AMMO or behavior.defaultMaxAmmo
        state.maxAmmo = config.MAX_AMMO or behavior.defaultMaxAmmo
        state.reloading = false
        state.reloadStartTime = 0
    elseif behavior.usesCooldown then
        state.nextUseTime = 0
        state.cooldownDuration = config.COOLDOWN_TIME or behavior.defaultCooldown
    else -- Passive
        state.isActive = false
        state.lastTriggerTime = 0
    end
    
    return state
end

-- ULTRA-FAST ABILITY USAGE CHECK
function CategorySystem.CanUseAbility(category: AbilityCategory, state: ResourceState, config: ResourceConfig): boolean
    local behavior = CATEGORY_BEHAVIORS[category]
    local currentTime = tick()
    
    -- Update state for auto-regen if applicable
    if behavior.usesAmmo and config.AMMO_REGEN_RATE and config.AMMO_REGEN_RATE > 0 then
        CategorySystem.UpdateAmmoRegen(state, config, currentTime)
    end
    
    if behavior.usesAmmo then
        return not state.reloading and (state.currentAmmo or 0) > 0
    elseif behavior.usesCooldown then
        return currentTime >= (state.nextUseTime or 0)
    else -- Passive
        local triggerInterval = config.TRIGGER_INTERVAL or CATEGORY_BEHAVIORS.Passive.defaultTriggerInterval
        return currentTime >= (state.lastTriggerTime or 0) + triggerInterval
    end
end

-- OPTIMIZED RESOURCE CONSUMPTION
function CategorySystem.ConsumeResources(category: AbilityCategory, state: ResourceState, config: ResourceConfig): ResourceState
    local behavior = CATEGORY_BEHAVIORS[category]
    local currentTime = tick()
    local newState = table.clone(state)
    newState.lastUpdateTime = currentTime
    
    if behavior.usesAmmo then
        newState.currentAmmo = math.max(0, (newState.currentAmmo or 0) - 1)
        
        -- Auto-reload if enabled and ammo is empty
        if config.AUTO_RELOAD and newState.currentAmmo == 0 and not newState.reloading then
            CategorySystem.StartReload(newState, config, currentTime)
        end
    elseif behavior.usesCooldown then
        newState.nextUseTime = currentTime + (newState.cooldownDuration or 0)
    else -- Passive
        newState.lastTriggerTime = currentTime
    end
    
    return newState
end

-- OPTIMIZED RELOAD SYSTEM
function CategorySystem.CanReload(category: AbilityCategory, state: ResourceState): boolean
    local behavior = CATEGORY_BEHAVIORS[category]
    return behavior.canReload and 
           not state.reloading and 
           (state.currentAmmo or 0) < (state.maxAmmo or 0)
end

function CategorySystem.CanForceReload(category: AbilityCategory): boolean
    return CATEGORY_BEHAVIORS[category].canReload
end

function CategorySystem.StartReload(state: ResourceState, config: ResourceConfig, currentTime: number?): ()
    currentTime = currentTime or tick()
    state.reloading = true
    state.reloadStartTime = currentTime
end

function CategorySystem.ForceReload(category: AbilityCategory, state: ResourceState, config: ResourceConfig): ResourceState
    if not CategorySystem.CanForceReload(category) then
        return state
    end
    
    local newState = table.clone(state)
    local currentTime = tick()
    
    if config.INSTANT_RELOAD then
        newState.currentAmmo = newState.maxAmmo
        newState.reloading = false
        newState.reloadStartTime = 0
    else
        CategorySystem.StartReload(newState, config, currentTime)
    end
    
    newState.lastUpdateTime = currentTime
    return newState
end

function CategorySystem.UpdateReload(state: ResourceState, config: ResourceConfig): ResourceState
    if not state.reloading then
        return state
    end
    
    local currentTime = tick()
    local reloadTime = config.RELOAD_TIME or CATEGORY_BEHAVIORS.Primary.defaultReloadTime
    local reloadProgress = (currentTime - (state.reloadStartTime or 0)) / reloadTime
    
    if reloadProgress >= 1.0 then
        local newState = table.clone(state)
        newState.currentAmmo = newState.maxAmmo
        newState.reloading = false
        newState.reloadStartTime = 0
        newState.lastUpdateTime = currentTime
        return newState
    end
    
    return state
end

-- AMMO REGENERATION SYSTEM
function CategorySystem.UpdateAmmoRegen(state: ResourceState, config: ResourceConfig, currentTime: number?): ()
    if not config.AMMO_REGEN_RATE or config.AMMO_REGEN_RATE <= 0 then
        return
    end
    
    currentTime = currentTime or tick()
    local timeSinceLastUpdate = currentTime - (state.lastUpdateTime or 0)
    local ammoToRegen = math.floor(timeSinceLastUpdate * config.AMMO_REGEN_RATE)
    
    if ammoToRegen > 0 then
        state.currentAmmo = math.min((state.currentAmmo or 0) + ammoToRegen, state.maxAmmo or 0)
        state.lastUpdateTime = currentTime
    end
end

-- OPTIMIZED DISPLAY GENERATION
function CategorySystem.GetResourceDisplay(category: AbilityCategory, state: ResourceState, config: ResourceConfig): ResourceDisplay
    local behavior = CATEGORY_BEHAVIORS[category]
    local currentTime = tick()
    
    -- Update state before generating display
    local updatedState = state
    if behavior.usesAmmo and state.reloading then
        updatedState = CategorySystem.UpdateReload(state, config)
    end
    
    local display: ResourceDisplay = {
        category = category,
        resourceType = behavior.resourceType,
        ready = CategorySystem.CanUseAbility(category, updatedState, config),
    }
    
    if behavior.usesAmmo then
        display.currentAmmo = updatedState.currentAmmo
        display.maxAmmo = updatedState.maxAmmo
        display.reloading = updatedState.reloading
        
        if updatedState.reloading then
            local reloadTime = config.RELOAD_TIME or behavior.defaultReloadTime
            display.reloadProgress = math.min(1.0, (currentTime - (updatedState.reloadStartTime or 0)) / reloadTime)
        end
    elseif behavior.usesCooldown then
        display.cooldownTotal = updatedState.cooldownDuration
        display.cooldownRemaining = math.max(0, (updatedState.nextUseTime or 0) - currentTime)
    else -- Passive
        display.active = updatedState.isActive
        display.lastTrigger = updatedState.lastTriggerTime
    end
    
    return display
end

-- PLAYER STATE MANAGEMENT
function CategorySystem.InitializePlayer(playerId: number): ()
    if not playerResourceCache[playerId] then
        playerResourceCache[playerId] = {}
    end
end

function CategorySystem.GetPlayerState(playerId: number, abilityId: number): ResourceState?
    return playerResourceCache[playerId] and playerResourceCache[playerId][abilityId]
end

function CategorySystem.SetPlayerState(playerId: number, abilityId: number, state: ResourceState): ()
    if not playerResourceCache[playerId] then
        CategorySystem.InitializePlayer(playerId)
    end
    playerResourceCache[playerId][abilityId] = state
end

function CategorySystem.CleanupPlayer(playerId: number): ()
    playerResourceCache[playerId] = nil
end

-- UTILITY FUNCTIONS
function CategorySystem.GetBehavior(category: AbilityCategory)
    return CATEGORY_BEHAVIORS[category]
end

function CategorySystem.UsesAmmo(category: AbilityCategory): boolean
    return CATEGORY_BEHAVIORS[category].usesAmmo
end

function CategorySystem.UsesCooldown(category: AbilityCategory): boolean
    return CATEGORY_BEHAVIORS[category].usesCooldown
end

function CategorySystem.IsPassive(category: AbilityCategory): boolean
    return CATEGORY_BEHAVIORS[category].isPassive
end

-- PERFORMANCE OPTIMIZATION: Update all player states in batches
function CategorySystem.UpdateAllStates(): ()
    local currentTime = tick()
    
    for playerId, abilities in pairs(playerResourceCache) do
        for abilityId, state in pairs(abilities) do
            if state.reloading then
                -- Update reload progress
                local behavior = CATEGORY_BEHAVIORS[state.category]
                if behavior.usesAmmo then
                    local reloadTime = behavior.defaultReloadTime -- Could be made configurable
                    if currentTime - (state.reloadStartTime or 0) >= reloadTime then
                        state.currentAmmo = state.maxAmmo
                        state.reloading = false
                        state.reloadStartTime = 0
                        state.lastUpdateTime = currentTime
                    end
                end
            end
        end
    end
end

-- Auto-update states every frame for optimal performance
RunService.Heartbeat:Connect(CategorySystem.UpdateAllStates)

return CategorySystem
