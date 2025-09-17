--!strict
-- InputComponent - Tracks client-reported input and dispatches per-frame actions

local BaseComponent = require(script.Parent.BaseComponent)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

type InputComponentData = {
    ActiveKeys: {[number]: boolean},
    PreviousKeys: {[number]: boolean},
    InputBuffer: {any},
    LastInputTime: number,
    InputEnabled: boolean,
    KeyBindings: {[string]: any},
    PrevSlotDown: {[number]: boolean},
}

export type InputComponent = BaseComponent.BaseComponent & {
    ProcessInput: (self: InputComponent, characterData: CharacterTypes.internalCharacter, inputType: Enum.UserInputType | Enum.KeyCode, isDown: boolean) -> (),
    IsKeyDown: (self: InputComponent, characterData: CharacterTypes.internalCharacter, key: Enum.UserInputType | Enum.KeyCode) -> boolean,
    WasKeyPressed: (self: InputComponent, characterData: CharacterTypes.internalCharacter, key: Enum.UserInputType | Enum.KeyCode) -> boolean,
    SetKeyBindings: (self: InputComponent, characterData: CharacterTypes.internalCharacter, bindings: {[string]: any}) -> (),
    GetKeyBindings: (self: InputComponent, characterData: CharacterTypes.internalCharacter) -> {[string]: any},
    ClearInputBuffer: (self: InputComponent, characterData: CharacterTypes.internalCharacter) -> (),
    EnableInput: (self: InputComponent, characterData: CharacterTypes.internalCharacter) -> (),
    DisableInput: (self: InputComponent, characterData: CharacterTypes.internalCharacter) -> (),
}

local OFFSET = 0
local DEFAULT_SLOT_BINDINGS: {[number]: {number}} = {
    [1] = { Enum.KeyCode.Q.Value, Enum.KeyCode.One.Value },
    [2] = { Enum.KeyCode.E.Value, Enum.KeyCode.Two.Value },
    [3] = { Enum.KeyCode.R.Value, Enum.KeyCode.Three.Value },
    [4] = { Enum.KeyCode.F.Value, Enum.KeyCode.Four.Value },
}

local InputComponent = BaseComponent:extend("Input") :: any

function InputComponent:Initialize(characterData: CharacterTypes.internalCharacter, config: any?)
    BaseComponent.Initialize(self, characterData, config)
    
    -- Create default key bindings structure
    local defaultKeyBindings = {
        Slots = {
            [1] = { numeric = DEFAULT_SLOT_BINDINGS[1] }, -- Q, 1
            [2] = { numeric = DEFAULT_SLOT_BINDINGS[2] }, -- E, 2  
            [3] = { numeric = DEFAULT_SLOT_BINDINGS[3] }, -- R, 3
            [4] = { numeric = DEFAULT_SLOT_BINDINGS[4] }, -- F, 4
        }
    }
    
    local componentData: InputComponentData = {
        ActiveKeys = {},
        PreviousKeys = {},
        InputBuffer = {},
        LastInputTime = tick(),
        InputEnabled = true,
        KeyBindings = config and config.KeyBindings or defaultKeyBindings,
        PrevSlotDown = {},
    }
    
    characterData.Components.Input = componentData :: any
    characterData.Components.InputState = { prevSlotDown = {} } -- Legacy compatibility
    
    -- Initialize key bindings in state manager
    characterData.StateManager:Set("ActiveKeys", {})
    characterData.StateManager:Set("KeyBindings", componentData.KeyBindings)
    characterData.StateManager:Set("MouseHitPosition", Vector3.new(0, 0, 0))
end

function InputComponent:Update(characterData: CharacterTypes.internalCharacter, dt: number)
    if not self:IsEnabled(characterData) then
        return
    end
    
    local component = characterData.Components.Input :: InputComponentData
    if not component or not component.InputEnabled then
        return
    end
    
    -- Get active keys from state manager
    local keysAny = characterData.StateManager:Get("ActiveKeys")
    if typeof(keysAny) ~= "table" then
        return
    end
    
    local keys = keysAny :: {[number]: boolean}
    component.ActiveKeys = keys
    
    -- Process combat inputs
    self:_ProcessCombatInputs(characterData, keys)
    
    -- Process ability inputs
    self:_ProcessAbilityInputs(characterData, keys)
    
    -- Update previous keys for next frame
    component.PreviousKeys = table.clone(keys)
    component.LastInputTime = tick()
end

function InputComponent:Cleanup(characterData: CharacterTypes.internalCharacter)
    local component = characterData.Components.Input :: InputComponentData
    if component then
        table.clear(component.ActiveKeys)
        table.clear(component.PreviousKeys)
        table.clear(component.InputBuffer)
    end
    
    if characterData.Components.InputState then
        characterData.Components.InputState = nil
    end
    
    BaseComponent.Cleanup(self, characterData)
end

function InputComponent:_ProcessCombatInputs(characterData: CharacterTypes.internalCharacter, keys: {[number]: boolean})
    -- Lazy load to avoid circular dependencies
    local AbilityComponent = self._abilityComponent
    if not AbilityComponent then
        local success, module = pcall(require, game.ServerStorage.Modules.Components.AbilityComponent)
        if success then
            self._abilityComponent = module
            AbilityComponent = module
        else
            warn("Failed to load AbilityComponent:", module)
            return
        end
    end
    
    local CombatComponent = self._combatComponent
    if not CombatComponent then
        local success, module = pcall(require, game.ServerStorage.Modules.Components.CombatComponent)
        if success then
            self._combatComponent = module
            CombatComponent = module
        else
            warn("Failed to load CombatComponent:", module)
            return
        end
    end
    
    -- Primary attack (M1) - Fully handled by scalable ability system
    local hasM1 = keys[OFFSET + Enum.UserInputType.MouseButton1.Value] == true
    if hasM1 then
        -- All ability processing now handled by:
        -- 1. ScalableAbilityHandler (client-side)
        -- 2. AbilityCastHandler (server-side)
        -- 3. AbilitySyncManager (synchronization)
        -- No direct processing needed here anymore

        -- Fallback to combat system for non-ability characters
        local player = characterData.Player or (characterData.PlayerId and game.Players:GetPlayerByUserId(characterData.PlayerId))
        if not player and CombatComponent.PerformAttack then
            CombatComponent.PerformAttack(characterData, Enums.AttackType.Default)
        end
    end
    
    -- Secondary action (M2) - Now handled by AbilityCastHandler for better client-server sync
    local hasM2 = keys[OFFSET + Enum.UserInputType.MouseButton2.Value] == true
    local player = characterData.Player or (characterData.PlayerId and game.Players:GetPlayerByUserId(characterData.PlayerId))

    if hasM2 and player and AbilityComponent then
        -- Ability activation now handled by RequestAbilityCast network event
        -- This prevents double activation and improves client-server synchronization
        -- See: AbilityCastHandler.server.luau
    elseif CombatComponent.PerformBlock then
        CombatComponent.PerformBlock(characterData, hasM2)
    end
end

function InputComponent:_ProcessAbilityInputs(characterData: CharacterTypes.internalCharacter, keys: {[number]: boolean})
    -- Lazy load to avoid circular dependencies
    local AbilityComponent = self._abilityComponent
    if not AbilityComponent then
        local success, module = pcall(require, game.ServerStorage.Modules.Components.AbilityComponent)
        if success then
            self._abilityComponent = module
            AbilityComponent = module
        else
            return
        end
    end
    
    local player = characterData.Player or (characterData.PlayerId and game.Players:GetPlayerByUserId(characterData.PlayerId))
    
    if not player or not AbilityComponent then
        return
    end
    
    local loadout = AbilityComponent:GetLoadout(characterData.PlayerId)
    local activeIds = (loadout and loadout.actives) or {}
    
    if #activeIds == 0 then
        return
    end
    
    -- Debug: Log when we're processing ability inputs
    print(`[InputComponent] Processing ability inputs for player, found {#activeIds} active abilities`)
    
    local component = characterData.Components.Input :: InputComponentData
    local prev = component.PrevSlotDown
    
    for slot = 1, 4 do
        -- Get key bindings for this slot
        local kbAny = characterData.StateManager:Get("KeyBindings")
        local slotBind = (typeof(kbAny) == "table" and (kbAny :: any).Slots and (kbAny :: any).Slots[slot]) or nil
        local codes = (slotBind and slotBind.numeric) or DEFAULT_SLOT_BINDINGS[slot]
        
        local down = false
        for _, code in ipairs(codes) do
            if keys[code] == true then
                down = true
                print(`[InputComponent] Slot {slot} key detected (code: {code})`)
                break
            end
        end
        
        local wasDown = prev[slot] == true
        if down and not wasDown then
            local abilityId = activeIds[slot]
            print(`[InputComponent] Slot {slot} pressed! AbilityId: {abilityId or "nil"}`)
            if abilityId and AbilityComponent then
                -- Re-enable direct ability activation for immediate response
                -- Note: This works alongside RequestAbilityCast for different input sources
                print(`[InputComponent] Activating ability via input: {abilityId} (slot {slot})`)
                local success = AbilityComponent.Activate(AbilityComponent, player, abilityId, nil)
                if not success then
                    warn(`[InputComponent] Failed to activate ability: {abilityId}`)
                else
                    print(`[InputComponent] Successfully activated ability: {abilityId}`)
                end
            end
        end
        
        prev[slot] = down
    end
end

function InputComponent:ProcessInput(characterData: CharacterTypes.internalCharacter, inputType: Enum.UserInputType | Enum.KeyCode, isDown: boolean)
    local component = characterData.Components.Input :: InputComponentData
    if not component or not component.InputEnabled then
        return
    end
    
    local keyValue = if typeof(inputType) == "EnumItem" then inputType.Value else 0
    component.ActiveKeys[keyValue] = isDown
    
    -- Update state manager
    characterData.StateManager:Set("ActiveKeys", component.ActiveKeys)
end

function InputComponent:IsKeyDown(characterData: CharacterTypes.internalCharacter, key: Enum.UserInputType | Enum.KeyCode): boolean
    local component = characterData.Components.Input :: InputComponentData
    if not component then
        return false
    end
    
    local keyValue = if typeof(key) == "EnumItem" then key.Value else 0
    return component.ActiveKeys[keyValue] == true
end

function InputComponent:WasKeyPressed(characterData: CharacterTypes.internalCharacter, key: Enum.UserInputType | Enum.KeyCode): boolean
    local component = characterData.Components.Input :: InputComponentData
    if not component then
        return false
    end
    
    local keyValue = if typeof(key) == "EnumItem" then key.Value else 0
    local isDown = component.ActiveKeys[keyValue] == true
    local wasDown = component.PreviousKeys[keyValue] == true
    
    return isDown and not wasDown
end

function InputComponent:SetKeyBindings(characterData: CharacterTypes.internalCharacter, bindings: {[string]: any})
    local component = characterData.Components.Input :: InputComponentData
    if not component then
        return
    end
    
    -- Merge with existing bindings
    for key, value in pairs(bindings) do
        component.KeyBindings[key] = value
    end
    
    characterData.StateManager:Set("KeyBindings", component.KeyBindings)
end

function InputComponent:GetKeyBindings(characterData: CharacterTypes.internalCharacter): {[string]: any}
    local component = characterData.Components.Input :: InputComponentData
    return component and table.clone(component.KeyBindings) or {}
end

function InputComponent:ClearInputBuffer(characterData: CharacterTypes.internalCharacter)
    local component = characterData.Components.Input :: InputComponentData
    if component then
        table.clear(component.InputBuffer)
        table.clear(component.ActiveKeys)
        table.clear(component.PreviousKeys)
    end
end

function InputComponent:EnableInput(characterData: CharacterTypes.internalCharacter)
    local component = characterData.Components.Input :: InputComponentData
    if component then
        component.InputEnabled = true
    end
end

function InputComponent:DisableInput(characterData: CharacterTypes.internalCharacter)
    local component = characterData.Components.Input :: InputComponentData
    if component then
        component.InputEnabled = false
        self:ClearInputBuffer(characterData)
    end
end

-- Create singleton instance for backward compatibility
local instance = InputComponent.new()

-- Export both instance methods and static interface for backward compatibility
local exports = {
    -- Instance (for new usage)
    Instance = instance,
    
    -- Static methods (for backward compatibility)
    Initialize = function(characterData, config)
        return instance:Initialize(characterData, config)
    end,
    
    Update = function(characterData, dt)
        return instance:Update(characterData, dt)
    end,
    
    Cleanup = function(characterData)
        return instance:Cleanup(characterData)
    end,
    
    SetKeyBindings = function(characterData, partial)
        return instance:SetKeyBindings(characterData, partial)
    end,
}

return exports