--!strict
-- AbilityCategoryRegistry: Runtime registration and management of ability categories
-- Dynamically registers ability categories as they are loaded

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local ClientAbilityStateManager = require(script.Parent.ClientAbilityStateManager)

type AbilityCategory = Types.AbilityCategory
type AbilityConfig = Types.AbilityConfig
type ClientAbility = Types.ClientAbility

export type CategoryDefinition = {
    name: AbilityCategory,
    resourceType: "ammo" | "cooldown" | "passive",
    validator: ((context: any) -> (boolean, string?))?,
    executor: ((ability: ClientAbility, context: any) -> any)?,
    defaultConfig: {[string]: any}?,
}

export type RegisteredAbility = {
    id: string,
    category: AbilityCategory,
    config: AbilityConfig,
    handler: ClientAbility?,
    registered: number,
}

export type AbilityCategoryRegistry = {
    -- Category management
    DefineCategory: (self: AbilityCategoryRegistry, definition: CategoryDefinition) -> (),
    GetCategory: (self: AbilityCategoryRegistry, name: AbilityCategory) -> CategoryDefinition?,
    GetAllCategories: (self: AbilityCategoryRegistry) -> {[AbilityCategory]: CategoryDefinition},
    
    -- Ability registration
    RegisterAbility: (self: AbilityCategoryRegistry, abilityId: string, config: AbilityConfig, handler: ClientAbility?) -> boolean,
    UnregisterAbility: (self: AbilityCategoryRegistry, abilityId: string) -> (),
    GetAbility: (self: AbilityCategoryRegistry, abilityId: string) -> RegisteredAbility?,
    GetAbilitiesByCategory: (self: AbilityCategoryRegistry, category: AbilityCategory) -> {RegisteredAbility},
    GetAllAbilities: (self: AbilityCategoryRegistry) -> {[string]: RegisteredAbility},
    
    -- Auto-discovery
    ScanAndRegisterAbilities: (self: AbilityCategoryRegistry) -> number,
    StartAutoDiscovery: (self: AbilityCategoryRegistry, interval: number?) -> (),
    StopAutoDiscovery: (self: AbilityCategoryRegistry) -> (),
    
    -- Events
    OnAbilityRegistered: (self: AbilityCategoryRegistry, callback: (ability: RegisteredAbility) -> ()) -> () -> (),
    OnCategoryDefined: (self: AbilityCategoryRegistry, callback: (category: CategoryDefinition) -> ()) -> () -> (),
}

local AbilityCategoryRegistry = {}
AbilityCategoryRegistry.__index = AbilityCategoryRegistry

function AbilityCategoryRegistry.new(): AbilityCategoryRegistry
    local self = setmetatable({}, AbilityCategoryRegistry)
    
    self._categories = {} :: {[AbilityCategory]: CategoryDefinition}
    self._abilities = {} :: {[string]: RegisteredAbility}
    self._stateManager = ClientAbilityStateManager.GetInstance()
    self._autoDiscoveryConnection = nil :: RBXScriptConnection?
    
    -- Event listeners
    self._abilityListeners = {} :: {(ability: RegisteredAbility) -> ()}
    self._categoryListeners = {} :: {(category: CategoryDefinition) -> ()}
    
    -- Define default categories
    self:_defineDefaultCategories()
    
    return self :: any
end

function AbilityCategoryRegistry:DefineCategory(definition: CategoryDefinition)
    if self._categories[definition.name] then
        warn(`[AbilityCategoryRegistry] Category {definition.name} already defined`)
        return
    end
    
    self._categories[definition.name] = definition
    
    -- Notify listeners
    for _, callback in ipairs(self._categoryListeners) do
        task.spawn(callback, definition)
    end
end

function AbilityCategoryRegistry:GetCategory(name: AbilityCategory): CategoryDefinition?
    return self._categories[name]
end

function AbilityCategoryRegistry:GetAllCategories(): {[AbilityCategory]: CategoryDefinition}
    local copy = {}
    for name, definition in pairs(self._categories) do
        copy[name] = definition
    end
    return copy
end

function AbilityCategoryRegistry:RegisterAbility(abilityId: string, config: AbilityConfig, handler: ClientAbility?): boolean
    -- Validate category exists
    local category = config.ABILITY_CATEGORY
    if not self._categories[category] then
        warn(`[AbilityCategoryRegistry] Unknown category {category} for ability {abilityId}`)
        return false
    end
    
    -- Check if already registered
    if self._abilities[abilityId] then
        warn(`[AbilityCategoryRegistry] Ability {abilityId} already registered`)
        return false
    end
    
    -- Create registration
    local registration: RegisteredAbility = {
        id = abilityId,
        category = category,
        config = config,
        handler = handler,
        registered = workspace:GetServerTimeNow(),
    }
    
    self._abilities[abilityId] = registration
    
    -- Register with state manager
    self._stateManager:RegisterAbility(abilityId, config)
    
    -- Notify listeners
    for _, callback in ipairs(self._abilityListeners) do
        task.spawn(callback, registration)
    end
    
    print(`[AbilityCategoryRegistry] Registered ability {abilityId} in category {category}`)
    return true
end

function AbilityCategoryRegistry:UnregisterAbility(abilityId: string)
    local ability = self._abilities[abilityId]
    if not ability then return end
    
    self._abilities[abilityId] = nil
    self._stateManager:UnregisterAbility(abilityId)
    
    print(`[AbilityCategoryRegistry] Unregistered ability {abilityId}`)
end

function AbilityCategoryRegistry:GetAbility(abilityId: string): RegisteredAbility?
    return self._abilities[abilityId]
end

function AbilityCategoryRegistry:GetAbilitiesByCategory(category: AbilityCategory): {RegisteredAbility}
    local abilities = {}
    for _, ability in pairs(self._abilities) do
        if ability.category == category then
            table.insert(abilities, ability)
        end
    end
    return abilities
end

function AbilityCategoryRegistry:GetAllAbilities(): {[string]: RegisteredAbility}
    local copy = {}
    for id, ability in pairs(self._abilities) do
        copy[id] = ability
    end
    return copy
end

function AbilityCategoryRegistry:ScanAndRegisterAbilities(): number
    local ClientAbilities = require(ReplicatedStorage.Modules.ClientAbilities)
    local registered = 0
    
    -- List of known ability IDs to scan
    local abilityIds = {
        "RemM1", "RemM2", "RemE", "RemR", "RemT", "RemF",
        "Dash", "Rem1", "Rem2"
    }
    
    for _, abilityId in ipairs(abilityIds) do
        -- Skip if already registered
        if self._abilities[abilityId] then
            continue
        end
        
        -- Try to load ability
        local ability = ClientAbilities.GetAbility(abilityId)
        if ability then
            -- Get config through GetSharedModule
            if ability.GetSharedModule then
                local shared = ability.GetSharedModule()
                if shared and shared.GetConfig then
                    local config = shared.GetConfig()
                    if config and config.ABILITY_CATEGORY then
                        local success = self:RegisterAbility(abilityId, config, ability)
                        if success then
                            registered = registered + 1
                        end
                    end
                end
            end
        end
    end
    
    print(`[AbilityCategoryRegistry] Scanned and registered {registered} abilities`)
    return registered
end

function AbilityCategoryRegistry:StartAutoDiscovery(interval: number?)
    if self._autoDiscoveryConnection then
        warn("[AbilityCategoryRegistry] Auto-discovery already running")
        return
    end
    
    local scanInterval = interval or 5
    
    -- Initial scan
    self:ScanAndRegisterAbilities()
    
    -- Periodic scans
    self._autoDiscoveryConnection = task.spawn(function()
        while self._autoDiscoveryConnection do
            task.wait(scanInterval)
            self:ScanAndRegisterAbilities()
        end
    end)
    
    print(`[AbilityCategoryRegistry] Started auto-discovery with {scanInterval}s interval`)
end

function AbilityCategoryRegistry:StopAutoDiscovery()
    if self._autoDiscoveryConnection then
        task.cancel(self._autoDiscoveryConnection)
        self._autoDiscoveryConnection = nil
        print("[AbilityCategoryRegistry] Stopped auto-discovery")
    end
end

function AbilityCategoryRegistry:OnAbilityRegistered(callback: (ability: RegisteredAbility) -> ()): () -> ()
    table.insert(self._abilityListeners, callback)
    
    -- Call for existing abilities
    for _, ability in pairs(self._abilities) do
        task.spawn(callback, ability)
    end
    
    -- Return disconnect function
    return function()
        local index = table.find(self._abilityListeners, callback)
        if index then
            table.remove(self._abilityListeners, index)
        end
    end
end

function AbilityCategoryRegistry:OnCategoryDefined(callback: (category: CategoryDefinition) -> ()): () -> ()
    table.insert(self._categoryListeners, callback)
    
    -- Call for existing categories
    for _, category in pairs(self._categories) do
        task.spawn(callback, category)
    end
    
    -- Return disconnect function
    return function()
        local index = table.find(self._categoryListeners, callback)
        if index then
            table.remove(self._categoryListeners, index)
        end
    end
end

-- Private methods
function AbilityCategoryRegistry:_defineDefaultCategories()
    -- Primary abilities (ammo-based)
    self:DefineCategory({
        name = "Primary",
        resourceType = "ammo",
        validator = function(context)
            -- Context has numeric abilityId, we need string
            -- Don't validate here - let state manager handle it
            return true
        end,
    })
    
    -- Active abilities (cooldown-based)
    self:DefineCategory({
        name = "Active",
        resourceType = "cooldown",
        validator = function(context)
            -- Don't validate here - let state manager handle it
            return true
        end,
    })
    
    -- Secondary abilities (cooldown-based)
    self:DefineCategory({
        name = "Secondary",
        resourceType = "cooldown",
        validator = function(context)
            -- Don't validate here - let state manager handle it
            return true
        end,
    })
    
    -- Ultimate abilities (long cooldown)
    self:DefineCategory({
        name = "Ultimate",
        resourceType = "cooldown",
        validator = function(context)
            -- Don't validate here - let state manager handle it
            return true
        end,
    })
    
    -- Passive abilities (always active)
    self:DefineCategory({
        name = "Passive",
        resourceType = "passive",
        validator = function(_context)
            return true -- Passives are always valid
        end,
    })
end

function AbilityCategoryRegistry:Destroy()
    self:StopAutoDiscovery()
    table.clear(self._abilityListeners)
    table.clear(self._categoryListeners)
    table.clear(self._abilities)
    table.clear(self._categories)
end

-- Create singleton instance
local instance: AbilityCategoryRegistry? = nil

return {
    GetInstance = function(): AbilityCategoryRegistry
        if not instance then
            instance = AbilityCategoryRegistry.new()
        end
        return instance :: AbilityCategoryRegistry
    end,
    
    new = AbilityCategoryRegistry.new,
}