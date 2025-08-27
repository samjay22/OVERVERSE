--!strict

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Types = require(script.Parent.Types)
local AbilityDefinition = require(script.Parent.AbilityDefinition)

type AbilityDefinition = Types.AbilityDefinition

-- Registry for all ability definitions in the game
local AbilityRegistry = {}
AbilityRegistry.__index = AbilityRegistry

local registry = nil

function AbilityRegistry.new()
    if registry then
        return registry
    end
    
    local self = setmetatable({}, AbilityRegistry)
    
    -- Storage for definitions
    self.definitions = {} :: {[string]: AbilityDefinition}
    self.definitionsByTag = {} :: {[string]: {AbilityDefinition}}
    self.definitionsByCategory = {} :: {[string]: {AbilityDefinition}}
    self.definitionsByCharacter = {} :: {[string]: {AbilityDefinition}}
    
    -- Caches
    self.instanceCache = {} :: {[string]: {[Instance]: Types.AbilityInstance}}
    self.modifierCache = {} :: {[string]: {Types.AbilityModifier}}
    
    -- Watchers for hot-reloading
    self.watchers = {} :: {[string]: RBXScriptConnection}
    self.loadedModules = {} :: {[ModuleScript]: boolean}
    
    -- Configuration
    self.config = {
        autoLoad = true,
        hotReload = RunService:IsStudio(),
        cacheDuration = 60,
        maxCacheSize = 1000
    }
    
    -- Initialize
    self:_initialize()
    
    registry = self
    return self
end

function AbilityRegistry:_initialize()
    -- Auto-load definitions if enabled
    if self.config.autoLoad then
        self:loadAllDefinitions()
    end
    
    -- Setup hot-reloading in Studio
    if self.config.hotReload then
        self:_setupHotReloading()
    end
    
    -- Periodic cache cleanup
    task.spawn(function()
        while true do
            task.wait(self.config.cacheDuration)
            self:_cleanupCache()
        end
    end)
end

-- Load ability definitions from various sources

function AbilityRegistry:loadAllDefinitions()
    -- Load from configuration modules
    self:loadFromFolder(ServerStorage:FindFirstChild("AbilityDefinitions"))
    self:loadFromFolder(ReplicatedStorage:FindFirstChild("AbilityDefinitions"))
    
    -- Load from legacy ability modules (backwards compatibility)
    self:loadLegacyAbilities()
    
    -- Load from JSON configuration files
    self:loadFromJSON()
    
    print(`[AbilityRegistry] Loaded {self:getDefinitionCount()} ability definitions`)
end

function AbilityRegistry:loadFromFolder(folder: Folder?)
    if not folder then
        return
    end
    
    for _, child in ipairs(folder:GetDescendants()) do
        if child:IsA("ModuleScript") then
            self:loadFromModule(child)
        end
    end
end

function AbilityRegistry:loadFromModule(module: ModuleScript)
    -- Prevent duplicate loading
    if self.loadedModules[module] then
        return
    end
    
    local success, result = pcall(require, module)
    if not success then
        warn(`[AbilityRegistry] Failed to load module {module:GetFullName()}: {result}`)
        return
    end
    
    -- Handle different module formats
    if type(result) == "table" then
        if result.id and result.name and result.type then
            -- Single definition
            self:registerDefinition(result)
        elseif result[1] then
            -- Array of definitions
            for _, def in ipairs(result) do
                self:registerDefinition(def)
            end
        else
            -- Dictionary of definitions
            for id, def in pairs(result) do
                if type(def) == "table" then
                    def.id = def.id or id
                    self:registerDefinition(def)
                end
            end
        end
    end
    
    self.loadedModules[module] = true
    
    -- Watch for changes if hot-reloading is enabled
    if self.config.hotReload then
        self:_watchModule(module)
    end
end

function AbilityRegistry:loadFromJSON()
    -- Look for JSON configuration files
    local configFolder = ServerStorage:FindFirstChild("AbilityConfigs")
    if not configFolder then
        return
    end
    
    for _, child in ipairs(configFolder:GetChildren()) do
        if child:IsA("StringValue") and child.Name:match("%.json$") then
            local success, data = pcall(function()
                return HttpService:JSONDecode(child.Value)
            end)
            
            if success and type(data) == "table" then
                if data.abilities then
                    for _, def in ipairs(data.abilities) do
                        self:registerDefinition(def)
                    end
                elseif data.id then
                    self:registerDefinition(data)
                end
            else
                warn(`[AbilityRegistry] Failed to parse JSON file {child.Name}`)
            end
        end
    end
end

function AbilityRegistry:loadLegacyAbilities()
    -- Load from the legacy ability system for backwards compatibility
    local abilitiesFolder = ReplicatedStorage:FindFirstChild("Modules"):FindFirstChild("Abilities")
    if not abilitiesFolder then
        return
    end
    
    for _, characterFolder in ipairs(abilitiesFolder:GetChildren()) do
        if characterFolder:IsA("Folder") then
            local characterName = characterFolder.Name
            
            for _, abilityModule in ipairs(characterFolder:GetChildren()) do
                if abilityModule:IsA("ModuleScript") then
                    self:_convertLegacyAbility(abilityModule, characterName)
                end
            end
        end
    end
end

function AbilityRegistry:_convertLegacyAbility(module: ModuleScript, characterName: string)
    local success, abilityData = pcall(require, module)
    if not success then
        return
    end
    
    -- Convert legacy format to new definition format
    local abilityName = module.Name
    local definition = {
        id = `{characterName}_{abilityName}`,
        name = abilityName,
        type = "Instant",
        activation = "Press",
        slot = abilityName,
        cooldown = { base = 5, modifiable = true },
        targeting = {
            type = "Aimed",
            range = 50,
            filter = { team = "Enemy", status = "Alive" }
        },
        effects = {},
        tags = { "Legacy", characterName },
        category = characterName,
        
        -- Store reference to legacy module for execution
        _legacyModule = module,
        _legacyData = abilityData
    }
    
    -- Try to extract configuration from legacy module
    if abilityData.Config then
        local config = abilityData.Config
        
        if config.Cooldown then
            definition.cooldown.base = config.Cooldown
        end
        
        if config.Range then
            definition.targeting.range = config.Range
        end
        
        if config.Damage then
            table.insert(definition.effects, {
                type = "Damage",
                trigger = "OnHit",
                amount = { base = config.Damage, modifiable = true },
                damageType = config.DamageType or "Physical"
            })
        end
    end
    
    self:registerDefinition(definition)
end

-- Registration and retrieval

-- OPTIMIZED: Faster registration with reduced allocations
function AbilityRegistry:registerDefinition(config: AbilityDefinition | {[string]: any}): boolean
    local success, definition = pcall(AbilityDefinition.new, config)
    if not success then
        warn(`[AbilityRegistry] Failed to register ability: {definition}`)
        return false
    end

    local id = definition.id

    -- OPTIMIZED: Only warn on duplicates if different
    local existing = self.definitions[id]
    if existing and existing ~= definition then
        warn(`[AbilityRegistry] Overwriting existing definition: {id}`)
    end

    -- Store in main registry
    self.definitions[id] = definition

    -- OPTIMIZED: Batch tag indexing to reduce table operations
    if definition.tags then
        local tagsByDefinition = self.definitionsByTag
        for _, tag in ipairs(definition.tags) do
            local tagList = tagsByDefinition[tag]
            if not tagList then
                tagList = {}
                tagsByDefinition[tag] = tagList
            end
            -- OPTIMIZED: Use direct insertion instead of table.insert
            tagList[#tagList + 1] = definition
        end
    end
    
    -- Index by category
    local category = definition.category or "General"
    if not self.definitionsByCategory[category] then
        self.definitionsByCategory[category] = {}
    end
    table.insert(self.definitionsByCategory[category], definition)
    
    -- Clear relevant caches
    self.instanceCache[id] = nil
    
    return true
end

function AbilityRegistry:unregisterDefinition(id: string): boolean
    local definition = self.definitions[id]
    if not definition then
        return false
    end
    
    -- Remove from main registry
    self.definitions[id] = nil
    
    -- Remove from tag indices
    if definition.tags then
        for _, tag in ipairs(definition.tags) do
            local tagList = self.definitionsByTag[tag]
            if tagList then
                local index = table.find(tagList, definition)
                if index then
                    table.remove(tagList, index)
                end
            end
        end
    end
    
    -- Remove from category index
    local category = definition.category or "General"
    local categoryList = self.definitionsByCategory[category]
    if categoryList then
        local index = table.find(categoryList, definition)
        if index then
            table.remove(categoryList, index)
        end
    end
    
    -- Clear caches
    self.instanceCache[id] = nil
    
    return true
end

function AbilityRegistry:getDefinition(id: string): AbilityDefinition?
    return self.definitions[id]
end

function AbilityRegistry:getDefinitions(): {AbilityDefinition}
    local list = {}
    for _, def in pairs(self.definitions) do
        table.insert(list, def)
    end
    return list
end

function AbilityRegistry:getDefinitionsByTag(tag: string): {AbilityDefinition}
    return self.definitionsByTag[tag] or {}
end

function AbilityRegistry:getDefinitionsByCategory(category: string): {AbilityDefinition}
    return self.definitionsByCategory[category] or {}
end

function AbilityRegistry:getDefinitionsByCharacter(characterName: string): {AbilityDefinition}
    -- Try cached result first
    if self.definitionsByCharacter[characterName] then
        return self.definitionsByCharacter[characterName]
    end
    
    -- Find all abilities for this character
    local abilities = {}
    
    -- Check by tag
    local byTag = self:getDefinitionsByTag(characterName)
    for _, def in ipairs(byTag) do
        abilities[def.id] = def
    end
    
    -- Check by category
    local byCategory = self:getDefinitionsByCategory(characterName)
    for _, def in ipairs(byCategory) do
        abilities[def.id] = def
    end
    
    -- Check by ID prefix
    for id, def in pairs(self.definitions) do
        if id:find(`^{characterName}_`) then
            abilities[id] = def
        end
    end
    
    -- Convert to list
    local list = {}
    for _, def in pairs(abilities) do
        table.insert(list, def)
    end
    
    -- Cache result
    self.definitionsByCharacter[characterName] = list
    
    return list
end

function AbilityRegistry:getDefinitionCount(): number
    local count = 0
    for _ in pairs(self.definitions) do
        count = count + 1
    end
    return count
end

-- Search and filtering

function AbilityRegistry:findDefinitions(filter: (AbilityDefinition) -> boolean): {AbilityDefinition}
    local results = {}
    
    for _, def in pairs(self.definitions) do
        if filter(def) then
            table.insert(results, def)
        end
    end
    
    return results
end

function AbilityRegistry:searchDefinitions(query: string): {AbilityDefinition}
    local lowerQuery = query:lower()
    
    return self:findDefinitions(function(def)
        -- Search in ID
        if def.id:lower():find(lowerQuery) then
            return true
        end
        
        -- Search in name
        if def.name:lower():find(lowerQuery) then
            return true
        end
        
        -- Search in description
        if def.description and def.description:lower():find(lowerQuery) then
            return true
        end
        
        -- Search in tags
        if def.tags then
            for _, tag in ipairs(def.tags) do
                if tag:lower():find(lowerQuery) then
                    return true
                end
            end
        end
        
        return false
    end)
end

-- Hot-reloading support

function AbilityRegistry:_setupHotReloading()
    -- Watch for new ability modules
    local function watchFolder(folder: Folder)
        folder.DescendantAdded:Connect(function(descendant)
            if descendant:IsA("ModuleScript") then
                task.wait(0.1) -- Wait for module to be fully loaded
                self:loadFromModule(descendant)
                print(`[AbilityRegistry] Hot-loaded new ability: {descendant.Name}`)
            end
        end)
        
        folder.DescendantRemoving:Connect(function(descendant)
            if descendant:IsA("ModuleScript") and self.loadedModules[descendant] then
                -- Find and remove definitions from this module
                for id, def in pairs(self.definitions) do
                    if def._sourceModule == descendant then
                        self:unregisterDefinition(id)
                        print(`[AbilityRegistry] Removed ability: {id}`)
                    end
                end
                self.loadedModules[descendant] = nil
            end
        end)
    end
    
    -- Watch known ability folders
    local folders = {
        ServerStorage:FindFirstChild("AbilityDefinitions"),
        ReplicatedStorage:FindFirstChild("AbilityDefinitions"),
        ReplicatedStorage:FindFirstChild("Modules"):FindFirstChild("Abilities")
    }
    
    for _, folder in ipairs(folders) do
        if folder then
            watchFolder(folder)
        end
    end
end

function AbilityRegistry:_watchModule(module: ModuleScript)
    -- Watch for changes to module scripts
    if self.watchers[module:GetFullName()] then
        return
    end
    
    local connection
    connection = module.Changed:Connect(function()
        -- Reload the module
        self.loadedModules[module] = nil
        self:loadFromModule(module)
        print(`[AbilityRegistry] Reloaded module: {module.Name}`)
    end)
    
    self.watchers[module:GetFullName()] = connection
end

-- Cache management

function AbilityRegistry:_cleanupCache()
    local now = os.clock()
    local cacheSize = 0
    
    for abilityId, instanceCache in pairs(self.instanceCache) do
        for owner, instance in pairs(instanceCache) do
            cacheSize = cacheSize + 1
            
            -- Remove instances that no longer exist
            if not owner.Parent then
                instanceCache[owner] = nil
            end
        end
        
        -- Remove empty caches
        if next(instanceCache) == nil then
            self.instanceCache[abilityId] = nil
        end
    end
    
    -- Clear oldest entries if cache is too large
    if cacheSize > self.config.maxCacheSize then
        -- Simple strategy: clear half the cache
        local cleared = 0
        for abilityId, instanceCache in pairs(self.instanceCache) do
            self.instanceCache[abilityId] = {}
            cleared = cleared + 1
            if cleared > cacheSize / 2 then
                break
            end
        end
    end
end

-- Singleton access
local registryInstance = nil

function AbilityRegistry.get()
    if not registryInstance then
        registryInstance = AbilityRegistry.new()
    end
    return registryInstance
end

return AbilityRegistry