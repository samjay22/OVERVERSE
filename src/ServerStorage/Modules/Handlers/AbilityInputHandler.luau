local _NetworkServer = require(game.ServerStorage.Modules.Core.NetworkServer) 
local CharacterManager = require(game.ServerStorage.Modules.Entities.Character.CharacterManager)
local AbilityComponent = require(game.ServerStorage.Modules.Components.AbilityComponent)
local StateManager = require(game.ReplicatedStorage.Modules.Utility.StateManager)

-- ===============================
-- ABILITY INPUT HANDLER MODULE
-- ===============================

local AbilityInputHandler = {}

-- Constants
local INPUT_TYPES = {
    M1 = tostring(Enum.UserInputType.MouseButton1.Value),
    M2 = tostring(Enum.UserInputType.MouseButton2.Value)
}

local SLOT_KEYS = {"Q", "E", "R", "F"}
local MAX_SLOTS = 4

-- Cache for KeyCode lookups to avoid repeated iterations
local keyCodeCache = {}

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
    local loadout = AbilityComponent.GetLoadout(character.PlayerId)
    if not loadout then
        warn("No loadout found for character", character.Name)
        return nil
    end
    
    local keyBindings = StateManager.Get(character.StateManager, "KeyBindings")
    if not keyBindings then
        warn("No key bindings found for character", character.Name)
        return nil
    end
    
    return {
        loadout = loadout,
        keyBindings = keyBindings,
        character = character
    }
end

-- Handle mouse button inputs
local function handleMouseInput(inputType, activeKeys, characterData)
    local key = INPUT_TYPES[inputType]
    if not activeKeys[key] then return end
    
    local ability
    if inputType == "M1" then
        ability = characterData.keyBindings.M1Ability or 
                 (characterData.loadout.primaryAttacks and characterData.loadout.primaryAttacks[1])
    elseif inputType == "M2" then
        ability = characterData.keyBindings.M2Ability or 
                 (characterData.loadout.primaryAttacks and characterData.loadout.primaryAttacks[2])
    end
    
    if ability then
        AbilityInputHandler.onAbilityActivated(inputType, ability, characterData.character)
    else
        warn(inputType .. " pressed but no ability bound for", characterData.character.Name)
    end
end

-- Handle slot-based ability inputs
local function handleSlotInputs(activeKeys, characterData)
    local slots = characterData.keyBindings.Slots
    local actives = characterData.loadout.actives
    
    if not slots or not actives then return end
    
    for slot = 1, MAX_SLOTS do
        local slotBinding = slots[slot]
        if slotBinding and slotBinding.numeric then
            local ability = actives[slot]
            
            -- Check if any bound keys for this slot are active
            for _, numCode in ipairs(slotBinding.numeric) do
                local keyCode = keyCodeCache[numCode]
                if keyCode and activeKeys[keyCode] then
                    if ability then
                        AbilityInputHandler.onAbilityActivated(
                            "Slot" .. slot .. "(" .. SLOT_KEYS[slot] .. ")", 
                            ability, 
                            characterData.character
                        )
                    else
                        warn("Slot", slot, "(" .. SLOT_KEYS[slot] .. ") pressed but no ability bound for", 
                             characterData.character.Name)
                    end
                    break -- Found active key for this slot, no need to check others
                end
            end
        end
    end
end

-- ===============================
-- PUBLIC INTERFACE
-- ===============================

-- Callback function that can be overridden for custom behavior
function AbilityInputHandler.onAbilityActivated(inputType, abilityName, character)
    warn(inputType .. " ability activated:", abilityName, "for", character.Name)
end

-- Main input handler
function AbilityInputHandler.handleActiveKeysChange(character, activeKeys)
    local characterData = getCharacterData(character)
    if not characterData then return end
    
    -- Handle mouse inputs
    handleMouseInput("M1", activeKeys, characterData)
    handleMouseInput("M2", activeKeys, characterData)
    
    -- Handle slot inputs
    handleSlotInputs(activeKeys, characterData)
end

-- Initialize and set up character connections
function AbilityInputHandler.initialize()
    initializeKeyCodeCache()
    
    CharacterManager:OnCharacterAdded(function(character)
        character.OnStateChange.Event:Connect(function(name, value, old)
            if name == "ActiveKeys" then
                AbilityInputHandler.handleActiveKeysChange(character, value)
            end
        end)
    end)
end

-- ===============================
-- INITIALIZATION
-- ===============================

AbilityInputHandler.initialize()


return AbilityInputHandler