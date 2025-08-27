--!strict
-- Ability Definitions Loader
-- Automatically loads all ability definitions and registers them with the system

local AbilityRegistry = require(game.ServerStorage.Modules.Core.AbilitySystem.AbilityRegistry)

local AbilityDefinitionsLoader = {}

function AbilityDefinitionsLoader.LoadAll()
    local registry = AbilityRegistry.get()
    local definitionsFolder = script
    
    print("[AbilityDefinitionsLoader] Loading ability definitions...")
    
    local loadedCount = 0
    local failedCount = 0
    
    -- Recursively load all definition modules
    local function loadFolder(folder: Instance, path: string)
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("ModuleScript") and child.Name ~= "init" then
                local success, result = pcall(require, child)
                if success then
                    -- Handle single or multiple definitions
                    if type(result) == "table" then
                        if result.id then
                            -- Single definition
                            local registered = registry:registerDefinition(result)
                            if registered then
                                loadedCount = loadedCount + 1
                                print(`  ✓ Loaded {path}/{child.Name}: {result.id}`)
                            else
                                failedCount = failedCount + 1
                                warn(`  ✗ Failed to register {path}/{child.Name}`)
                            end
                        elseif result[1] then
                            -- Array of definitions
                            for i, def in ipairs(result) do
                                local registered = registry:registerDefinition(def)
                                if registered then
                                    loadedCount = loadedCount + 1
                                    print(`  ✓ Loaded {path}/{child.Name}[{i}]: {def.id}`)
                                else
                                    failedCount = failedCount + 1
                                    warn(`  ✗ Failed to register {path}/{child.Name}[{i}]`)
                                end
                            end
                        else
                            -- Dictionary of definitions
                            for id, def in pairs(result) do
                                if type(def) == "table" then
                                    def.id = def.id or id
                                    local registered = registry:registerDefinition(def)
                                    if registered then
                                        loadedCount = loadedCount + 1
                                        print(`  ✓ Loaded {path}/{child.Name}.{id}`)
                                    else
                                        failedCount = failedCount + 1
                                        warn(`  ✗ Failed to register {path}/{child.Name}.{id}`)
                                    end
                                end
                            end
                        end
                    end
                else
                    failedCount = failedCount + 1
                    warn(`  ✗ Error loading {path}/{child.Name}: {result}`)
                end
            elseif child:IsA("Folder") then
                -- Recursively load subfolders
                loadFolder(child, `{path}/{child.Name}`)
            end
        end
    end
    
    -- Start loading from root
    loadFolder(definitionsFolder, "AbilityDefinitions")
    
    print(`[AbilityDefinitionsLoader] Completed: {loadedCount} loaded, {failedCount} failed`)
    
    return {
        loaded = loadedCount,
        failed = failedCount,
        total = loadedCount + failedCount
    }
end

function AbilityDefinitionsLoader.LoadCharacter(characterName: string)
    local registry = AbilityRegistry.get()
    local characterFolder = script:FindFirstChild(characterName)
    
    if not characterFolder then
        warn(`[AbilityDefinitionsLoader] Character folder not found: {characterName}`)
        return {}
    end
    
    local abilities = {}
    
    for _, module in ipairs(characterFolder:GetChildren()) do
        if module:IsA("ModuleScript") then
            local success, definition = pcall(require, module)
            if success and type(definition) == "table" and definition.id then
                registry:registerDefinition(definition)
                abilities[module.Name] = definition.id
            end
        end
    end
    
    return abilities
end

-- Auto-load on require
AbilityDefinitionsLoader.LoadAll()

return AbilityDefinitionsLoader