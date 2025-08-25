--!strict
-- Ability Component - Self-contained component for managing character abilities

local BaseComponent = require(script.Parent.BaseComponent)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)
local ClientAbilityTypes = require(game.ReplicatedStorage.Modules.Types.AbilityTypes)
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)

local CENTERALIZED_COOLDOWNS : {[Player] : {[string]: number}} = {}

type AbilityComponentData = {
    Loadout: AbilityTypes.Loadout,
    Cooldowns: { [string]: number },
    ActiveAbilities: { [string]: boolean },
    LastActivation: { [string]: number },
    PassiveModifiers: {[string]: number},
    KeyBindings: {[string]: string?},
    LastCooldownCheck: number,
}

export type AbilityComponent = BaseComponent.BaseComponent & {
    Activate: (self: AbilityComponent, player: Player, abilityId: string, ctxExtra: {[string]: any}?) -> boolean,
    HandleInput: (self: AbilityComponent, player: Player, action: string, isDown: boolean, meta: {[string]: any}?) -> boolean,
    GetLoadout: (self: AbilityComponent, playerId: number) -> AbilityTypes.Loadout?,
    SetLoadout: (self: AbilityComponent, characterData: CharacterTypes.internalCharacter, loadout: AbilityTypes.Loadout) -> (),
    RemapBinding: (self: AbilityComponent, player: Player, binding: string, abilityId: string?) -> boolean,
    IsOnCooldown: (self: AbilityComponent, characterData: CharacterTypes.internalCharacter, abilityId: string) -> boolean,
    GetCooldownRemaining: (self: AbilityComponent, characterData: CharacterTypes.internalCharacter, abilityId: string) -> number,
}

-- Constants
local OFFSET = 100000
local SLOT_KEYS = {"Q", "E", "R", "F"}

-- Passive ability modifiers
local PASSIVE_MODIFIERS = {
    Keen = {
        CriticalChance = 0.15,
        CriticalDamage = 0.25,
    },
    -- Add more passive abilities here
}

-- Store component instances by player ID for quick access
local componentsByPlayerId: {[number]: AbilityComponentData} = {}

local AbilityComponent = BaseComponent:extend("Ability") :: any

function AbilityComponent:Initialize(characterData: CharacterTypes.internalCharacter, config: any?)
    BaseComponent.Initialize(self, characterData, config)
    
    -- Get loadout from config or use character's default
    local loadout: AbilityTypes.Loadout
    if config and (config :: any).AbilityLoadout then
        loadout = (config :: any).AbilityLoadout
    else
        -- Try to get loadout based on character class
        local Constants = require(game.ReplicatedStorage.Modules.Utility.Constants)
        local LoadoutRegistry = require(game.ServerStorage.Modules.registery.Loadouts)
        
        local classId = characterData.ClassId or Constants.CHARACTER_ASSET_DEFAULT
        loadout = LoadoutRegistry.Get(classId)
    end
    
    local componentData: AbilityComponentData = {
        Loadout = loadout,
        Cooldowns = {},
        ActiveAbilities = {},
        LastActivation = {},
        PassiveModifiers = {},
        KeyBindings = {},
        LastCooldownCheck = 0,
    }
    
    characterData.Components.Ability = componentData :: any
    
    -- Store in global registry for quick access
    componentsByPlayerId[characterData.PlayerId] = componentData
    
    -- Apply passive abilities if any
    if loadout.passive then
        self:_ApplyPassiveModifiers(characterData, loadout.passive, true)
    end
    
    -- Initialize key bindings in state manager
    characterData.StateManager:Set("KeyBindings", {})
    characterData.StateManager:Set("PassiveModifiers", {})
end

function AbilityComponent:Update(characterData: CharacterTypes.internalCharacter, dt: number)
    if not self:IsEnabled(characterData) then
        return
    end
    
    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then
        return
    end
    
    local currentTime = tick()
    
    -- Update cooldowns (check every 0.1 seconds to reduce overhead)
    if currentTime - component.LastCooldownCheck > 0.1 then
        component.LastCooldownCheck = currentTime
        
        for abilityId, cooldownEnd in pairs(component.Cooldowns) do
            if currentTime >= cooldownEnd then
                component.Cooldowns[abilityId] = nil
            end
        end
    end
    
    -- Update active ability durations if needed
    for abilityId, isActive in pairs(component.ActiveAbilities) do
        if isActive then
            local lastActivation = component.LastActivation[abilityId] or 0
            local duration = self:_GetAbilityDuration(abilityId)
            if duration and (currentTime - lastActivation) > duration then
                component.ActiveAbilities[abilityId] = false
            end
        end
    end
end

function AbilityComponent:Cleanup(characterData: CharacterTypes.internalCharacter)
    -- Remove from global registry
    componentsByPlayerId[characterData.PlayerId] = nil
    
    -- Remove passive effects if any
    local component = characterData.Components.Ability :: AbilityComponentData
    if component and component.Loadout.passive then
        self:_ApplyPassiveModifiers(characterData, component.Loadout.passive, false)
    end
    
    BaseComponent.Cleanup(self, characterData)
end

function AbilityComponent:Activate(player: Player, abilityId: string, ctxExtra: {[string]: any}?): boolean
    local characterData = self:_GetCharacterData(player)
    if not characterData then
        return false
    end
    
    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then
        return false
    end
    
    -- Check if already casting
    if characterData.StateManager:Get("CastingAbility") then
        return false
    end
    
    -- Check if ability exists in loadout
    if not self:_HasAbility(component, abilityId) then
        return false
    end
    
    -- Check cooldown
    if self:IsOnCooldown(characterData, abilityId) then
        return false
    end
    
    -- Check if player is alive and not stunned
    local isStunned = characterData.StateManager:Get("IsStunned")
    local isDead = characterData.StateManager:Get("IsDead")
    if isStunned or isDead then
        return false
    end
    
    -- Set casting state
    characterData.StateManager:Set("CastingAbility", true)
    
    -- Execute the ability
    local success = self:_ExecuteAbility(player, characterData, abilityId, ctxExtra)
    
    if success then
        -- Mark as active
        component.ActiveAbilities[abilityId] = true
        component.LastActivation[abilityId] = tick()
        
        -- Start cooldown
        local cooldown = self:_GetAbilityCooldown(abilityId)
        if cooldown and cooldown > 0 then
            component.Cooldowns[abilityId] = tick() + cooldown
        end
    end
    
    -- Clear casting state
    characterData.StateManager:Set("CastingAbility", false)
    
    return success
end

function AbilityComponent:HandleInput(player: Player, action: string, isDown: boolean, meta: {[string]: any}?): boolean
    local characterData = self:_GetCharacterData(player)
    if not characterData then
        return false
    end
    
    -- Update last input timestamp
    characterData.StateManager:Set("LastInputTS", (meta and meta.tsServer) or os.time())
    
    -- Route to appropriate handler
    if action == "M1" then
        return self:_HandleM1(player, characterData, isDown, meta)
    elseif action == "M2" then
        return self:_HandleM2(player, characterData, isDown, meta)
    elseif string.sub(action, 1, 4) == "Slot" then
        return self:_HandleSlot(player, characterData, action, isDown, meta)
    else
        -- Try to activate as ability
        if isDown then
            return self:Activate(player, action, meta)
        end
    end
    
    return false
end

function AbilityComponent:GetLoadout(playerId: number): AbilityTypes.Loadout?
    -- Get from component registry
    local componentData = componentsByPlayerId[playerId]
    if componentData then
        return componentData.Loadout
    end
    
    -- Try to get from character data if not in registry yet
    local CharacterManager = require(game.ServerStorage.Modules.Entities.Character.CharacterManager)
    local characterData = CharacterManager:GetCharacterData(playerId) :: any
    if characterData and characterData.Components and characterData.Components.Ability then
        local component = characterData.Components.Ability :: AbilityComponentData
        return component.Loadout
    end
    
    -- Return default loadout as fallback
    local LoadoutRegistry = require(game.ServerStorage.Modules.registery.Loadouts)
    return LoadoutRegistry.Get("Default")
end

function AbilityComponent:SetLoadout(characterData: CharacterTypes.internalCharacter, loadout: AbilityTypes.Loadout)
    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then
        return
    end
    
    -- Remove old passive if any
    if component.Loadout.passive then
        self:_ApplyPassiveModifiers(characterData, component.Loadout.passive, false)
    end
    
    -- Update loadout
    component.Loadout = loadout
    componentsByPlayerId[characterData.PlayerId] = component
    
    -- Apply new passive if any
    if loadout.passive then
        self:_ApplyPassiveModifiers(characterData, loadout.passive, true)
    end
    
    -- Clear cooldowns for abilities not in new loadout
    for abilityId in pairs(component.Cooldowns) do
        if not self:_HasAbility(component, abilityId) then
            component.Cooldowns[abilityId] = nil
            component.ActiveAbilities[abilityId] = nil
        end
    end
end

function AbilityComponent:RemapBinding(player: Player, binding: string, abilityId: string?): boolean
    local characterData = self:_GetCharacterData(player)
    if not characterData then
        return false
    end
    
    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then
        return false
    end
    
    -- Handle M1/M2 bindings
    if binding == "M1" or binding == "M2" then
        component.KeyBindings[binding .. "Ability"] = abilityId
        
        local binds = table.clone(characterData.StateManager:Get("KeyBindings") or {})
        binds[binding .. "Ability"] = abilityId
        characterData.StateManager:Set("KeyBindings", binds)
        return true
    end
    
    -- Handle slot bindings
    local slot = tonumber(string.sub(binding, 5))
    if slot and slot >= 1 and slot <= 4 then
        local newLoadout = table.clone(component.Loadout)
        newLoadout.actives = table.clone(newLoadout.actives or {})
        newLoadout.actives[slot] = abilityId
        self:SetLoadout(characterData, newLoadout)
        return true
    end
    
    return false
end

function AbilityComponent:IsOnCooldown(characterData: CharacterTypes.internalCharacter, abilityId: string): boolean
    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then
        return false
    end
    
    local cooldownEnd = component.Cooldowns[abilityId]
    return cooldownEnd ~= nil and tick() < cooldownEnd
end

function AbilityComponent:GetCooldownRemaining(characterData: CharacterTypes.internalCharacter, abilityId: string): number
    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then
        return 0
    end
    
    local cooldownEnd = component.Cooldowns[abilityId]
    if cooldownEnd then
        return math.max(0, cooldownEnd - tick())
    end
    
    return 0
end

-- Private helper methods
function AbilityComponent:_HandleM1(player: Player, characterData: CharacterTypes.internalCharacter, isDown: boolean, meta: {[string]: any}?): boolean
    if not isDown then return true end
    
    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then return false end
    
    -- Check for ability override
    local abilityId = component.KeyBindings.M1Ability or (component.Loadout.primaryAttacks and component.Loadout.primaryAttacks[1])
    
    if abilityId then
        return self:Activate(player, abilityId, meta)
    end
    
    -- No ability bound - let combat system handle default attack
    return false
end

function AbilityComponent:_HandleM2(player: Player, characterData: CharacterTypes.internalCharacter, isDown: boolean, meta: {[string]: any}?): boolean
    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then return false end
    
    -- Check for ability override
    local abilityId = component.KeyBindings.M2Ability or (component.Loadout.primaryAttacks and component.Loadout.primaryAttacks[2])
    
    if abilityId then
        if isDown then
            return self:Activate(player, abilityId, meta)
        end
        return true
    end
    
    -- No ability bound - let combat system handle default block
    return false
end

function AbilityComponent:_HandleSlot(player: Player, characterData: CharacterTypes.internalCharacter, action: string, isDown: boolean, meta: {[string]: any}?): boolean
    if not isDown then return false end
    
    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then return false end
    
    -- Extract slot number
    local slot = tonumber(string.sub(action, 5))
    if not slot or slot < 1 or slot > 4 then
        return false
    end
    
    -- Get ability for this slot
    local abilityId = component.Loadout.actives and component.Loadout.actives[slot]
    if abilityId then
        return self:Activate(player, abilityId, meta)
    end
    
    return false
end

function AbilityComponent:_HasAbility(component: AbilityComponentData, abilityId: string): boolean
    -- Check actives
    if component.Loadout.actives then
        for _, id in ipairs(component.Loadout.actives) do
            if id == abilityId then
                return true
            end
        end
    end
    
    -- Check primary attacks
    if component.Loadout.primaryAttacks then
        for _, id in ipairs(component.Loadout.primaryAttacks) do
            if id == abilityId then
                return true
            end
        end
    end
    
    -- Check passive
    if component.Loadout.passive == abilityId then
        return true
    end
    
    return false
end

function AbilityComponent:_ExecuteAbility(player: Player, characterData: CharacterTypes.internalCharacter, abilityId: string, ctxExtra: {[string]: any}?): boolean
    -- Parse ability ID (format: "ClassName-AbilityName")
    local parts = string.split(abilityId, "-")
    if #parts < 2 then
        warn("Invalid ability ID format:", abilityId)
        return false
    end
    
    local className = parts[1]
    local abilityName = parts[2]
    
    -- Try to find and execute the ability module
    local Abilities = game.ReplicatedStorage.Modules:FindFirstChild("Abilities")
    if not Abilities then
        warn("Abilities folder not found")
        return false
    end
    
    local classModule = Abilities:FindFirstChild(className)
    if not classModule then
        warn("Class module not found:", className)
        return false
    end
    
    local ok, module = pcall(require, classModule)
    if not ok then
        warn("Failed to require class module:", module)
        return false
    end
    
    local abilityModule = module[abilityName]
    if not abilityModule then
        warn("Ability not found in class:", abilityName)
        return false
    end
    
    -- Execute server validation
    if abilityModule.Server and abilityModule.Server.Validate then
        if not abilityModule.Server.InternalState.Cooldowns then
            abilityModule.Server.InternalState.Cooldowns = CENTERALIZED_COOLDOWNS
        end

        local success = abilityModule.Server:Validate(player, ctxExtra)
        if success then
            -- Fire network event for client replication
            local NetworkManager = require(game.ServerStorage.Modules.Core.NetworkManager)
            if NetworkManager and player then
                -- Commented out to reduce spam
                -- warn("Ability activated:", abilityId)
            end
        end
        return success
    end
    
    return false
end

function AbilityComponent:_GetAbilityCooldown(abilityId: string): number?
    -- Get from ability registry
    local AbilityRegistry = require(game.ServerStorage.Modules.registery.Abilities)
    local abilityDef = AbilityRegistry.GetAbility(abilityId)
    
    if abilityDef and abilityDef.cooldown then
        return abilityDef.cooldown
    end
    
    -- Default cooldowns based on ability type
    if string.find(abilityId, "M1") then
        return 0.5
    elseif string.find(abilityId, "M2") then
        return 0.3
    else
        return 1 -- Default 1 second for other abilities
    end
end

function AbilityComponent:_GetAbilityDuration(abilityId: string): number?
    -- Get from ability registry
    local AbilityRegistry = require(game.ServerStorage.Modules.registery.Abilities)
    local abilityDef = AbilityRegistry.GetAbility(abilityId)
    return abilityDef and abilityDef.duration
end

function AbilityComponent:_ApplyPassiveModifiers(characterData: CharacterTypes.internalCharacter, passiveId: string, isEquipping: boolean)
    local stateManager = characterData.StateManager
    if not stateManager then return end
    
    local modifiers = PASSIVE_MODIFIERS[passiveId]
    if not modifiers then return end
    
    local currentModifiers = stateManager:Get("PassiveModifiers") or {}
    
    for stat, value in pairs(modifiers) do
        local current = currentModifiers[stat] or 0
        currentModifiers[stat] = isEquipping 
            and (current + value) 
            or math.max(0, current - value)
    end
    
    stateManager:Set("PassiveModifiers", currentModifiers)
end

function AbilityComponent:_GetCharacterData(player: Player): CharacterTypes.internalCharacter?
    -- Use CharacterManager singleton to get character data
    local CharacterManager = require(game.ServerStorage.Modules.Entities.Character.CharacterManager)
    return CharacterManager:GetCharacterData(player) :: any
end

-- Create singleton instance for backward compatibility
local instance = AbilityComponent.new()

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
    
    Activate = function(player, abilityId, ctxExtra)
        return instance:Activate(player, abilityId, ctxExtra)
    end,
    
    HandleInput = function(player, action, isDown, meta)
        return instance:HandleInput(player, action, isDown, meta)
    end,
    
    GetLoadout = function(playerId)
        return instance:GetLoadout(playerId)
    end,
    
    SetLoadout = function(characterData, loadout)
        return instance:SetLoadout(characterData, loadout)
    end,
    
    RemapBinding = function(player, binding, abilityId)
        return instance:RemapBinding(player, binding, abilityId)
    end,
    
    -- Legacy compatibility
    PrimaryAttack = function(player, attackType)
        return instance:HandleInput(player, "M1", true, {attackType = attackType})
    end,
    
    M1 = function(player, attackType)
        return instance:HandleInput(player, "M1", true, {attackType = attackType})
    end,
    
    M2 = function(player, isDown)
        return instance:HandleInput(player, "M2", isDown, nil)
    end,

    GetStaticCooldowns = function()
        return CENTERALIZED_COOLDOWNS
    end,
}

return exports