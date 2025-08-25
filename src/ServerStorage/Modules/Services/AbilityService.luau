--!strict
-- AbilityService: Optimized manager for per-character ability loadouts, cooldowns, and activation
local ServerStorage = game:GetService("ServerStorage")

local CombatComponent = require(game.ServerStorage.Modules.Components.CombatComponent)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)
local ClientAbilityTypes = require(game.ReplicatedStorage.Modules.Types.AbilityTypes)
local Character = require(game.ServerStorage.Modules.Entities.Character)
local Abilities = game.ReplicatedStorage.Modules.Abilities

-- Type exports
export type IAbilityService = AbilityTypes.IAbilityService
export type Loadout = AbilityTypes.Loadout
export type PerCharacterAbilityState = AbilityTypes.PerCharacterAbilityState
export type AbilityId = AbilityTypes.AbilityId

-- Constants
local OFFSET = 100000
local SLOT_TO_NUM_CODES = {
    [1] = { Enum.KeyCode.Q.Value, Enum.KeyCode.One.Value },
    [2] = { Enum.KeyCode.E.Value, Enum.KeyCode.Two.Value },
    [3] = { Enum.KeyCode.R.Value, Enum.KeyCode.Three.Value },
    [4] = { Enum.KeyCode.F.Value, Enum.KeyCode.Four.Value },
}

local DEFAULT_BINDINGS = {
    M1 = { numeric = { OFFSET + Enum.UserInputType.MouseButton1.Value } },
    M2 = { numeric = { OFFSET + Enum.UserInputType.MouseButton2.Value } },
}

-- Passive ability modifiers
local PASSIVE_MODIFIERS = {
    Keen = {
        CriticalChance = 0.15,
        CriticalDamage = 0.25,
    },
    -- Add more passive abilities here
}

local AbilityService = {}
AbilityService.__index = AbilityService

-- **Constructor**
function AbilityService.New()
    return setmetatable({
        _perCharacter = {} :: {[number]: PerCharacterAbilityState}
    }, AbilityService)
end

-- **Private Helper Functions**
local function normalizeLoadout(incoming: any): Loadout
    if not incoming then
        return { primaryAttacks = {}, actives = {}, passive = nil }
    end
    
    local primaryAttacks = incoming.primaryAttacks or (incoming.primaryAttack and {incoming.primaryAttack}) or {}
    
    return {
        primaryAttacks = primaryAttacks,
        actives = incoming.actives or {},
        passive = incoming.passive,
    }
end

local function createBindingEntry(input: EnumItem?): { numeric: {number} }
    if not input then
        return { numeric = {} }
    end
    
    local value = if input.EnumType == Enum.KeyCode 
        then input.Value 
        else OFFSET + input.Value
        
    return { numeric = { value } }
end

local function getCharacterSafe(player: Player): AbilityTypes.CharacterRef?
    return Character:GetCharacterData(player)
end

-- **Core Methods**
function AbilityService:Initialize(character: AbilityTypes.CharacterRef, loadout: Loadout?)
    local playerId = character.PlayerId
    local normalizedLoadout = normalizeLoadout(loadout)
    
    self._perCharacter[playerId] = {
        cooldowns = {},
        loadout = normalizedLoadout,
    }
    
    -- Apply initial passive if present
    if normalizedLoadout.passive then
        self:_applyPassiveModifiers(character, normalizedLoadout.passive, true)
    end
end

function AbilityService:Update(character: AbilityTypes.CharacterRef, dt: number)
    -- Currently no server-side updates needed
    return
end

-- **Cooldown Management**
function AbilityService:_isOffCooldown(playerId: number, abilityId: string, cd: number?): boolean
    local state = self._perCharacter[playerId]
    if not state then return false end
    
    local cooldownEnd = state.cooldowns[abilityId]
    return not cooldownEnd or time() >= cooldownEnd
end

function AbilityService:_startCooldown(playerId: number, abilityId: string, cd: number?)
    if not cd or cd <= 0 then return end
    
    local state = self._perCharacter[playerId]
    if state then
        state.cooldowns[abilityId] = time() + cd
    end
end

-- **Input Handling**
function AbilityService:HandleInput(player: Player, action: string, isDown: boolean, meta: {[string]: any}?): boolean
    local character = getCharacterSafe(player)
    if not character then return false end
    
    -- Update last input timestamp
    character.StateManager:Set("LastInputTS", (meta and meta.tsServer) or os.time())
    
    -- Route to appropriate handler
    if action == "M1" then
        return self:_handleM1(player, character, isDown, meta)
    elseif action == "M2" then
        return self:_handleM2(player, character, isDown)
    elseif action == "Slot" then
        return true -- Client predictor handles slot abilities
    end
    
    return false
end

function AbilityService:_handleM1(player: Player, character: AbilityTypes.CharacterRef, isDown: boolean, meta: {[string]: any}?): boolean
    if not isDown then return true end
    
    local keyBinds = character.StateManager:Get("KeyBindings") or {}
    local state = self._perCharacter[player.UserId]
    
    -- Check for ability override
    local abilityId = keyBinds.M1Ability or (state and state.loadout.primaryAttacks[1])
    
    if abilityId then
        return true -- Let client predictor handle
    end
    
    -- Default melee attack
    return CombatComponent.PerformAttack(character, meta and meta.attackType)
end

function AbilityService:_handleM2(player: Player, character: AbilityTypes.CharacterRef, isDown: boolean): boolean
    local keyBinds = character.StateManager:Get("KeyBindings") or {}
    local state = self._perCharacter[player.UserId]
    
    -- Check for ability override
    local abilityId = keyBinds.M2Ability or (state and state.loadout.primaryAttacks[2])
    
    if abilityId then
        return true -- Let client predictor handle
    end
    
    -- Default block
    return CombatComponent.PerformBlock(character, isDown)
end

-- **Legacy Compatibility**
function AbilityService:PrimaryAttack(player: Player, attackType: string?): boolean
    return self:M1(player, attackType)
end

function AbilityService:M1(player: Player, attackType: string?): boolean
    local character = getCharacterSafe(player)
    return character and CombatComponent.PerformAttack(character, attackType) or false
end

function AbilityService:M2(player: Player, isDown: boolean): boolean
    local character = getCharacterSafe(player)
    return character and CombatComponent.PerformBlock(character, isDown) or false
end

function AbilityService:Activate(player: Player, abilityId: string, ctxExtra: {[string]: any}?): boolean
    if Character:GetCharacterState(player, "CastingAbility") then return false end
    Character:SetCharacterState(player, "CastingAbility", true)

    local class, ability = unpack(abilityId:split("-"))
    print(class, ability)

    local classAbilities : ClientAbilityTypes.AbilityModule = require(Abilities:FindFirstChild(class))[ability] :: any
    classAbilities.Server:Validate(player)

    Character:SetCharacterState(player, "CastingAbility", false)
    return true
end

-- **Binding Management**
function AbilityService:RemapBinding(player: Player, binding: string, abilityId: string?): boolean
    local character = getCharacterSafe(player)
    if not character then return false end
    
    -- Handle M1/M2 bindings
    if binding == "M1" or binding == "M2" then
        local binds = table.clone(character.StateManager:Get("KeyBindings") or {})
        binds[binding .. "Ability"] = abilityId
        character.StateManager:Set("KeyBindings", binds)
        return true
    end
    
    -- Handle slot bindings
    local slot = tonumber(string.sub(binding, 5))
    if slot and slot >= 1 and slot <= 4 then
        local state = self._perCharacter[player.UserId]
        if not state then return false end
        
        local newLoadout = table.clone(state.loadout)
        newLoadout.actives = table.clone(newLoadout.actives or {})
        newLoadout.actives[slot] = abilityId
        state.loadout = newLoadout
        return true
    end
    
    return false
end

-- **Loadout Management**
function AbilityService:GetLoadout(playerId: number): Loadout?
    local state = self._perCharacter[playerId]
    return state and state.loadout
end

function AbilityService:SetLoadout(character: AbilityTypes.CharacterRef, newLoadout: Loadout)
    local playerId = character.PlayerId
    local state = self._perCharacter[playerId]
    
    if not state then
        self:Initialize(character, newLoadout)
        return
    end
    
    local oldLoadout = state.loadout
    state.loadout = normalizeLoadout(newLoadout)
    
    -- Handle passive changes
    self:_updatePassives(character, oldLoadout.passive, state.loadout.passive)
    
    -- Update key bindings
    self:_updateKeyBindings(character, state.loadout)
end

function AbilityService:_updateKeyBindings(character: AbilityTypes.CharacterRef, loadout: Loadout)
   
end

function AbilityService:_applyPassiveModifiers(character: AbilityTypes.CharacterRef, passiveId: AbilityId, isEquipping: boolean)
    local stateManager = character.StateManager
    if not stateManager then return end
    
    local modifiers = PASSIVE_MODIFIERS[passiveId]
    warn(modifiers)
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

-- Legacy compatibility methods
AbilityService._getState = function(self, playerId: number): PerCharacterAbilityState?
    return self._perCharacter[playerId]
end

AbilityService._equipPassive = function(self, character: AbilityTypes.CharacterRef, passiveId: AbilityId)
    self:_applyPassiveModifiers(character, passiveId, true)
end

AbilityService._unequipPassive = function(self, character: AbilityTypes.CharacterRef, passiveId: AbilityId)
    self:_applyPassiveModifiers(character, passiveId, false)
end

AbilityService._handlePassiveChanges = AbilityService._updatePassives

return AbilityService
