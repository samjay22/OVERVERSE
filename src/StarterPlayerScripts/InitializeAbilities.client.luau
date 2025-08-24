--!strict
-- InitializeAbilities: Bootstraps the ability system with configuration
-- Ensures all configured abilities are properly registered

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer

-- Wait for modules
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configuration = Modules:WaitForChild("Configuration")
local Utility = Modules:WaitForChild("Utility")

-- Import modules
local AbilityConfiguration = require(Configuration:WaitForChild("AbilityConfiguration"))
local ResourceTypes = require(Configuration:WaitForChild("ResourceTypes"))
local ClientAbilityStateManager = require(Utility:WaitForChild("ClientAbilityStateManager"))
local AbilityCategoryRegistry = require(Utility:WaitForChild("AbilityCategoryRegistry"))
local ClientAbilities = require(Modules:WaitForChild("ClientAbilities"))

-- Get singletons
local stateManager = ClientAbilityStateManager.GetInstance()
local registry = AbilityCategoryRegistry.GetInstance()

print("[InitializeAbilities] Starting ability system initialization...")

-- Wait for character
local character = Player.Character or Player.CharacterAdded:Wait()

-- Initialize all configured abilities
local function initializeAbilities()
    local enabledAbilities = AbilityConfiguration.GetEnabledAbilities()
    local initialized = 0
    
    for _, abilityDef in ipairs(enabledAbilities) do
        print(`[InitializeAbilities] Initializing {abilityDef.id}...`)
        
        -- Try to get the ability handler
        local handler = ClientAbilities.GetAbility(abilityDef.id)
        
        if handler then
            -- Get config from handler
            local config = nil
            if handler.GetSharedModule then
                local shared = handler.GetSharedModule()
                if shared and shared.GetConfig then
                    config = shared.GetConfig()
                end
            end
            
            if config then
                -- Register with the registry (which also registers with state manager)
                local success = registry:RegisterAbility(abilityDef.id, config, handler)
                if success then
                    initialized = initialized + 1
                    print(`[InitializeAbilities] ✓ Registered {abilityDef.id}`)
                else
                    warn(`[InitializeAbilities] Failed to register {abilityDef.id}`)
                end
            else
                warn(`[InitializeAbilities] No config found for {abilityDef.id}`)
            end
        else
            -- Ability handler not loaded yet, create a minimal config
            local minimalConfig = {
                ABILITY_CATEGORY = abilityDef.category,
                ATTACK_RANGE = abilityDef.attackRange or 100,
                REQUIRES_TARGET = abilityDef.requiresTarget or false,
            }
            
            -- Add resource-specific fields based on type
            if abilityDef.resource then
                local resourceType = abilityDef.resource.type
                if resourceType == "ammo" then
                    minimalConfig.MAX_AMMO = abilityDef.resource.maxAmmo
                    minimalConfig.RELOAD_TIME = abilityDef.resource.reloadTime
                    minimalConfig.FIRE_RATE = abilityDef.resource.fireRate
                elseif resourceType == "cooldown" then
                    minimalConfig.COOLDOWN_TIME = abilityDef.resource.cooldownTime
                    minimalConfig.FIRE_RATE = abilityDef.resource.fireRate
                end
            end
            
            -- Register with minimal config
            local success = registry:RegisterAbility(abilityDef.id, minimalConfig, nil)
            if success then
                initialized = initialized + 1
                print(`[InitializeAbilities] ✓ Pre-registered {abilityDef.id} (handler will load later)`)
            end
        end
    end
    
    print(`[InitializeAbilities] Initialized {initialized}/{#enabledAbilities} abilities`)
    
    -- Print summary
    local allAbilities = registry:GetAllAbilities()
    print("[InitializeAbilities] Registered abilities:")
    for id, registration in pairs(allAbilities) do
        local state = stateManager:GetAbilityState(id)
        if state then
            print(`  - {id}: {state.type} resource, ready: {state.ready}`)
        else
            print(`  - {id}: No state`)
        end
    end
end

-- Initialize on startup
task.wait(1) -- Small delay to ensure everything is loaded
initializeAbilities()

-- Re-initialize when character respawns
Player.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    task.wait(1)
    initializeAbilities()
end)

print("[InitializeAbilities] Ability system initialization complete")