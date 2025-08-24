--!strict
-- ClientCategoryHandler: Integrates with centralized state management
-- Uses ClientAbilityStateManager and AbilityCategoryRegistry for all operations

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local ClientAbilityStateManager = require(script.Parent.ClientAbilityStateManager)
local AbilityCategoryRegistry = require(script.Parent.AbilityCategoryRegistry)
local CategorySystem = require(script.Parent.CategorySystem)

type SharedAbilityContext = Types.SharedAbilityContext
type ClientAbility = Types.ClientAbility
type AbilityCategory = Types.AbilityCategory
type AbilityConfig = Types.AbilityConfig
type ResourceState = ClientAbilityStateManager.ResourceState

export type ResourceDisplay = {
    resourceType: "ammo" | "cooldown" | "passive",
    ready: boolean,
    
    -- Ammo display
    currentAmmo: number?,
    maxAmmo: number?,
    reloading: boolean?,
    reloadProgress: number?,
    
    -- Cooldown display
    cooldownRemaining: number?,
    cooldownTotal: number?,
}

export type ClientCategoryHandler = {
    ExecuteAbility: (abilityModule: ClientAbility, context: SharedAbilityContext) -> (),
    GetResourceDisplay: (abilityId: string, category: AbilityCategory, config: AbilityConfig) -> ResourceDisplay,
    ForceReload: (abilityId: string, category: AbilityCategory, config: AbilityConfig) -> boolean,
    IsReady: (abilityId: string) -> boolean,
    GetState: (abilityId: string) -> ResourceState?,
}

local ClientCategoryHandler = {} :: ClientCategoryHandler

-- Get singleton instances
local stateManager = ClientAbilityStateManager.GetInstance()
local registry = AbilityCategoryRegistry.GetInstance()

-- Numeric to string ID mapping (must match AbilityPredictor)
local NUMERIC_TO_STRING_MAP: {[number]: string} = {
    [1] = "RemM1",
    [2] = "RemM2", 
    [3] = "Dash",
    [4] = "RemE",
    -- [5] = "RemR", -- Not implemented
    -- [6] = "RemT", -- Not implemented
    [7] = "RemF",
}

function ClientCategoryHandler.ExecuteAbility(abilityModule: ClientAbility, context: SharedAbilityContext)
    print(`[ClientCategoryHandler] ExecuteAbility called with ID: {context.abilityId}`)
    
    -- Convert numeric ID to string ID
    local stringAbilityId = NUMERIC_TO_STRING_MAP[context.abilityId]
    if not stringAbilityId then
        stringAbilityId = tostring(context.abilityId)
        warn(`[ClientCategoryHandler] Unknown numeric ability ID: {context.abilityId}`)
    end
    
    print(`[ClientCategoryHandler] String ID: {stringAbilityId}`)
    
    -- Get ability registration
    local registration = registry:GetAbility(stringAbilityId)
    if not registration then
        -- Try to register on the fly
        local sharedModule = abilityModule.GetSharedModule()
        local config = sharedModule.GetConfig()
        registry:RegisterAbility(stringAbilityId, config, abilityModule)
        registration = registry:GetAbility(stringAbilityId)
        
        if not registration then
            warn(`[ClientCategoryHandler] Failed to register ability {stringAbilityId}`)
            return
        end
    end
    
    -- AbilityPredictor already checked IsReady and called UseAbility
    -- We don't need to check again here as it would fail after resource consumption
    
    -- Get category definition for validation
    local categoryDef = registry:GetCategory(registration.category)
    if categoryDef and categoryDef.validator then
        local isValid, reason = categoryDef.validator(context)
        if not isValid then
            warn(`[ClientCategoryHandler] Validation failed for {stringAbilityId}: {reason}`)
            return
        end
    end
    
    -- Execute ability (resource already consumed by AbilityPredictor)
    print(`[ClientCategoryHandler] About to execute ability {stringAbilityId}`)
    print(`[ClientCategoryHandler] Has OnCast: {abilityModule.OnCast ~= nil}, Has Execute: {abilityModule.Execute ~= nil}`)
    if abilityModule.OnCast then
        print(`[ClientCategoryHandler] Calling OnCast for {stringAbilityId}`)
        -- Set using ability attribute for other systems
        Players.LocalPlayer:SetAttribute("UsingAbility", true)
        task.defer(function()
            Players.LocalPlayer:SetAttribute("UsingAbility", false)
        end)
        
        abilityModule.OnCast(context)
        print(`[ClientCategoryHandler] OnCast completed for {stringAbilityId}`)
    else
        warn(`[ClientCategoryHandler] No OnCast or Execute method for {stringAbilityId}`)
    end
end

function ClientCategoryHandler.GetResourceDisplay(
    abilityId: string,
    category: AbilityCategory,
    config: AbilityConfig
): ResourceDisplay
    -- Ensure ability is registered
    local registration = registry:GetAbility(abilityId)
    if not registration then
        registry:RegisterAbility(abilityId, config, nil)
    end
    
    -- Get current state
    local state = stateManager:GetAbilityState(abilityId)
    if not state then
        return {
            resourceType = "cooldown",
            ready = false,
        }
    end
    
    local display: ResourceDisplay = {
        resourceType = state.resourceType,
        ready = state.ready,
    }
    
    -- Add resource-specific fields
    if state.resourceType == "ammo" then
        display.currentAmmo = state.currentAmmo
        display.maxAmmo = state.maxAmmo
        display.reloading = state.reloading
        
        if state.reloading then
            display.reloadProgress = stateManager:GetReloadProgress(abilityId)
        end
        
    elseif state.resourceType == "cooldown" then
        local remaining = stateManager:GetRemainingCooldown(abilityId)
        display.cooldownRemaining = remaining
        display.cooldownTotal = state.cooldownDuration
    end
    
    return display
end

function ClientCategoryHandler.ForceReload(
    abilityId: string,
    category: AbilityCategory,
    config: AbilityConfig
): boolean
    -- Only Primary abilities can be reloaded
    if category ~= "Primary" then
        return false
    end
    
    -- Ensure ability is registered
    local registration = registry:GetAbility(abilityId)
    if not registration then
        registry:RegisterAbility(abilityId, config, nil)
    end
    
    -- Start reload
    stateManager:StartReload(abilityId)
    return true
end

function ClientCategoryHandler.IsReady(abilityId: string): boolean
    return stateManager:IsReady(abilityId)
end

function ClientCategoryHandler.GetState(abilityId: string): ResourceState?
    return stateManager:GetAbilityState(abilityId)
end

-- Legacy compatibility methods (delegate to main method)
function ClientCategoryHandler.ExecutePrimary(abilityModule: ClientAbility, context: SharedAbilityContext)
    ClientCategoryHandler.ExecuteAbility(abilityModule, context)
end

function ClientCategoryHandler.ExecuteActive(abilityModule: ClientAbility, context: SharedAbilityContext)
    ClientCategoryHandler.ExecuteAbility(abilityModule, context)
end

function ClientCategoryHandler.ExecutePassive(abilityModule: ClientAbility, context: SharedAbilityContext)
    ClientCategoryHandler.ExecuteAbility(abilityModule, context)
end

function ClientCategoryHandler.ExecuteSecondary(abilityModule: ClientAbility, context: SharedAbilityContext)
    ClientCategoryHandler.ExecuteAbility(abilityModule, context)
end

function ClientCategoryHandler.ExecuteUltimate(abilityModule: ClientAbility, context: SharedAbilityContext)
    ClientCategoryHandler.ExecuteAbility(abilityModule, context)
end

function ClientCategoryHandler.UpdateResources()
    -- Resources update automatically via ClientAbilityStateManager
end

-- Start auto-discovery when module loads
task.defer(function()
    registry:StartAutoDiscovery(3)
end)

return ClientCategoryHandler