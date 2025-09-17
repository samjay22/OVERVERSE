--!strict
-- ComponentInitializer - Ensures all components are properly initialized

local RunService = game:GetService("RunService")

-- Only run on server
if not RunService:IsServer() then
    return
end

print("Initializing Component System...")

-- Pre-load all components to ensure they're registered
local components = {
    "AbilityComponent",
    "CombatComponent", 
    "EffectComponent",
    "HealthComponent",
    "InputComponent",
    "MovementComponent",
    "StaminaComponent",
    "WeaponComponent",
}

local loadedCount = 0
for _, componentName in ipairs(components) do
    local success, result = pcall(function()
        return require(game.ServerStorage.Modules.Components[componentName])
    end)
    
    if success then
        loadedCount = loadedCount + 1
        print("✓ Loaded", componentName)
    else
        warn("✗ Failed to load", componentName, "-", result)
    end
end

print(string.format("Component System Initialized: %d/%d components loaded", loadedCount, #components))

-- Initialize Ability System
local abilitySuccess, abilityErr = pcall(function()
    -- Load ability definitions
    local _AbilityDefinitions = require(game.ServerStorage.AbilityDefinitions)
    print("✓ Ability definitions loaded")
end)

if not abilitySuccess then
    warn("Failed to load ability definitions:", abilityErr)
end

-- Initialize AbilityInputHandler
local handlerSuccess, handlerErr = pcall(function()
    local AbilityInputHandler = require(game.ServerStorage.Modules.Handlers.AbilityInputHandler)
    if AbilityInputHandler.initialize then
        AbilityInputHandler.initialize()
        print("✓ AbilityInputHandler initialized")
    end
end)

if not handlerSuccess then
    warn("Failed to initialize AbilityInputHandler:", handlerErr)
end