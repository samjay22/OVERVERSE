local RunService = game:GetService("RunService")
local CharacterManager = require(game.ServerStorage.Modules.Entities.Character.CharacterManager)
local StateManager = require(game.ReplicatedStorage.Modules.Utility.StateManager)

-- Lazy load AbilityComponent to avoid circular dependencies
local AbilityComponent = nil
local function getAbilityComponent()
    if not AbilityComponent then
        local success, module = pcall(require, game.ServerStorage.Modules.Components.AbilityComponent)
        if success then
            AbilityComponent = module
        else
            warn("Failed to load AbilityComponent:", module)
        end
    end
    return AbilityComponent
end

-- ===============================
-- ABILITY INPUT HANDLER MODULE
-- ===============================

local AbilityInputHandler = {}

-- Constants
local INPUT_TYPES = {
    M1 = Enum.UserInputType.MouseButton1.Value,
    M2 = Enum.UserInputType.MouseButton2.Value
}

local SLOT_KEYS = {"Q", "E", "R", "F"}
local MAX_SLOTS = 4

-- Cache for KeyCode lookups to avoid repeated iterations
local keyCodeCache = {}

-- Track active characters and their last input states
local trackedCharacters = {} -- {[character]: {lastKeys: {}, lastFired: {}, cooldowns: {}}}

-- ===============================
-- PRIVATE HELPER FUNCTIONS
-- ===============================

-- Initialize KeyCode cache for better performance
local function initializeKeyCodeCache()
    if next(keyCodeCache) then return end -- Already initialized
    
    for _, keyCode in pairs(Enum.KeyCode:GetEnumItems()) do
        keyCodeCache[keyCode.Value] = keyCode
    end
end

-- Get character data with validation
local function getCharacterData(character)
    -- Get character name safely (character is an internalCharacter type)
    local characterName = (character.Character and character.Character.Name) 
        or (character.Entity and character.Entity.name)
        or ("Player_" .. tostring(character.PlayerId))
    
    local component = getAbilityComponent()
    if not component then
        return nil
    end
    
    local loadout = component.GetLoadout(character.PlayerId)
    if not loadout then
        return nil
    end
    
    local keyBindings = StateManager.Get(character.StateManager, "KeyBindings") or {}

    return {
        loadout = loadout,
        keyBindings = keyBindings,
        character = character,
        name = characterName
    }
end

-- Process ability activation
local function activateAbility(inputType, ability, characterData)
    if not ability then return end
    
    -- Call the activation callback
    AbilityInputHandler.onAbilityActivated(inputType, ability, characterData)
end

-- ===============================
-- PUBLIC INTERFACE
-- ===============================

-- Callback function that can be overridden for custom behavior
function AbilityInputHandler.onAbilityActivated(inputType, abilityName, character)
    warn(inputType .. " ability activated:", abilityName, "for", character.name)
end

-- Process inputs for a character on each heartbeat
function AbilityInputHandler.processCharacter(character)
    local activeKeys = StateManager.Get(character.StateManager, "ActiveKeys")
    if not activeKeys then return end
    
    local characterData = getCharacterData(character)
    if not characterData then return end
    
    -- Get or create tracking data for this character
    if not trackedCharacters[character] then
        trackedCharacters[character] = {
            lastKeys = {},
            lastFired = {},
            cooldowns = {}
        }
    end
    
    local tracking = trackedCharacters[character]
    
    -- Check M1
    local m1Key = INPUT_TYPES.M1
    if activeKeys[m1Key] and not tracking.lastKeys[m1Key] then
        local ability = characterData.keyBindings.M1Ability or 
                          (characterData.loadout.primaryAttacks and characterData.loadout.primaryAttacks[1])
        if ability then
            activateAbility("M1", ability, characterData)
        end
    end
    
    -- Check M2
    local m2Key = INPUT_TYPES.M2
    if activeKeys[m2Key] and not tracking.lastKeys[m2Key] then
        local ability = characterData.keyBindings.M2Ability or 
                         (characterData.loadout.primaryAttacks and characterData.loadout.primaryAttacks[2])
        if ability then
            activateAbility("M2", ability, characterData)
        end
    end
    
    -- Check slot abilities (only on press, not hold)
    local slots = characterData.keyBindings.Slots
    local actives = characterData.loadout.actives
    
    if not slots then
        warn(`[AbilityInputHandler] No slots found in keyBindings for {characterData.name}`)
        return
    end
    
    if not actives then
        warn(`[AbilityInputHandler] No actives found in loadout for {characterData.name}`)
        return
    end
    

    if slots and actives and #activeKeys > 0 then
        for slot = 1, MAX_SLOTS do
            local slotBinding = slots[slot]
            if slotBinding and slotBinding.numeric then
                local ability = actives[slot]
                
                for _, numCode in ipairs(slotBinding.numeric) do
                    -- Use numeric key directly, not string
                    local isPressed = activeKeys[numCode]
                    local wasPressed = tracking.lastKeys[numCode]
                    
                    -- Only trigger on key press transition (not pressed -> pressed)
                    if isPressed and not wasPressed and ability then
                        activateAbility("Slot" .. slot .. "(" .. SLOT_KEYS[slot] .. ")", ability, characterData)
                        break
                    end
                end
            end
        end
    end
    
    -- Update last key states for next frame
    tracking.lastKeys = table.clone(activeKeys)
end

-- Cleanup tracking for a character
function AbilityInputHandler.cleanup(character)
    trackedCharacters[character] = nil
end

-- Initialize and set up the heartbeat loop
function AbilityInputHandler.initialize()
    initializeKeyCodeCache()
    
    -- Track characters as they're added
    local activeCharacters = {}
    
   -- Set up heartbeat to process all tracked characters
    RunService.Heartbeat:Connect(function()
		for _, plr in ipairs(game.Players:GetChildren()) do
			local char = CharacterManager:GetCharacterData(plr)
			if char then
				AbilityInputHandler.processCharacter(char)
			end
		end
    end)
    
    -- Track and clean up characters
    CharacterManager:OnCharacterAdded(function(character)
        activeCharacters[character] = true
        
        character.OnDeath.Event:Connect(function()
            activeCharacters[character] = nil
            AbilityInputHandler.cleanup(character)
        end)
    end)
end

-- ===============================
-- INITIALIZATION
-- ===============================

AbilityInputHandler.initialize()

return AbilityInputHandler