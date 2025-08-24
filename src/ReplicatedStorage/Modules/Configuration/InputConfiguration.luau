--!strict
-- InputConfiguration: Flexible input binding system
-- Supports keyboard, mouse, gamepad, and custom keybinds

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

export type InputType = "keyboard" | "mouse" | "gamepad" | "touch"

export type InputBinding = {
    primary: EnumItem, -- Primary key/button
    alternate: EnumItem?, -- Alternate key/button
    modifier: EnumItem?, -- Shift, Ctrl, Alt
    holdable: boolean, -- Can be held down
    holdDelay: number?, -- Delay before hold starts
    holdRate: number?, -- Rate of repeat when held
}

export type InputProfile = {
    name: string,
    description: string?,
    bindings: {[string]: InputBinding}, -- ability slot -> binding
    deviceType: InputType,
}

export type InputConfiguration = {
    profiles: {[string]: InputProfile},
    activeProfile: string,
    customBindings: {[string]: InputBinding}?, -- User overrides
}

-- Default input profiles
local DEFAULT_PROFILES = {
    ["keyboard-mouse"] = {
        name = "Keyboard & Mouse",
        description = "Standard PC controls",
        deviceType = "keyboard",
        bindings = {
            ability_slot_1 = {
                primary = Enum.UserInputType.MouseButton1,
                holdable = true,
            },
            ability_slot_2 = {
                primary = Enum.UserInputType.MouseButton2,
                holdable = true,
            },
            ability_slot_3 = {
                primary = Enum.KeyCode.E,
                alternate = Enum.KeyCode.Three,
                holdable = false,
            },
            ability_slot_4 = {
                primary = Enum.KeyCode.Q,
                alternate = Enum.KeyCode.Four,
                holdable = false,
            },
            ability_slot_5 = {
                primary = Enum.KeyCode.R,
                alternate = Enum.KeyCode.Five,
                holdable = false,
            },
            ability_slot_6 = {
                primary = Enum.KeyCode.F,
                alternate = Enum.KeyCode.Six,
                holdable = false,
            },
            ability_reload = {
                primary = Enum.KeyCode.R,
                modifier = Enum.KeyCode.LeftShift,
                holdable = false,
            },
            ability_cancel = {
                primary = Enum.KeyCode.Escape,
                alternate = Enum.KeyCode.X,
                holdable = false,
            },
        },
    },
    
    ["gamepad"] = {
        name = "Gamepad",
        description = "Controller support",
        deviceType = "gamepad",
        bindings = {
            ability_slot_1 = {
                primary = Enum.KeyCode.ButtonR2,
                holdable = true,
            },
            ability_slot_2 = {
                primary = Enum.KeyCode.ButtonL2,
                holdable = true,
            },
            ability_slot_3 = {
                primary = Enum.KeyCode.ButtonX,
                holdable = false,
            },
            ability_slot_4 = {
                primary = Enum.KeyCode.ButtonY,
                holdable = false,
            },
            ability_slot_5 = {
                primary = Enum.KeyCode.ButtonR1,
                holdable = false,
            },
            ability_slot_6 = {
                primary = Enum.KeyCode.ButtonL1,
                holdable = false,
            },
            ability_reload = {
                primary = Enum.KeyCode.ButtonB,
                holdable = false,
            },
            ability_cancel = {
                primary = Enum.KeyCode.ButtonA,
                holdable = false,
            },
        },
    },
    
    ["mobile"] = {
        name = "Mobile",
        description = "Touch controls",
        deviceType = "touch",
        bindings = {
            -- Mobile uses on-screen buttons, these are fallbacks
            ability_slot_1 = {
                primary = Enum.UserInputType.Touch,
                holdable = true,
            },
        },
    },
}

-- Input Configuration Manager
local InputConfiguration = {}
InputConfiguration.__index = InputConfiguration

-- Private state
local currentConfig: InputConfiguration = {
    profiles = DEFAULT_PROFILES,
    activeProfile = "keyboard-mouse",
    customBindings = {},
}

local inputCallbacks: {[string]: {(pressed: boolean) -> ()}} = {}
local profileChangeCallbacks: {(profile: InputProfile) -> ()} = {}

-- Get current active profile
function InputConfiguration.GetActiveProfile(): InputProfile
    return currentConfig.profiles[currentConfig.activeProfile]
end

-- Set active profile
function InputConfiguration.SetActiveProfile(profileName: string): boolean
    if not currentConfig.profiles[profileName] then
        warn(`[InputConfiguration] Profile {profileName} not found`)
        return false
    end
    
    currentConfig.activeProfile = profileName
    
    -- Notify listeners
    local profile = currentConfig.profiles[profileName]
    for _, callback in ipairs(profileChangeCallbacks) do
        task.spawn(callback, profile)
    end
    
    return true
end

-- Get binding for ability slot
function InputConfiguration.GetBinding(slotId: string): InputBinding?
    -- Check custom bindings first
    if currentConfig.customBindings and currentConfig.customBindings[slotId] then
        return currentConfig.customBindings[slotId]
    end
    
    -- Then check active profile
    local profile = InputConfiguration.GetActiveProfile()
    return profile.bindings[slotId]
end

-- Set custom binding for a slot
function InputConfiguration.SetCustomBinding(slotId: string, binding: InputBinding)
    if not currentConfig.customBindings then
        currentConfig.customBindings = {}
    end
    
    currentConfig.customBindings[slotId] = binding
end

-- Clear custom binding
function InputConfiguration.ClearCustomBinding(slotId: string)
    if currentConfig.customBindings then
        currentConfig.customBindings[slotId] = nil
    end
end

-- Clear all custom bindings
function InputConfiguration.ClearAllCustomBindings()
    currentConfig.customBindings = {}
end

-- Check if an input matches a binding
function InputConfiguration.MatchesBinding(input: InputObject, binding: InputBinding): boolean
    -- Check modifier first
    if binding.modifier then
        local modifierPressed = UserInputService:IsKeyDown(binding.modifier)
        if not modifierPressed then
            return false
        end
    end
    
    -- Check primary key
    if input.UserInputType == binding.primary or input.KeyCode == binding.primary then
        return true
    end
    
    -- Check alternate key
    if binding.alternate and (input.UserInputType == binding.alternate or input.KeyCode == binding.alternate) then
        return true
    end
    
    return false
end

-- Get slot ID from input
function InputConfiguration.GetSlotFromInput(input: InputObject): string?
    local profile = InputConfiguration.GetActiveProfile()
    
    for slotId, binding in pairs(profile.bindings) do
        if InputConfiguration.MatchesBinding(input, binding) then
            return slotId
        end
    end
    
    -- Check custom bindings
    if currentConfig.customBindings then
        for slotId, binding in pairs(currentConfig.customBindings) do
            if InputConfiguration.MatchesBinding(input, binding) then
                return slotId
            end
        end
    end
    
    return nil
end

-- Map ability ID to slot
local abilityToSlotMap = {
    RemM1 = "ability_slot_1",
    RemM2 = "ability_slot_2",
    RemE = "ability_slot_3",
    Dash = "ability_slot_4",
    RemR = "ability_slot_5",
    RemF = "ability_slot_6",
}

-- Get slot for ability
function InputConfiguration.GetSlotForAbility(abilityId: string): string?
    return abilityToSlotMap[abilityId]
end

-- Get ability for slot
function InputConfiguration.GetAbilityForSlot(slotId: string): string?
    for abilityId, slot in pairs(abilityToSlotMap) do
        if slot == slotId then
            return abilityId
        end
    end
    return nil
end

-- Get display text for binding
function InputConfiguration.GetBindingDisplay(binding: InputBinding): string
    local text = ""
    
    -- Add modifier if exists
    if binding.modifier then
        local modifierName = binding.modifier.Name
        if modifierName:find("Shift") then
            text = "Shift+"
        elseif modifierName:find("Control") or modifierName:find("Ctrl") then
            text = "Ctrl+"
        elseif modifierName:find("Alt") then
            text = "Alt+"
        end
    end
    
    -- Add primary key
    local primaryName = binding.primary.Name
    
    -- Simplify common names
    if primaryName == "MouseButton1" then
        text = text .. "MB1"
    elseif primaryName == "MouseButton2" then
        text = text .. "MB2"
    elseif primaryName == "MouseButton3" then
        text = text .. "MB3"
    elseif primaryName:find("Button") then
        -- Gamepad button
        text = text .. primaryName:gsub("Button", "")
    else
        -- Keyboard key
        text = text .. primaryName
    end
    
    return text
end

-- Auto-detect best profile based on last input
function InputConfiguration.AutoDetectProfile()
    local lastInputType = UserInputService:GetLastInputType()
    
    if lastInputType == Enum.UserInputType.Gamepad1 or 
       lastInputType == Enum.UserInputType.Gamepad2 or
       lastInputType == Enum.UserInputType.Gamepad3 or
       lastInputType == Enum.UserInputType.Gamepad4 then
        InputConfiguration.SetActiveProfile("gamepad")
    elseif lastInputType == Enum.UserInputType.Touch then
        InputConfiguration.SetActiveProfile("mobile")
    else
        InputConfiguration.SetActiveProfile("keyboard-mouse")
    end
end

-- Subscribe to profile changes
function InputConfiguration.OnProfileChanged(callback: (profile: InputProfile) -> ()): () -> ()
    table.insert(profileChangeCallbacks, callback)
    
    -- Return disconnect function
    return function()
        local index = table.find(profileChangeCallbacks, callback)
        if index then
            table.remove(profileChangeCallbacks, index)
        end
    end
end

-- Save configuration to DataStore (for user preferences)
function InputConfiguration.SaveConfiguration(player: Player)
    -- This would save to DataStore in production
    -- For now, just store locally
    local data = {
        activeProfile = currentConfig.activeProfile,
        customBindings = currentConfig.customBindings,
    }
    
    -- In production: DataStore:SetAsync(player.UserId, data)
    return data
end

-- Load configuration from DataStore
function InputConfiguration.LoadConfiguration(player: Player, data: any?)
    if data then
        if data.activeProfile then
            currentConfig.activeProfile = data.activeProfile
        end
        if data.customBindings then
            currentConfig.customBindings = data.customBindings
        end
    end
end

-- Initialize input detection
function InputConfiguration.Initialize()
    -- Auto-detect on input change
    UserInputService.LastInputTypeChanged:Connect(function(lastInputType)
        if lastInputType == Enum.UserInputType.Gamepad1 then
            InputConfiguration.SetActiveProfile("gamepad")
        elseif lastInputType == Enum.UserInputType.Touch then
            InputConfiguration.SetActiveProfile("mobile")
        elseif lastInputType == Enum.UserInputType.Keyboard or 
                lastInputType == Enum.UserInputType.MouseButton1 then
            InputConfiguration.SetActiveProfile("keyboard-mouse")
        end
    end)
    
    -- Initial auto-detect
    InputConfiguration.AutoDetectProfile()
end

return InputConfiguration