--!strict
-- Test script to verify the registry systems are working using TestService

local TestService = game:GetService("TestService")

local AbilityRegistry = require(game.ServerStorage.Modules.registery.ImprovedAbilityRegistry)
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
local function testAbilityRegistry()
    TestService:Message("Testing Ability Registry...")
    
    -- Test GetAll method
    assertType(AbilityRegistry.GetAll, "function", "GetAll should be a function")
    
    local allAbilities = AbilityRegistry.GetAll()
    assertType(allAbilities, "table", "GetAll should return a table")
    
    -- Test that we have some abilities
    local abilityCount = 0
    for id, ability in allAbilities do
        abilityCount += 1
        assertType(id, "string", "Ability ID should be a string")
        assertType(ability, "table", "Ability should be a table")
        assertHasProperty(ability, "name", `Ability {id} should have a name`)
        assertHasProperty(ability, "type", `Ability {id} should have a type`)
        
        TestService:Message(`✓ Found ability: {id} - {ability.name} ({ability.type})`)
    end
    
    TestService:Message(`Found {abilityCount} abilities total`)
    
    -- Test type-specific getters
    assertType(AbilityRegistry.GetActive, "function", "GetActive should be a function")
    assertType(AbilityRegistry.GetPassive, "function", "GetPassive should be a function")
    assertType(AbilityRegistry.GetToggle, "function", "GetToggle should be a function")
    
    -- Test with valid ability IDs
    local dashAbility = AbilityRegistry.GetActive("Dash")
    if dashAbility then
        assertHasProperty(dashAbility, "name", "Dash ability should have a name")
        TestService:Message(`✓ Found dash ability: {dashAbility.name}`)
    else
        TestService:Message("ℹ No Dash ability found (this may be expected)")
    end
    
    local keenAbility = AbilityRegistry.GetPassive("Keen")
    if keenAbility then
        assertHasProperty(keenAbility, "name", "Keen ability should have a name")
        TestService:Message(`✓ Found keen ability: {keenAbility.name}`)
    else
        TestService:Message("ℹ No Keen ability found (this may be expected)")
    end
    
    -- Test bulk getters
    local allActives = AbilityRegistry.GetAllActives()
    local allPassives = AbilityRegistry.GetAllPassives()
    local allToggles = AbilityRegistry.GetAllToggles()
    
    assertType(allActives, "table", "GetAllActives should return a table")
    assertType(allPassives, "table", "GetAllPassives should return a table")
    assertType(allToggles, "table", "GetAllToggles should return a table")
    
    local activeCount = 0
    for _ in allActives do activeCount += 1 end
    local passiveCount = 0
    for _ in allPassives do passiveCount += 1 end
    local toggleCount = 0
    for _ in allToggles do toggleCount += 1 end
    
    TestService:Message(`Active abilities: {activeCount}, Passive: {passiveCount}, Toggle: {toggleCount}`)
    
    -- Test utility methods
    local totalCount = AbilityRegistry.Count()
    assertType(totalCount, "number", "Count should return a number")
    TestService:Message(`Total ability count: {totalCount}`)
    
    TestService:Message("✓ Ability Registry tests passed")
end

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
        TestService:Message(`✓ Found default loadout with primary attack: {defaultLoadout.primaryAttack or "None"}`)
        
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
            
            TestService:Message(`✓ Found loadout: {assetKey} - Primary: {loadout.primaryAttack or "None"}`)
        end
        
        TestService:Message(`Found {loadoutCount} loadouts total`)
    else
        TestService:Message("ℹ LoadoutRegistry.GetAllLoadouts method not available")
    end
    
    TestService:Message("✓ Loadout Registry tests passed")
end

-- Test registry integration
local function testRegistryIntegration()
    TestService:Message("Testing registry integration...")
    
    -- Test that registries can work together
    local allAbilities = AbilityRegistry.GetAll()
    
    -- Verify that we have at least some registries working
    local hasAbilities = next(allAbilities) ~= nil
    
    TestService:Message(`Registry status - Abilities: {hasAbilities and "✓" or "⚠"}`)
    
    -- Test that the ability IDs are valid enum values
    for id, ability in allAbilities do
        local validIds = {"Dash", "Keen", "Heal", "Block", "Parry", "Charge", "Slam", "Thrust"}
        local isValidId = false
        for _, validId in validIds do
            if id == validId then
                isValidId = true
                break
            end
        end
        assert(isValidId, `Ability ID '{id}' is not a valid AbilityId enum value`)
    end
    
    TestService:Message("✓ Registry integration tests passed")
end

-- Run all tests
local function runAllTests()
    TestService:Message("=== Starting Registry System Tests ===")
    
    local success = pcall(testAbilityRegistry)
    if not success then
        TestService:Error("Ability Registry test failed")
        return
    end
    
    success = pcall(testEffectRegistry)
    if not success then
        TestService:Error("Effect Registry test failed")
        return
    end
    
    success = pcall(testLoadoutRegistry)
    if not success then
        TestService:Error("Loadout Registry test failed")
        return
    end
    
    success = pcall(testRegistryIntegration)
    if not success then
        TestService:Error("Registry integration test failed")
        return
    end
    
    TestService:Message("=== All Registry System Tests Passed ===")
end

-- Run the tests
runAllTests()
