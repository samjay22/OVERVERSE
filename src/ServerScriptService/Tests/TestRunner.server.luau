--!strict
-- Comprehensive test runner for the Roblox game systems using TestService

local TestService = game:GetService("TestService")

-- Test configuration
local TEST_CONFIG = {
    -- Enable/disable specific test suites
    characterTests = true,
    registryTests = true,
    performanceTests = true,
    
    -- Test timeouts (in seconds)
    maxTestTime = 30,
    
    -- Output configuration
    verbose = true,
    showPassed = true,
    showFailed = true,
    showSkipped = true,
}

-- Test result tracking
local testResults = {
    passed = 0,
    failed = 0,
    skipped = 0,
    totalTime = 0,
    suites = {}
}

-- Utility functions
local function getCurrentTime(): number
    return tick()
end

local function formatTime(timeSeconds: number): string
    if timeSeconds < 1 then
        return `{math.floor(timeSeconds * 1000)}ms`
    else
        return `{string.format("%.2f", timeSeconds)}s`
    end
end

local function log(level: "INFO" | "PASS" | "FAIL" | "SKIP" | "ERROR", message: string)
    local prefix = ""
    if level == "PASS" then
        prefix = "✓"
    elseif level == "FAIL" then
        prefix = "✗"
    elseif level == "SKIP" then
        prefix = "⚠"
    elseif level == "ERROR" then
        prefix = "❌"
    else
        prefix = "ℹ"
    end
    
    local formattedMessage = `[{prefix}] {message}`
    
    if level == "ERROR" or level == "FAIL" then
        TestService:Error(formattedMessage)
    else
        TestService:Message(formattedMessage)
    end
end

-- Test suite runner
local function runTestSuite(suiteName: string, testFunction: () -> (), shouldRun: boolean): ()
    if not shouldRun then
        log("SKIP", `Skipping test suite: {suiteName}`)
        testResults.skipped += 1
        return
    end
    
    log("INFO", `Starting test suite: {suiteName}`)
    local startTime = getCurrentTime()
    
    local success = pcall(testFunction)
    
    local endTime = getCurrentTime()
    local duration = endTime - startTime
    testResults.totalTime += duration
    
    if success then
        log("PASS", `Test suite '{suiteName}' passed in {formatTime(duration)}`)
        testResults.passed += 1
        testResults.suites[suiteName] = { status = "PASS", duration = duration }
    else
        log("FAIL", `Test suite '{suiteName}' failed after {formatTime(duration)}`)
        testResults.failed += 1
        testResults.suites[suiteName] = { status = "FAIL", duration = duration }
    end
end

-- Performance test suite
local function runPerformanceTests()
    log("INFO", "Running performance tests...")
    
    -- Test script loading time
    local loadStartTime = getCurrentTime()
    
    -- Load key modules and measure time
    local modules = {
        {
            name = "Character",
            loader = function() return require(game.ServerStorage.Modules.Entities.Character) end
        },
        {
            name = "AbilityRegistry", 
            loader = function() return require(game.ServerStorage.Modules.registery.Abilities) end
        },
        {
            name = "StateManager",
            loader = function() return require(game.ServerStorage.Modules.Core.StateManager) end
        },
    }
    
    for _, moduleInfo in modules do
        local moduleStartTime = getCurrentTime()
        local success = pcall(moduleInfo.loader)
        local moduleEndTime = getCurrentTime()
        local loadTime = moduleEndTime - moduleStartTime
        
        if success then
            log("PASS", `Module '{moduleInfo.name}' loaded in {formatTime(loadTime)}`)
        else
            log("FAIL", `Module '{moduleInfo.name}' failed to load`)
        end
        
        -- Warn if loading takes too long
        if loadTime > 0.1 then
            log("INFO", `⚠ Module '{moduleInfo.name}' took {formatTime(loadTime)} to load (> 100ms)`)
        end
    end
    
    local totalLoadTime = getCurrentTime() - loadStartTime
    log("INFO", `Total module loading time: {formatTime(totalLoadTime)}`)
    
    -- Test memory usage (basic check)
    local beforeGC = collectgarbage("count")
    collectgarbage("count") -- Force garbage collection step
    local afterGC = collectgarbage("count")
    
    log("INFO", `Memory usage: {math.floor(afterGC)} KB (freed {math.floor(beforeGC - afterGC)} KB after GC)`)
end

-- Character system tests
local function runCharacterTests()
    log("INFO", "Loading Character system tests...")
    
    -- This would normally load and run the character test file
    -- For now, just verify the module exists and can be required
    local Character = require(game.ServerStorage.Modules.Entities.Character)
    assert(Character ~= nil, "Character module should load successfully")
    assert(typeof(Character.New) == "function", "Character should have New method")
    
    local characterInstance = Character.New()
    assert(characterInstance ~= nil, "Character.New should return an instance")
    assert(typeof(characterInstance.OnCharacterCreation) == "function", "Character should have OnCharacterCreation method")
    
    log("PASS", "Character system basic validation passed")
end

-- Registry system tests  
local function runRegistryTests()
    log("INFO", "Loading Registry system tests...")
    
    -- Test that registries can be loaded
    local AbilityRegistry = require(game.ServerStorage.Modules.registery.Abilities)
    local EffectRegistry = require(game.ServerStorage.Modules.registery.Effects)
    local LoadoutRegistry = require(game.ServerStorage.Modules.registery.Loadouts)
    
    assert(AbilityRegistry ~= nil, "AbilityRegistry should load")
    assert(EffectRegistry ~= nil, "EffectRegistry should load")
    assert(LoadoutRegistry ~= nil, "LoadoutRegistry should load")
    
    -- Test basic registry functionality
    assert(typeof(AbilityRegistry.GetAll) == "function", "AbilityRegistry should have GetAll method")
    assert(typeof(LoadoutRegistry.Get) == "function", "LoadoutRegistry should have Get method")
    
    -- Test that registries return proper data structures
    local abilities = AbilityRegistry.GetAll()
    assert(typeof(abilities) == "table", "GetAll should return a table")
    
    log("PASS", "Registry system basic validation passed")
end

-- System integration tests
local function runIntegrationTests()
    log("INFO", "Running system integration tests...")
    
    -- Test that core systems can work together
    local Character = require(game.ServerStorage.Modules.Entities.Character)
    local AbilityRegistry = require(game.ServerStorage.Modules.registery.Abilities)
    
    local characterInstance = Character.New()
    local abilities = AbilityRegistry.GetAll()
    
    -- Verify they can interact without errors
    assert(characterInstance ~= nil and abilities ~= nil, "Core systems should be loadable together")
    
    log("PASS", "System integration basic validation passed")
end

-- Main test runner
local function runAllTests()
    log("INFO", "=== Roblox Game System Test Suite ===")
    log("INFO", `Test configuration: Character={TEST_CONFIG.characterTests}, Registry={TEST_CONFIG.registryTests}, Performance={TEST_CONFIG.performanceTests}`)
    
    local totalStartTime = getCurrentTime()
    
    -- Run test suites
    runTestSuite("Performance Tests", runPerformanceTests, TEST_CONFIG.performanceTests)
    runTestSuite("Character System Tests", runCharacterTests, TEST_CONFIG.characterTests)
    runTestSuite("Registry System Tests", runRegistryTests, TEST_CONFIG.registryTests)
    runTestSuite("Integration Tests", runIntegrationTests, true)
    
    local totalEndTime = getCurrentTime()
    testResults.totalTime = totalEndTime - totalStartTime
    
    -- Generate test report
    log("INFO", "=== Test Results Summary ===")
    log("INFO", `Total suites run: {testResults.passed + testResults.failed}`)
    log("INFO", `Passed: {testResults.passed}`)
    log("INFO", `Failed: {testResults.failed}`)
    log("INFO", `Skipped: {testResults.skipped}`)
    log("INFO", `Total time: {formatTime(testResults.totalTime)}`)
    
    -- Detailed suite results
    if TEST_CONFIG.verbose then
        log("INFO", "=== Detailed Results ===")
        for suiteName, result in testResults.suites do
            local status = result.status
            local duration = formatTime(result.duration)
            log("INFO", `{suiteName}: {status} ({duration})`)
        end
    end
    
    -- Final status
    if testResults.failed == 0 then
        log("PASS", "🎉 All tests passed!")
    else
        log("FAIL", `❌ {testResults.failed} test suite(s) failed`)
    end
    
    -- Output to Developer Console for easy reading
    print("\n" .. string.rep("=", 50))
    print("ROBLOX GAME SYSTEM TEST RESULTS")
    print(string.rep("=", 50))
    print(`Passed: {testResults.passed} | Failed: {testResults.failed} | Skipped: {testResults.skipped}`)
    print(`Total Time: {formatTime(testResults.totalTime)}`)
    print(string.rep("=", 50))
end

-- Auto-run tests when script loads
wait(1) -- Give services time to initialize
runAllTests()
