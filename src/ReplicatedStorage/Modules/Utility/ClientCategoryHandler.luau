--!strict
-- Abstract client-side category handler with strict typing

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local CategorySystem = require(ReplicatedStorage.Modules.Utility.CategorySystem)

type SharedAbilityContext = Types.SharedAbilityContext
type ClientAbility = Types.ClientAbility
type AbilityCategory = Types.AbilityCategory
type ResourceState = CategorySystem.ResourceState
type ResourceConfig = CategorySystem.ResourceConfig

-- Abstract resource manager interface
type ResourceManager = {
    states: { [string]: ResourceState },
    getState: (self: ResourceManager, id: string, category: AbilityCategory, config: ResourceConfig) -> ResourceState,
    consumeResource: (self: ResourceManager, id: string, category: AbilityCategory, config: ResourceConfig) -> ResourceState,
    canUse: (self: ResourceManager, id: string, category: AbilityCategory, config: ResourceConfig) -> boolean,
    forceReload: (self: ResourceManager, id: string, category: AbilityCategory, config: ResourceConfig) -> boolean,
}

-- Create resource manager with closure
local function createResourceManager(): ResourceManager
    local manager = {} :: ResourceManager
    manager.states = {}
    
    function manager:getState(id: string, category: AbilityCategory, config: ResourceConfig): ResourceState
        if not self.states[id] then
            self.states[id] = CategorySystem.InitializeResourceState(category, id, config)
        end
        
        -- Auto-update reload state for ammo abilities
        if CategorySystem.UsesAmmo(category) and self.states[id].reloading then
            self.states[id] = CategorySystem.UpdateReload(self.states[id], config)
        end
        
        return self.states[id]
    end
    
    function manager:consumeResource(id: string, category: AbilityCategory, config: ResourceConfig): ResourceState
        local state = self:getState(id, category, config)
        local newState = CategorySystem.ConsumeResources(category, state, config)
        self.states[id] = newState
        return newState
    end
    
    function manager:canUse(id: string, category: AbilityCategory, config: ResourceConfig): boolean
        local state = self:getState(id, category, config)
        return CategorySystem.CanUseAbility(category, state, config)
    end
    
    function manager:forceReload(id: string, category: AbilityCategory, config: ResourceConfig): boolean
        if not CategorySystem.CanForceReload(category) then
            return false
        end
        
        local state = self:getState(id, category, config)
        self.states[id] = CategorySystem.ForceReload(category, state, config)
        return true
    end
    
    return manager
end

local resourceManager = createResourceManager()

-- Abstract execution pipeline
local function executeAbilityPipeline(
    abilityModule: ClientAbility,
    context: SharedAbilityContext,
    category: AbilityCategory
): ()
    local sharedModule = abilityModule.GetSharedModule()
    local config = sharedModule.GetConfig()
    local abilityId = tostring(context.abilityId)
    
    -- Check resources
    if not resourceManager:canUse(abilityId, category, config) then
        warn(`[{category}] Cannot execute - resources unavailable`)
        return
    end
    
    -- Execute ability with error handling
    local success, err = pcall(function()
        if abilityModule.OnCast then
            -- Set ability state for UI/other systems
            if CategorySystem.UsesCooldown(category) or CategorySystem.UsesAmmo(category) then
                Players.LocalPlayer:SetAttribute("UsingAbility", true)
                task.defer(function()
                    Players.LocalPlayer:SetAttribute("UsingAbility", false)
                end)
            end
            
            abilityModule.OnCast(context)
        end
    end)
    
    if not success then
        warn(`[{category}] Execution failed: {err}`)
        return
    end
    
    -- Consume resources on successful execution
    resourceManager:consumeResource(abilityId, category, config)
end

-- Public interface with strict typing
export type ClientCategoryHandler = {
    ExecuteAbility: (abilityModule: ClientAbility, context: SharedAbilityContext) -> (),
    GetResourceDisplay: (abilityId: string, category: AbilityCategory, config: ResourceConfig) -> CategorySystem.ResourceDisplay,
    ForceReload: (abilityId: string, category: AbilityCategory, config: ResourceConfig) -> boolean,
}

local ClientCategoryHandler: ClientCategoryHandler = {} :: ClientCategoryHandler

function ClientCategoryHandler.ExecuteAbility(abilityModule: ClientAbility, context: SharedAbilityContext): ()
    local sharedModule = abilityModule.GetSharedModule()
    local config = sharedModule.GetConfig()
    local category: AbilityCategory = config.ABILITY_CATEGORY
    
    executeAbilityPipeline(abilityModule, context, category)
end

function ClientCategoryHandler.GetResourceDisplay(
    abilityId: string,
    category: AbilityCategory,
    config: ResourceConfig
): CategorySystem.ResourceDisplay
    local state = resourceManager:getState(abilityId, category, config)
    return CategorySystem.GetResourceDisplay(category, state, config)
end

function ClientCategoryHandler.ForceReload(
    abilityId: string,
    category: AbilityCategory,
    config: ResourceConfig
): boolean
    return resourceManager:forceReload(abilityId, category, config)
end

-- Auto-update resources every frame
RunService.Heartbeat:Connect(function()
    for id, state in pairs(resourceManager.states) do
        if state.reloading then
            -- Updates happen automatically in getState
            resourceManager:getState(id, state.category, {
                RELOAD_TIME = 2.0, -- Default, should come from config
                ABILITY_CATEGORY = state.category,
            } :: ResourceConfig)
        end
    end
end)

-- Legacy compatibility methods
function ClientCategoryHandler.ExecutePrimary(abilityModule: ClientAbility, context: SharedAbilityContext): ()
    executeAbilityPipeline(abilityModule, context, "Primary")
end

function ClientCategoryHandler.ExecuteActive(abilityModule: ClientAbility, context: SharedAbilityContext): ()
    executeAbilityPipeline(abilityModule, context, "Active")
end

function ClientCategoryHandler.ExecutePassive(abilityModule: ClientAbility, context: SharedAbilityContext): ()
    executeAbilityPipeline(abilityModule, context, "Passive")
end

function ClientCategoryHandler.ExecuteSecondary(abilityModule: ClientAbility, context: SharedAbilityContext): ()
    executeAbilityPipeline(abilityModule, context, "Secondary")
end

function ClientCategoryHandler.ExecuteUltimate(abilityModule: ClientAbility, context: SharedAbilityContext): ()
    executeAbilityPipeline(abilityModule, context, "Ultimate")
end

function ClientCategoryHandler.UpdateResources(): ()
    -- This method is called by external systems but updates happen automatically
end

return ClientCategoryHandler