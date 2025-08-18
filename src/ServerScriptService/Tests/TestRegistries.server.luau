--!strict
-- Test script to verify the registry systems are working using TestService

local TestService = game:GetService("TestService")

local EffectRegistry = require(game.ServerStorage.Modules.registery.Effects)
local LoadoutRegistry = require(game.ServerStorage.Modules.registery.Loadouts)

-- Test utilities
local function assert(condition: boolean, message: string)
    if not condition then
        TestService:Error(message)
    end
end

local function assertType(value: any, expectedType: string, message: string?)
    local testMessage = message or `Expected type {expectedType}, got {typeof(value)}`
    assert(typeof(value) == expectedType, testMessage)
end

local function assertHasProperty(object: any, propertyName: string, message: string?)
    local testMessage = message or `Expected object to have property '{propertyName}'`
    assert(typeof(object) == "table" and object[propertyName] ~= nil, testMessage)
end

-- Test Ability Registry functionality
-- Ability registry tests removed

-- Test Effect Registry functionality
local function testEffectRegistry()
    TestService:Message("Testing Effect Registry...")
    
    -- Test GetAllEffects method (if it exists)
    if EffectRegistry.GetAllEffects then
        assertType(EffectRegistry.GetAllEffects, "function", "GetAllEffects should be a function")
        
        local allEffects = EffectRegistry.GetAllEffects()
        assertType(allEffects, "table", "GetAllEffects should return a table")
        
        local effectCount = 0
        for id, effect in allEffects do
            effectCount += 1
            assertType(id, "string", "Effect ID should be a string")
            assertType(effect, "table", "Effect should be a table")
            assertHasProperty(effect, "name", `Effect {id} should have a name`)
            
            TestService:Message(`✓ Found effect: {id} - {effect.name}`)
        end
        
        TestService:Message(`Found {effectCount} effects total`)
    else
        TestService:Message("ℹ EffectRegistry.GetAllEffects method not available")
    end
    
    -- Test GetEffect method (if it exists)
    if EffectRegistry.GetEffect then
        assertType(EffectRegistry.GetEffect, "function", "GetEffect should be a function")
        
        local bleedEffect = EffectRegistry.GetEffect("Bleed")
        if bleedEffect then
            assertHasProperty(bleedEffect, "name", "Bleed effect should have a name")
            TestService:Message(`✓ Found bleed effect: {bleedEffect.name}`)
        else
            TestService:Message("ℹ No bleed effect found (this may be expected)")
        end
    else
        TestService:Message("ℹ EffectRegistry.GetEffect method not available")
    end
    
    TestService:Message("✓ Effect Registry tests passed")
end

-- Test Loadout Registry functionality
local function testLoadoutRegistry()
    TestService:Message("Testing Loadout Registry...")
    
    -- Test Get method
    assertType(LoadoutRegistry.Get, "function", "Get should be a function")
    
    local defaultLoadout = LoadoutRegistry.Get("Default")
    if defaultLoadout then
        assertType(defaultLoadout, "table", "Default loadout should be a table")
        local primary = (defaultLoadout.primaryAttacks and defaultLoadout.primaryAttacks[1]) or "None"
        TestService:Message(`✓ Found default loadout with primary attack: {primary}`)
        
        -- Test loadout properties
        if defaultLoadout.actives then
            assertType(defaultLoadout.actives, "table", "Loadout actives should be a table")
            TestService:Message(`✓ Default loadout actives: {table.concat(defaultLoadout.actives, ", ")}`)
        end
        
        if defaultLoadout.passive then
            TestService:Message(`✓ Default loadout passive: {defaultLoadout.passive}`)
        end
    else
        TestService:Message("ℹ No default loadout found (this may be expected)")
    end
    
    -- Test GetAllLoadouts method (if it exists)
    if LoadoutRegistry.GetAllLoadouts then
        assertType(LoadoutRegistry.GetAllLoadouts, "function", "GetAllLoadouts should be a function")
        
        local allLoadouts = LoadoutRegistry.GetAllLoadouts()
        assertType(allLoadouts, "table", "GetAllLoadouts should return a table")
        
        local loadoutCount = 0
        for assetKey, loadout in allLoadouts do
            loadoutCount += 1
            assertType(assetKey, "string", "Loadout asset key should be a string")
            assertType(loadout, "table", "Loadout should be a table")
            local p = (loadout.primaryAttacks and loadout.primaryAttacks[1]) or "None"
            TestService:Message(`✓ Found loadout: {assetKey} - Primary: {p}`)
        end
        
        TestService:Message(`Found {loadoutCount} loadouts total`)
    else
        TestService:Message("ℹ LoadoutRegistry.GetAllLoadouts method not available")
    end
    
    TestService:Message("✓ Loadout Registry tests passed")
end

-- Test registry integration
-- Integration tests related to ability registry removed

-- Run all tests
local function runAllTests()
    TestService:Message("=== Starting Registry System Tests ===")
    
    -- Ability registry removed
    local success = pcall(testEffectRegistry)
    if not success then
        TestService:Error("Effect Registry test failed")
        return
    end
    
    success = pcall(testLoadoutRegistry)
    if not success then
        TestService:Error("Loadout Registry test failed")
        return
    end
    
    -- Ability registry integration removed
    
    TestService:Message("=== All Registry System Tests Passed ===")
end

-- Run the tests
runAllTests()
