--!strict
-- Component Test - Verifies that refactored components work correctly

local function testComponents()
    print("Testing refactored components...")
    
    -- Test loading each component
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
    
    local results = {}
    
    for _, componentName in ipairs(components) do
        local success, component = pcall(require, game.ServerStorage.Modules.Components[componentName])
        if success then
            -- Check for backward compatibility methods
            local hasInitialize = typeof(component.Initialize) == "function"
            local hasUpdate = typeof(component.Update) == "function"
            local hasCleanup = typeof(component.Cleanup) == "function"
            local hasInstance = component.Instance ~= nil
            
            if hasInitialize and hasUpdate and hasCleanup then
                results[componentName] = {
                    loaded = true,
                    backwardCompatible = true,
                    hasInstance = hasInstance,
                }
                print("✓", componentName, "- Loaded successfully with backward compatibility")
            else
                results[componentName] = {
                    loaded = true,
                    backwardCompatible = false,
                    hasInstance = hasInstance,
                    missingMethods = {
                        Initialize = not hasInitialize,
                        Update = not hasUpdate,
                        Cleanup = not hasCleanup,
                    }
                }
                warn("⚠", componentName, "- Missing backward compatibility methods")
            end
        else
            results[componentName] = {
                loaded = false,
                error = component,
            }
            warn("✗", componentName, "- Failed to load:", component)
        end
    end
    
    -- Test mock character initialization
    print("\nTesting mock character initialization...")
    
    local mockCharacter = {
        PlayerId = 1,
        Player = nil,
        Character = Instance.new("Model"),
        Humanoid = Instance.new("Humanoid"),
        StateManager = {
            Get = function(_, key) return nil end,
            Set = function(_, key, value) end,
            OnStateChange = function(_, key, callback) end,
            SetMultiple = function(_, values) end,
        },
        Components = {},
        Signals = {},
        _connections = {},
    }
    
    -- Try initializing each component with mock data
    for _, componentName in ipairs(components) do
        if results[componentName].loaded and results[componentName].backwardCompatible then
            local component = require(game.ServerStorage.Modules.Components[componentName])
            local initSuccess, initError = pcall(component.Initialize, mockCharacter, {})
            
            if initSuccess then
                print("  ✓", componentName, "initialized successfully")
            else
                warn("  ✗", componentName, "initialization failed:", initError)
            end
        end
    end
    
    print("\nComponent test complete!")
    return results
end

return {
    test = testComponents,
}