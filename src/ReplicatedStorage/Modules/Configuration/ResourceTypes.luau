--!strict
-- ResourceTypes: Abstract resource behavior implementations
-- Provides pluggable resource types for the ability system

local RunService = game:GetService("RunService")

export type ResourceValue = number | {current: number, max: number}

export type ResourceState = {
    type: string,
    current: number,
    max: number,
    regenRate: number?,
    lastUseTime: number?,
    isReloading: boolean?,
    reloadStartTime: number?,
    metadata: {[string]: any}?,
}

export type ResourceBehavior = {
    type: string,
    displayName: string,
    
    -- Core methods
    Initialize: (config: {[string]: any}) -> ResourceState,
    CanUse: (state: ResourceState, cost: number?) -> boolean,
    Use: (state: ResourceState, cost: number?) -> ResourceState,
    Update: (state: ResourceState, deltaTime: number) -> ResourceState,
    
    -- Optional methods
    StartReload: ((state: ResourceState) -> ResourceState)?,
    CancelReload: ((state: ResourceState) -> ResourceState)?,
    GetDisplayInfo: ((state: ResourceState) -> {text: string, progress: number})?,
    
    -- Configuration
    defaultConfig: {[string]: any},
    supportsReload: boolean,
    supportsRegen: boolean,
}

-- Resource Type Registry
local ResourceTypes = {}
local registeredTypes: {[string]: ResourceBehavior} = {}

-- Ammo Resource Type
local AmmoResource: ResourceBehavior = {
    type = "ammo",
    displayName = "Ammo",
    supportsReload = true,
    supportsRegen = false,
    
    defaultConfig = {
        maxAmmo = 6,
        reloadTime = 2,
        autoReload = true,
        fireRate = 0.5,
    },
    
    Initialize = function(config)
        return {
            type = "ammo",
            current = config.maxAmmo or 6,
            max = config.maxAmmo or 6,
            isReloading = false,
            metadata = {
                reloadTime = config.reloadTime or 2,
                autoReload = config.autoReload ~= false,
                fireRate = config.fireRate or 0.5,
            },
        }
    end,
    
    CanUse = function(state, cost)
        return state.current >= (cost or 1) and not state.isReloading
    end,
    
    Use = function(state, cost)
        local newState = table.clone(state)
        newState.current = math.max(0, state.current - (cost or 1))
        newState.lastUseTime = workspace:GetServerTimeNow()
        
        -- Auto-reload when empty
        if newState.current <= 0 and state.metadata and state.metadata.autoReload then
            newState.isReloading = true
            newState.reloadStartTime = workspace:GetServerTimeNow()
        end
        
        return newState
    end,
    
    Update = function(state, deltaTime)
        if not state.isReloading then
            return state
        end
        
        local reloadTime = state.metadata and state.metadata.reloadTime or 2
        local elapsed = workspace:GetServerTimeNow() - (state.reloadStartTime or 0)
        
        if elapsed >= reloadTime then
            local newState = table.clone(state)
            newState.current = state.max
            newState.isReloading = false
            newState.reloadStartTime = nil
            return newState
        end
        
        return state
    end,
    
    StartReload = function(state)
        if state.isReloading or state.current >= state.max then
            return state
        end
        
        local newState = table.clone(state)
        newState.isReloading = true
        newState.reloadStartTime = workspace:GetServerTimeNow()
        return newState
    end,
    
    CancelReload = function(state)
        if not state.isReloading then
            return state
        end
        
        local newState = table.clone(state)
        newState.isReloading = false
        newState.reloadStartTime = nil
        return newState
    end,
    
    GetDisplayInfo = function(state)
        if state.isReloading then
            local reloadTime = state.metadata and state.metadata.reloadTime or 2
            local elapsed = workspace:GetServerTimeNow() - (state.reloadStartTime or 0)
            local progress = math.min(1, elapsed / reloadTime)
            return {
                text = "Reloading...",
                progress = progress,
            }
        else
            return {
                text = `{state.current}/{state.max}`,
                progress = state.current / state.max,
            }
        end
    end,
}

-- Cooldown Resource Type
local CooldownResource: ResourceBehavior = {
    type = "cooldown",
    displayName = "Cooldown",
    supportsReload = false,
    supportsRegen = false,
    
    defaultConfig = {
        cooldownTime = 5,
        fireRate = 0.1,
    },
    
    Initialize = function(config)
        return {
            type = "cooldown",
            current = 0,
            max = config.cooldownTime or 5,
            lastUseTime = 0,
            metadata = {
                fireRate = config.fireRate or 0.1,
            },
        }
    end,
    
    CanUse = function(state, cost)
        local now = workspace:GetServerTimeNow()
        local elapsed = now - (state.lastUseTime or 0)
        return elapsed >= state.max
    end,
    
    Use = function(state, cost)
        local newState = table.clone(state)
        newState.lastUseTime = workspace:GetServerTimeNow()
        return newState
    end,
    
    Update = function(state, deltaTime)
        -- Cooldowns update automatically based on time
        return state
    end,
    
    GetDisplayInfo = function(state)
        local now = workspace:GetServerTimeNow()
        local elapsed = now - (state.lastUseTime or 0)
        local remaining = math.max(0, state.max - elapsed)
        local progress = 1 - (remaining / state.max)
        
        if remaining > 0 then
            return {
                text = string.format("%.1fs", remaining),
                progress = progress,
            }
        else
            return {
                text = "Ready",
                progress = 1,
            }
        end
    end,
}

-- Energy Resource Type
local EnergyResource: ResourceBehavior = {
    type = "energy",
    displayName = "Energy",
    supportsReload = false,
    supportsRegen = true,
    
    defaultConfig = {
        maxEnergy = 100,
        energyCost = 25,
        regenRate = 5, -- per second
        regenDelay = 2, -- delay after use before regen starts
    },
    
    Initialize = function(config)
        return {
            type = "energy",
            current = config.startEnergy or config.maxEnergy or 100,
            max = config.maxEnergy or 100,
            regenRate = config.regenRate or 5,
            lastUseTime = 0,
            metadata = {
                energyCost = config.energyCost or 25,
                regenDelay = config.regenDelay or 2,
            },
        }
    end,
    
    CanUse = function(state, cost)
        local actualCost = cost or (state.metadata and state.metadata.energyCost) or 25
        return state.current >= actualCost
    end,
    
    Use = function(state, cost)
        local actualCost = cost or (state.metadata and state.metadata.energyCost) or 25
        local newState = table.clone(state)
        newState.current = math.max(0, state.current - actualCost)
        newState.lastUseTime = workspace:GetServerTimeNow()
        return newState
    end,
    
    Update = function(state, deltaTime)
        local now = workspace:GetServerTimeNow()
        local timeSinceUse = now - (state.lastUseTime or 0)
        local regenDelay = state.metadata and state.metadata.regenDelay or 2
        
        if timeSinceUse > regenDelay and state.current < state.max then
            local newState = table.clone(state)
            local regenAmount = (state.regenRate or 5) * deltaTime
            newState.current = math.min(state.max, state.current + regenAmount)
            return newState
        end
        
        return state
    end,
    
    GetDisplayInfo = function(state)
        return {
            text = `{math.floor(state.current)}/{state.max}`,
            progress = state.current / state.max,
        }
    end,
}

-- Charges Resource Type
local ChargesResource: ResourceBehavior = {
    type = "charges",
    displayName = "Charges",
    supportsReload = false,
    supportsRegen = true,
    
    defaultConfig = {
        maxCharges = 3,
        chargeRegenTime = 5,
        consumeAllOnUse = false,
    },
    
    Initialize = function(config)
        return {
            type = "charges",
            current = config.maxCharges or 3,
            max = config.maxCharges or 3,
            lastUseTime = 0,
            metadata = {
                chargeRegenTime = config.chargeRegenTime or 5,
                consumeAllOnUse = config.consumeAllOnUse or false,
                lastRegenTime = workspace:GetServerTimeNow(),
            },
        }
    end,
    
    CanUse = function(state, cost)
        return state.current >= (cost or 1)
    end,
    
    Use = function(state, cost)
        local newState = table.clone(state)
        if state.metadata and state.metadata.consumeAllOnUse then
            newState.current = 0
        else
            newState.current = math.max(0, state.current - (cost or 1))
        end
        newState.lastUseTime = workspace:GetServerTimeNow()
        return newState
    end,
    
    Update = function(state, deltaTime)
        if state.current >= state.max then
            return state
        end
        
        local now = workspace:GetServerTimeNow()
        local metadata = state.metadata
        if not metadata then return state end
        
        local timeSinceRegen = now - (metadata.lastRegenTime or 0)
        local regenTime = metadata.chargeRegenTime or 5
        
        if timeSinceRegen >= regenTime then
            local newState = table.clone(state)
            newState.current = math.min(state.max, state.current + 1)
            
            if not newState.metadata then
                newState.metadata = {}
            end
            newState.metadata = table.clone(newState.metadata)
            newState.metadata.lastRegenTime = now
            
            return newState
        end
        
        return state
    end,
    
    GetDisplayInfo = function(state)
        local chargeDisplay = string.rep("●", state.current) .. string.rep("○", state.max - state.current)
        
        if state.current < state.max then
            local metadata = state.metadata
            if metadata then
                local now = workspace:GetServerTimeNow()
                local timeSinceRegen = now - (metadata.lastRegenTime or 0)
                local regenTime = metadata.chargeRegenTime or 5
                local progress = timeSinceRegen / regenTime
                
                return {
                    text = chargeDisplay,
                    progress = (state.current + progress) / state.max,
                }
            end
        end
        
        return {
            text = chargeDisplay,
            progress = state.current / state.max,
        }
    end,
}

-- Heat Resource Type (inverse - builds up with use)
local HeatResource: ResourceBehavior = {
    type = "heat",
    displayName = "Heat",
    supportsReload = false,
    supportsRegen = true,
    
    defaultConfig = {
        maxHeat = 100,
        heatPerUse = 20,
        cooldownRate = 10, -- per second
        overheatPenalty = 3, -- seconds
    },
    
    Initialize = function(config)
        return {
            type = "heat",
            current = 0,
            max = config.maxHeat or 100,
            regenRate = -(config.cooldownRate or 10), -- negative for cooling
            lastUseTime = 0,
            metadata = {
                heatPerUse = config.heatPerUse or 20,
                overheatPenalty = config.overheatPenalty or 3,
                overheated = false,
                overheatTime = 0,
            },
        }
    end,
    
    CanUse = function(state, cost)
        local metadata = state.metadata
        if metadata and metadata.overheated then
            local now = workspace:GetServerTimeNow()
            local timeSinceOverheat = now - (metadata.overheatTime or 0)
            if timeSinceOverheat < (metadata.overheatPenalty or 3) then
                return false
            end
        end
        
        local heatCost = cost or (metadata and metadata.heatPerUse) or 20
        return state.current + heatCost <= state.max
    end,
    
    Use = function(state, cost)
        local heatCost = cost or (state.metadata and state.metadata.heatPerUse) or 20
        local newState = table.clone(state)
        newState.current = math.min(state.max, state.current + heatCost)
        newState.lastUseTime = workspace:GetServerTimeNow()
        
        if newState.current >= state.max then
            if not newState.metadata then
                newState.metadata = {}
            end
            newState.metadata = table.clone(newState.metadata)
            newState.metadata.overheated = true
            newState.metadata.overheatTime = workspace:GetServerTimeNow()
        end
        
        return newState
    end,
    
    Update = function(state, deltaTime)
        if state.current <= 0 then
            return state
        end
        
        local newState = table.clone(state)
        local coolAmount = math.abs(state.regenRate or 10) * deltaTime
        newState.current = math.max(0, state.current - coolAmount)
        
        -- Clear overheat when fully cooled
        if newState.current <= 0 and state.metadata and state.metadata.overheated then
            if not newState.metadata then
                newState.metadata = {}
            end
            newState.metadata = table.clone(newState.metadata)
            newState.metadata.overheated = false
            newState.metadata.overheatTime = 0
        end
        
        return newState
    end,
    
    GetDisplayInfo = function(state)
        local metadata = state.metadata
        if metadata and metadata.overheated then
            return {
                text = "OVERHEATED",
                progress = 1,
            }
        else
            local heatPercent = (state.current / state.max) * 100
            return {
                text = string.format("%.0f%%", heatPercent),
                progress = state.current / state.max,
            }
        end
    end,
}

-- Register default types
function ResourceTypes.RegisterDefaults()
    registeredTypes["ammo"] = AmmoResource
    registeredTypes["cooldown"] = CooldownResource
    registeredTypes["energy"] = EnergyResource
    registeredTypes["charges"] = ChargesResource
    registeredTypes["heat"] = HeatResource
end

-- Register custom resource type
function ResourceTypes.RegisterType(resourceType: ResourceBehavior)
    if registeredTypes[resourceType.type] then
        warn(`[ResourceTypes] Type {resourceType.type} already registered`)
        return false
    end
    
    registeredTypes[resourceType.type] = resourceType
    return true
end

-- Get resource type
function ResourceTypes.GetType(typeName: string): ResourceBehavior?
    return registeredTypes[typeName]
end

-- Get all registered types
function ResourceTypes.GetAllTypes(): {[string]: ResourceBehavior}
    return table.clone(registeredTypes)
end

-- Create resource state from config
function ResourceTypes.CreateResource(typeName: string, config: {[string]: any}?): ResourceState?
    local resourceType = registeredTypes[typeName]
    if not resourceType then
        warn(`[ResourceTypes] Unknown resource type: {typeName}`)
        return nil
    end
    
    local finalConfig = {}
    
    -- Merge default config
    for key, value in pairs(resourceType.defaultConfig) do
        finalConfig[key] = value
    end
    
    -- Override with provided config
    if config then
        for key, value in pairs(config) do
            finalConfig[key] = value
        end
    end
    
    return resourceType.Initialize(finalConfig)
end

-- Update resource state
function ResourceTypes.UpdateResource(state: ResourceState, deltaTime: number): ResourceState
    local resourceType = registeredTypes[state.type]
    if not resourceType then
        warn(`[ResourceTypes] Unknown resource type: {state.type}`)
        return state
    end
    
    return resourceType.Update(state, deltaTime)
end

-- Check if resource can be used
function ResourceTypes.CanUseResource(state: ResourceState, cost: number?): boolean
    local resourceType = registeredTypes[state.type]
    if not resourceType then
        return false
    end
    
    return resourceType.CanUse(state, cost)
end

-- Use resource
function ResourceTypes.UseResource(state: ResourceState, cost: number?): ResourceState
    local resourceType = registeredTypes[state.type]
    if not resourceType then
        warn(`[ResourceTypes] Unknown resource type: {state.type}`)
        return state
    end
    
    return resourceType.Use(state, cost)
end

-- Start reload (if supported)
function ResourceTypes.StartReload(state: ResourceState): ResourceState
    local resourceType = registeredTypes[state.type]
    if not resourceType then
        return state
    end
    
    if resourceType.StartReload then
        return resourceType.StartReload(state)
    end
    
    return state
end

-- Get display info
function ResourceTypes.GetDisplayInfo(state: ResourceState): {text: string, progress: number}?
    local resourceType = registeredTypes[state.type]
    if not resourceType then
        return nil
    end
    
    if resourceType.GetDisplayInfo then
        return resourceType.GetDisplayInfo(state)
    end
    
    -- Default display
    return {
        text = `{state.current}/{state.max}`,
        progress = state.current / state.max,
    }
end

-- Initialize with default types
ResourceTypes.RegisterDefaults()

return ResourceTypes