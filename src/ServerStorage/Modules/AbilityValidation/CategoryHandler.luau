--!strict
-- Optimized Category Handler - Simplified, High-Performance Ability Execution
-- Ultra-lightweight with maximum configurability

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CategorySystem = require(ReplicatedStorage.Modules.Utility.CategorySystem)
local Types = require(script.Parent.Types)
local ClientAbilityTypes = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

type AbilityResult = Types.AbilityResult
type SharedAbilityContext = Types.SharedAbilityContext
type AbilityCategory = CategorySystem.AbilityCategory
type ServerAbilityModule = ClientAbilityTypes.ServerAbility
type ResourceState = CategorySystem.ResourceState
type ResourceConfig = CategorySystem.ResourceConfig

-- OPTIMIZED CATEGORY HANDLER
local CategoryHandler = {}

-- ULTRA-FAST UNIVERSAL EXECUTION ENGINE
local function executeWithResources(
    abilityModule: ServerAbilityModule, 
    context: SharedAbilityContext, 
    category: AbilityCategory
): AbilityResult
    local playerId = context.playerId
    local abilityId = context.abilityId
    
    -- Initialize player if needed
    CategorySystem.InitializePlayer(playerId)
    
    -- Get or create ability state
    local resourceState = CategorySystem.GetPlayerState(playerId, abilityId)
    if not resourceState then
        local sharedModule = abilityModule.GetSharedModule()
        local config = sharedModule.GetConfig()
        
        -- Validate configuration
        local configValid, configError = CategorySystem.ValidateConfig(config)
        if not configValid then
            return {
                success = false,
                reason = "Invalid config: " .. (configError or "Unknown error")
            }
        end
        
        resourceState = CategorySystem.InitializeResourceState(category, tostring(abilityId), config)
        if resourceState then
            CategorySystem.SetPlayerState(playerId, abilityId, resourceState)
        else
            return {
                success = false,
                reason = "Failed to initialize resource state"
            }
        end
    end
    
    -- Ensure we have a valid resource state
    if not resourceState then
        return {
            success = false,
            reason = "No resource state available"
        }
    end
    
    -- Get configuration
    local sharedModule = abilityModule.GetSharedModule()
    local config = sharedModule.GetConfig()
    
    -- Ultra-fast resource check
    if not CategorySystem.CanUseAbility(category, resourceState, config) then
        local display = CategorySystem.GetResourceDisplay(category, resourceState, config)
        return {
            success = false,
            reason = if display.reloading then "Reloading..." 
                    elseif display.cooldownRemaining and display.cooldownRemaining > 0 then "On cooldown" 
                    else "Cannot use ability"
        }
    end
    
    -- Execute ability
    local executeResult = abilityModule.OnRequest(context)
    
    if executeResult.success then
        -- Consume resources and update state
        local newState = CategorySystem.ConsumeResources(category, resourceState, config)
        CategorySystem.SetPlayerState(playerId, abilityId, newState)
    end
    
    return executeResult
end

-- SIMPLIFIED CATEGORY DISPATCH - Direct routing for maximum performance
function CategoryHandler.ExecutePrimary(abilityModule: ServerAbilityModule, context: SharedAbilityContext): AbilityResult
    return executeWithResources(abilityModule, context, "Primary")
end

function CategoryHandler.ExecuteActive(abilityModule: ServerAbilityModule, context: SharedAbilityContext): AbilityResult
    return executeWithResources(abilityModule, context, "Active")
end

function CategoryHandler.ExecutePassive(abilityModule: ServerAbilityModule, context: SharedAbilityContext): AbilityResult
    return executeWithResources(abilityModule, context, "Passive")
end

function CategoryHandler.ExecuteSecondary(abilityModule: ServerAbilityModule, context: SharedAbilityContext): AbilityResult
    return executeWithResources(abilityModule, context, "Secondary")
end

function CategoryHandler.ExecuteUltimate(abilityModule: ServerAbilityModule, context: SharedAbilityContext): AbilityResult
    return executeWithResources(abilityModule, context, "Ultimate")
end

-- MAIN EXECUTION DISPATCHER - Optimized case statement
function CategoryHandler.ExecuteAbility(abilityModule: ServerAbilityModule, context: SharedAbilityContext): AbilityResult
    local sharedModule = abilityModule.GetSharedModule()
    local config = sharedModule.GetConfig()
    local category = config.ABILITY_CATEGORY
    
    -- Fast dispatch based on category
    if category == "Primary" then
        return CategoryHandler.ExecutePrimary(abilityModule, context)
    elseif category == "Active" then
        return CategoryHandler.ExecuteActive(abilityModule, context)
    elseif category == "Passive" then
        return CategoryHandler.ExecutePassive(abilityModule, context)
    elseif category == "Secondary" then
        return CategoryHandler.ExecuteSecondary(abilityModule, context)
    elseif category == "Ultimate" then
        return CategoryHandler.ExecuteUltimate(abilityModule, context)
    else
        return {
            success = false,
            reason = "Unknown ability category: " .. tostring(category)
        }
    end
end

-- OPTIMIZED RELOAD SYSTEM - R Key Integration
function CategoryHandler.HandleReload(playerId: number, abilityId: number): boolean
    local resourceState = CategorySystem.GetPlayerState(playerId, abilityId)
    if not resourceState then
        return false
    end
    
    -- Only Primary abilities can be reloaded
    if not CategorySystem.CanForceReload(resourceState.category) then
        return false
    end
    
    if not CategorySystem.CanReload(resourceState.category, resourceState) then
        return false
    end
    
    -- Create default config for reload (simplified)
    local config: ResourceConfig = {
        ABILITY_CATEGORY = resourceState.category,
        RELOAD_TIME = 2.0, -- Default, should come from actual config
        MAX_AMMO = resourceState.maxAmmo or 6,
    }
    
    local newState = CategorySystem.ForceReload(resourceState.category, resourceState, config)
    CategorySystem.SetPlayerState(playerId, abilityId, newState)
    
    return true
end

-- SIMPLIFIED PLAYER MANAGEMENT
function CategoryHandler.InitializePlayer(playerId: number): ()
    CategorySystem.InitializePlayer(playerId)
end

function CategoryHandler.InitializeAbility(playerId: number, abilityId: number, abilityModule: ServerAbilityModule): ()
    CategorySystem.InitializePlayer(playerId)
    
    local existingState = CategorySystem.GetPlayerState(playerId, abilityId)
    if not existingState then
        local sharedModule = abilityModule.GetSharedModule()
        local config = sharedModule.GetConfig()
        local category = config.ABILITY_CATEGORY :: AbilityCategory
        
        local resourceState = CategorySystem.InitializeResourceState(category :: AbilityCategory, tostring(abilityId), config)
        CategorySystem.SetPlayerState(playerId, abilityId, resourceState)
    end
end

-- UTILITY FUNCTIONS
function CategoryHandler.GetResourceDisplay(playerId: number, abilityId: number): CategorySystem.ResourceDisplay?
    local resourceState = CategorySystem.GetPlayerState(playerId, abilityId)
    if not resourceState then
        return nil
    end
    
    -- Create default config for display
    local config: ResourceConfig = {
        ABILITY_CATEGORY = resourceState.category,
        RELOAD_TIME = 2.0,
        MAX_AMMO = resourceState.maxAmmo or 6,
        COOLDOWN_TIME = resourceState.cooldownDuration or 0,
    }
    
    return CategorySystem.GetResourceDisplay(resourceState.category, resourceState, config)
end

function CategoryHandler.CleanupPlayer(playerId: number): ()
    CategorySystem.CleanupPlayer(playerId)
end

-- PERFORMANCE UTILITIES
function CategoryHandler.GetPlayerResourceState(playerId: number, abilityId: number): ResourceState?
    return CategorySystem.GetPlayerState(playerId, abilityId)
end

function CategoryHandler.UpdatePlayerResourceState(playerId: number, abilityId: number, state: ResourceState): ()
    CategorySystem.SetPlayerState(playerId, abilityId, state)
end

-- CONFIGURATION HELPERS
function CategoryHandler.ValidateAbilityConfig(config: any): (boolean, string?)
    return CategorySystem.ValidateConfig(config)
end

return CategoryHandler
