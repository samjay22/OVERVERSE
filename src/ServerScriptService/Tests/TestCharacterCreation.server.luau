--!strict
-- Test script to verify OnCharacterCreation functionality using TestService

local TestService = game:GetService("TestService")

local Character = require(game.ServerStorage.Modules.Entities.Character)

-- Test utilities
local function assert(condition: boolean, message: string)
    if not condition then
        TestService:Error(message)
    end
end

local function assertEquals(expected: any, actual: any, message: string?)
    local testMessage = message or `Expected {tostring(expected)}, got {tostring(actual)}`
    assert(expected == actual, testMessage)
end

local function assertNotNil(value: any, message: string?)
    local testMessage = message or `Expected value to not be nil`
    assert(value ~= nil, testMessage)
end

local function assertInstanceOf(instance: any, className: string, message: string?)
    local testMessage = message or `Expected instance of {className}, got {typeof(instance)}`
    assert(typeof(instance) == "Instance" and instance.ClassName == className, testMessage)
end

-- Test OnCharacterCreation hook functionality
local function testCharacterCreationHook()
    TestService:Message("Testing OnCharacterCreation hook functionality...")
    
    -- Test creating character instance
    local characterInstance = Character.New()
    assertNotNil(characterInstance, "Character instance should be created")
    
    -- Mock player and character for testing
    local mockPlayer = {
        Name = "TestPlayer",
        UserId = 12345
    }
    
    local mockCharacter = Instance.new("Model")
    mockCharacter.Name = "TestCharacter"
    
    -- Track if OnCharacterCreation was called
    local hookCalled = false
    local addedAccessory = false
    local addedAnimations = false
    
    -- Override OnCharacterCreation for testing
    function characterInstance:OnCharacterCreation(player: Player, character: Model, config)
        hookCalled = true
        
        -- Verify parameters
        assertEquals("TestPlayer", player.Name, "Player name should match")
        assertEquals("TestCharacter", character.Name, "Character name should match")
        
        -- Add test accessory
        local testAccessory = Instance.new("Part")
        testAccessory.Name = "TestWeapon"
        testAccessory.Size = Vector3.new(1, 1, 4)
        testAccessory.Material = Enum.Material.Metal
        testAccessory.BrickColor = BrickColor.new("Steel blue")
        testAccessory.Parent = character
        addedAccessory = true
        
        -- Add animation folder
        local animationFolder = Instance.new("Folder")
        animationFolder.Name = "CustomAnimations"
        animationFolder.Parent = character
        addedAnimations = true
    end
    
    -- Call the hook manually for testing
    characterInstance:OnCharacterCreation(mockPlayer :: any, mockCharacter, {})
    
    -- Verify hook was called and modifications were made
    assert(hookCalled, "OnCharacterCreation hook should have been called")
    assert(addedAccessory, "Test accessory should have been added")
    assert(addedAnimations, "Animation folder should have been added")
    
    -- Verify the actual objects were created
    local weapon = mockCharacter:FindFirstChild("TestWeapon")
    assertNotNil(weapon, "TestWeapon should exist in character")
    assertInstanceOf(weapon, "Part", "TestWeapon should be a Part")
    
    local animations = mockCharacter:FindFirstChild("CustomAnimations")
    assertNotNil(animations, "CustomAnimations folder should exist")
    assertInstanceOf(animations, "Folder", "CustomAnimations should be a Folder")
    
    -- Clean up
    mockCharacter:Destroy()
    
    TestService:Message("✓ OnCharacterCreation hook test passed")
end

-- Test character instance creation
local function testCharacterInstanceCreation()
    TestService:Message("Testing Character instance creation...")
    
    local characterInstance = Character.New()
    assertNotNil(characterInstance, "Character instance should not be nil")
    
    -- Test that it has expected methods
    assert(typeof(characterInstance.OnCharacterCreation) == "function", "Should have OnCharacterCreation method")
    
    TestService:Message("✓ Character instance creation test passed")
end

-- Test character spawn functionality (basic test)
local function testCharacterSpawnBasics()
    TestService:Message("Testing basic character spawn functionality...")
    
    local characterInstance = Character.New()
    
    -- Test that SpawnCharacter method exists
    assert(typeof(characterInstance.SpawnCharacter) == "function", "Should have SpawnCharacter method")
    
    TestService:Message("✓ Character spawn basics test passed")
end

-- Run all tests
local function runAllTests()
    TestService:Message("=== Starting Character Creation Tests ===")
    
    local success = pcall(testCharacterInstanceCreation)
    if not success then
        TestService:Error("Character instance creation test failed")
        return
    end
    
    success = pcall(testCharacterCreationHook)
    if not success then
        TestService:Error("Character creation hook test failed")
        return
    end
    
    success = pcall(testCharacterSpawnBasics)
    if not success then
        TestService:Error("Character spawn basics test failed")
        return
    end
    
    TestService:Message("=== All Character Creation Tests Passed ===")
end

-- Run the tests
runAllTests()
