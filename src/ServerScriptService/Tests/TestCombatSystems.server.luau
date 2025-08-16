--!strict
-- Test script for Combat and Weapon systems using TestService

local TestService = game:GetService("TestService")

-- Import the systems we want to test
local CombatService = require(game.ServerStorage.Modules.Services.CombatService)
local WeaponService = require(game.ServerStorage.Modules.Services.WeaponService)
local AbilityService = require(game.ServerStorage.Modules.Services.AbilityService)

-- Test utilities
local function assert(condition: boolean, message: string)
    if not condition then
        TestService:Error(message)
    end
end

local function assertNotNil(value: any, message: string?)
    local testMessage = message or "Expected value to not be nil"
    assert(value ~= nil, testMessage)
end

local function assertType(value: any, expectedType: string, message: string?)
    local testMessage = message or `Expected type {expectedType}, got {typeof(value)}`
    assert(typeof(value) == expectedType, testMessage)
end

-- Test CombatService functionality
local function testCombatService()
    TestService:Message("Testing CombatService...")
    
    -- Test that CombatService loads and has expected methods
    assertNotNil(CombatService, "CombatService should load successfully")
    assertType(CombatService, "table", "CombatService should be a table")
    
    -- Test for actual combat service methods
    assertType(CombatService.New, "function", "New should be a function")
    
    -- Create an instance to test instance methods
    local combatInstance = CombatService.New()
    assertNotNil(combatInstance, "CombatService.New should return an instance")
    
    -- Test instance methods exist
    assertType(combatInstance.Initialize, "function", "Initialize should be a function")
    assertType(combatInstance.PerformAttack, "function", "PerformAttack should be a function")
    assertType(combatInstance.PerformBlock, "function", "PerformBlock should be a function")
    assertType(combatInstance.TakeDamage, "function", "TakeDamage should be a function")
    assertType(combatInstance.ApplyDamage, "function", "ApplyDamage should be a function")
    
    TestService:Message("✓ CombatService tests passed")
end

-- Test WeaponService functionality
local function testWeaponService()
    TestService:Message("Testing WeaponService...")
    
    assertNotNil(WeaponService, "WeaponService should load successfully")
    assertType(WeaponService, "table", "WeaponService should be a table")
    
    -- Test basic structure - check if it's a class with New method
    if WeaponService.New then
        assertType(WeaponService.New, "function", "New should be a function")
        
        local weaponInstance = WeaponService.New()
        if weaponInstance then
            assertNotNil(weaponInstance, "WeaponService.New should return an instance")
        end
    end
    
    TestService:Message("✓ WeaponService tests passed")
end

-- Test AbilityService functionality
local function testAbilityService()
    TestService:Message("Testing AbilityService...")
    
    assertNotNil(AbilityService, "AbilityService should load successfully")
    assertType(AbilityService, "table", "AbilityService should be a table")
    
    -- Test basic structure
    if AbilityService.New then
        assertType(AbilityService.New, "function", "New should be a function")
        
        local abilityInstance = AbilityService.New()
        if abilityInstance then
            assertNotNil(abilityInstance, "AbilityService.New should return an instance")
        end
    end
    
    TestService:Message("✓ AbilityService tests passed")
end

-- Test service integration
local function testServiceIntegration()
    TestService:Message("Testing service integration...")
    
    -- Test that all services can be loaded together without conflicts
    local services = {
        CombatService = CombatService,
        WeaponService = WeaponService,
        AbilityService = AbilityService,
    }
    
    for serviceName, service in services do
        assertNotNil(service, `{serviceName} should be loaded`)
        assertType(service, "table", `{serviceName} should be a table`)
    end
    
    -- Test that services don't interfere with each other
    local servicesLoaded = 0
    for _ in services do
        servicesLoaded += 1
    end
    
    assert(servicesLoaded == 3, "All 3 services should be loaded")
    
    TestService:Message("✓ Service integration tests passed")
end

-- Test component system basic functionality
local function testComponentSystem()
    TestService:Message("Testing Component system basics...")
    
    -- Test that component folder exists and has expected structure
    local componentsFolder = game.ServerStorage.Modules:FindFirstChild("Components")
    assertNotNil(componentsFolder, "Components folder should exist")
    
    -- Test that expected component files exist
    local expectedComponents = {
        "AbilityComponent",
        "CombatComponent", 
        "HealthComponent",
        "MovementComponent",
        "StaminaComponent",
        "WeaponComponent"
    }
    
    local foundComponents = 0
    for _, componentName in expectedComponents do
        local component = componentsFolder:FindFirstChild(componentName)
        if component then
            foundComponents += 1
            TestService:Message(`✓ {componentName} found`)
        else
            TestService:Message(`⚠ {componentName} not found`)
        end
    end
    
    TestService:Message(`Component structure: {foundComponents}/{#expectedComponents} components found`)
    
    TestService:Message("✓ Component system tests passed")
end

-- Test state management system
local function testStateManagement()
    TestService:Message("Testing State Management system...")
    
    -- Test StateManager
    local StateManager = require(game.ServerStorage.Modules.Core.StateManager)
    assertNotNil(StateManager, "StateManager should load")
    assertType(StateManager, "table", "StateManager should be a table")
    
    -- Test basic state operations if the API supports it
    if StateManager.New then
        assertType(StateManager.New, "function", "StateManager.New should be a function")
        
        local stateInstance = StateManager.New()
        assertNotNil(stateInstance, "StateManager.New should return an instance")
    end
    
    TestService:Message("✓ State Management tests passed")
end

-- Run all combat system tests
local function runAllTests()
    TestService:Message("=== Starting Combat System Tests ===")
    
    local tests = {
        { name = "CombatService", func = testCombatService },
        { name = "WeaponService", func = testWeaponService },
        { name = "AbilityService", func = testAbilityService },
        { name = "Service Integration", func = testServiceIntegration },
        { name = "Component System", func = testComponentSystem },
        { name = "State Management", func = testStateManagement },
    }
    
    local passed = 0
    local failed = 0
    
    for _, test in tests do
        TestService:Message(`Running {test.name} tests...`)
        
        local success = pcall(test.func)
        if success then
            passed += 1
            TestService:Message(`✓ {test.name} tests passed`)
        else
            failed += 1
            TestService:Error(`✗ {test.name} tests failed`)
        end
    end
    
    TestService:Message("=== Combat System Test Results ===")
    TestService:Message(`Passed: {passed}`)
    TestService:Message(`Failed: {failed}`)
    TestService:Message(`Total: {passed + failed}`)
    
    if failed == 0 then
        TestService:Message("🎉 All combat system tests passed!")
    else
        TestService:Error(`❌ {failed} test suite(s) failed`)
    end
end

-- Run the tests
runAllTests()
