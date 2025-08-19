--!strict
-- AbilityService: manages per-character ability loadouts, cooldowns, and activation

local _ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatComponent = require(game.ServerStorage.Modules.Components.CombatComponent)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)
local ClientAbilities = require(_ReplicatedStorage.Modules.ClientAbilities)

export type IAbilityService = AbilityTypes.IAbilityService
export type Loadout = AbilityTypes.Loadout
export type PerCharacterAbilityState = AbilityTypes.PerCharacterAbilityState
-- Server no longer depends on ability registry; client modules drive behavior
export type AbilityId = AbilityTypes.AbilityId

local AbilityService = {}
AbilityService.__index = AbilityService

function AbilityService.New()
    local self = setmetatable({}, AbilityService)
    self._perCharacter = {} :: {[number]: PerCharacterAbilityState}
    return self
end

-- Normalize external/registry loadout shapes into typed Loadout
local function _normalizeLoadout(incoming: Loadout | any): Loadout
    if not incoming then
        return {
            primaryAttacks = {},
            actives = {},
            passive = nil,
        }
    end
    local pa = (incoming :: any).primaryAttacks
    local single = (incoming :: any).primaryAttack
    local normalizedPrimary = if pa ~= nil then pa elseif single ~= nil then { single } else {}
    local actives = (incoming :: any).actives or {}
    local passive = (incoming :: any).passive
    return {
        primaryAttacks = normalizedPrimary,
        actives = actives,
        passive = passive,
    }
end

-- Registry removed: no server-side ability definitions

function AbilityService:_getState(playerId: number): PerCharacterAbilityState?
    return self._perCharacter[playerId]
end

function AbilityService:Initialize(character: AbilityTypes.CharacterRef, loadout: Loadout?)
    local playerId: number = character.PlayerId
    local initial: Loadout = _normalizeLoadout(loadout)
    self._perCharacter[playerId] = {
        cooldowns = {},
        loadout = initial,
    }

    -- Passive server hooks removed; client is responsible for passive visuals/effects
end

function AbilityService:Update(character: AbilityTypes.CharacterRef, dt: number)
    local state: PerCharacterAbilityState? = self:_getState(character.PlayerId)
    if not state then return end
    -- No server passive ticking
end

local function _now(): number
    return time()
end

local function _canPayStamina(character: AbilityTypes.CharacterRef, cost: number?): boolean
    local c: number = cost or 0
    if c <= 0 then return true end
    local current: number = character.StateManager:Get("Stamina")
    return current >= c
end

local function _spendStamina(character: AbilityTypes.CharacterRef, cost: number?)
    local c: number = cost or 0
    if c <= 0 then return end
    local current: number = character.StateManager:Get("Stamina")
    character.StateManager:Set("Stamina", math.max(0, current - c))
end

function AbilityService:_isOffCooldown(playerId: number, abilityId: string, cd: number?): boolean
    local state: PerCharacterAbilityState? = self._perCharacter[playerId]
    if not state then return false end
    local untilTime: number? = state.cooldowns[abilityId :: any]
    return not untilTime or _now() >= untilTime
end

function AbilityService:_startCooldown(playerId: number, abilityId: string, cd: number?)
    local state: PerCharacterAbilityState? = self._perCharacter[playerId]
    if not state then return end
    local duration: number = cd or 0
    if duration <= 0 then return end
    state.cooldowns[abilityId :: any] = _now() + duration
end

function AbilityService:Activate(player: Player, abilityId: string, ctxExtra: {[string]: any}?): boolean
    -- Server no longer looks up or executes abilities; client predicts and server validates elsewhere
    -- Accept the request so input pipeline proceeds; authoritative checks are in ServerAbilityValidator
    return true
end

function AbilityService:PrimaryAttack(player: Player, attackType: string?): boolean
    print(player)
    local Character = require(game.ServerStorage.Modules.Entities.Character)
    local character: AbilityTypes.CharacterRef? = Character:GetCharacterData(player)
    if not character then return false end
        -- Back-compat: route to M1
        return self:M1(player, attackType)
end

-- New: Explicit M1 / M2 controls
function AbilityService:M1(player: Player, attackType: string?): boolean
    local Character = require(game.ServerStorage.Modules.Entities.Character)
    local character: AbilityTypes.CharacterRef? = Character:GetCharacterData(player)
    if not character then return false end
    return CombatComponent.PerformAttack(character, attackType)
end

function AbilityService:M2(player: Player, isDown: boolean): boolean
    local Character = require(game.ServerStorage.Modules.Entities.Character)
    local character: AbilityTypes.CharacterRef? = Character:GetCharacterData(player)
    if not character then return false end
    return CombatComponent.PerformBlock(character, isDown)
end

-- Unified input handler to avoid many one-off functions.
-- action: "M1" | "M2" | "Slot"
-- meta: { slot: number?, tsServer: number? }
function AbilityService:HandleInput(player: Player, action: string, isDown: boolean, meta: {[string]: any}?): boolean
    local Character = require(game.ServerStorage.Modules.Entities.Character)
    local character: AbilityTypes.CharacterRef? = Character:GetCharacterData(player)
    if not character then return false end

    local keyBinds = character.StateManager:Get("KeyBindings") or {}
    local ts = (meta and (meta :: any).tsServer) or os.time()
    character.StateManager:Set("LastInputTS", ts)
    local pcState: PerCharacterAbilityState? = self:_getState(player.UserId)

    if action == "M2" then
            -- Prefer explicit override (KeyBindings.M2Ability), else use loadout.primaryAttacks[2]
            -- If an ability is bound, let the client predictor handle it; otherwise default to block
            local override: string? = (keyBinds and (keyBinds :: any).M2Ability) :: any
            local pa2: string? = (pcState and pcState.loadout and (pcState.loadout.primaryAttacks or {})[2]) :: any
            local chosen: string? = override or pa2
            if chosen then
                return true
            end
            return self:M2(player, isDown)
    elseif action == "M1" then
            -- Prefer explicit override (KeyBindings.M1Ability), else use loadout.primaryAttacks[1]
            -- If an ability is bound, let the client predictor handle it; otherwise default melee
            local override: string? = (keyBinds and (keyBinds :: any).M1Ability) :: any
            local pa1: string? = (pcState and pcState.loadout and (pcState.loadout.primaryAttacks or {})[1]) :: any
            local chosen: string? = override or pa1
            if chosen then
                return true
            end
            if isDown then
                return self:M1(player, (meta and (meta :: any).attackType) or nil)
            end
            return true
    elseif action == "Slot" then
        -- Client predictor handles slot abilities; server acknowledges input
        return true
    else
        return false
    end
end

-- Convenience: Remap M1/M2 abilities or slot abilities in one place.
-- binding: "M1" | "M2" | "Slot1" | "Slot2" | "Slot3" | "Slot4"
function AbilityService:RemapBinding(player: Player, binding: string, abilityId: string?)
    local Character = require(game.ServerStorage.Modules.Entities.Character)
    local character: AbilityTypes.CharacterRef? = Character:GetCharacterData(player)
    if not character then return false end

    if binding == "M1" or binding == "M2" then
        local binds = character.StateManager:Get("KeyBindings") or {}
        local copy = table.clone(binds)
        if binding == "M1" then
            copy.M1Ability = abilityId
        else
            copy.M2Ability = abilityId
        end
        character.StateManager:Set("KeyBindings", copy)
        return true
    end

    -- Slot remap updates the loadout
    local slot = tonumber(string.sub(binding, 5))
    if slot and slot >= 1 and slot <= 4 then
        local state: PerCharacterAbilityState? = self:_getState(player.UserId)
        if not state then return false end
        local newLoadout = table.clone(state.loadout)
        newLoadout.actives = table.clone(newLoadout.actives)
        if abilityId == nil then
            newLoadout.actives[slot] = nil :: any
        else
            newLoadout.actives[slot] = abilityId :: any
        end
        state.loadout = newLoadout
        return true
    end
    return false
end
-- New: get current loadout for a character
function AbilityService:GetLoadout(playerId: number): Loadout?
    local s = self._perCharacter[playerId]
    return s and s.loadout or nil
end

-- New: apply and set a loadout for a character (handles passive equip/unequip)
function AbilityService:SetLoadout(character: AbilityTypes.CharacterRef, newLoadout: Loadout)
    local playerId = character.PlayerId
    local state = self._perCharacter[playerId]
    if not state then
        self:Initialize(character, newLoadout)
        return
    end

    local oldLoadout = state.loadout
    state.loadout = _normalizeLoadout(newLoadout)

    -- Handle passive ability changes
    self:_handlePassiveChanges(character, oldLoadout, state.loadout)

    -- Also rebuild default KeyBindings from the new loadout using ClientAbilities inputs
    local OFFSET = 100000
    local SLOT_TO_NUM_CODES: {[number]: {number}} = {
        [1] = { Enum.KeyCode.Q.Value, Enum.KeyCode.One.Value },
        [2] = { Enum.KeyCode.E.Value, Enum.KeyCode.Two.Value },
        [3] = { Enum.KeyCode.R.Value, Enum.KeyCode.Three.Value },
        [4] = { Enum.KeyCode.F.Value, Enum.KeyCode.Four.Value },
    }
    -- Legacy string key names removed; numeric-only mapping is used throughout
    local function toBindingEntry(input: EnumItem): { numeric: {number} }
        if input.EnumType == Enum.KeyCode then
            return { numeric = { (input :: any).Value } }
        elseif input.EnumType == Enum.UserInputType then
            return { numeric = { OFFSET + (input :: any).Value } }
        else
            return { numeric = {} }
        end
    end

    local binds = {
        M1 = { numeric = { OFFSET + Enum.UserInputType.MouseButton1.Value } },
        M2 = { numeric = { OFFSET + Enum.UserInputType.MouseButton2.Value } },
        Slots = {} :: { [number]: { numeric: {number} } },
    }
    local activeIds = state.loadout.actives or {}
    for slot = 1, 4 do
        local abilityId: string? = activeIds[slot]
        local entry
        if abilityId ~= nil then
            local clientMod = ClientAbilities.Get(abilityId :: any)
            if clientMod and typeof(clientMod.getAbilityInputRequired) == "function" then
                local ok, input = pcall(function()
                    return (clientMod :: any).getAbilityInputRequired()
                end)
                if ok and input ~= nil then
                    entry = toBindingEntry(input :: EnumItem)
                    -- Preserve paired number/QERF defaults if matching this slot
                    if input.EnumType == Enum.KeyCode then
                        local val = (input :: any).Value
                        local slotCodes = SLOT_TO_NUM_CODES[slot]
                        for _, code in ipairs(slotCodes) do
                            if code == val then
                                -- union with slot defaults
                                local mergedNums = {} :: {number}
                                local presentNum = {} :: {[number]: boolean}
                                for _, n in ipairs(entry.numeric) do
                                    presentNum[n] = true
                                    table.insert(mergedNums, n)
                                end
                                for _, n in ipairs(slotCodes) do
                                    if not presentNum[n] then
                                        table.insert(mergedNums, n)
                                    end
                                end
                                entry = { numeric = mergedNums }
                                break
                            end
                        end
                    end
                end
            end
        end
    if not entry or (#entry.numeric == 0) then
            entry = {
        numeric = table.clone(SLOT_TO_NUM_CODES[slot]),
            }
        end
        (binds.Slots :: any)[slot] = entry
    end
    character.StateManager:Set("KeyBindings", binds)
end

-- Handle passive ability changes when loadout is updated
function AbilityService:_handlePassiveChanges(character: AbilityTypes.CharacterRef, oldLoadout: Loadout, newLoadout: Loadout)
    local oldPassive = oldLoadout.passive
    local newPassive = newLoadout.passive

    -- Remove old passive if it changed
    if oldPassive and oldPassive ~= newPassive then
        self:_unequipPassive(character, oldPassive)
    end

    -- Equip new passive if different
    if newPassive and newPassive ~= oldPassive then
        self:_equipPassive(character, newPassive)
    end
end

-- Equip a passive ability
function AbilityService:_equipPassive(character: AbilityTypes.CharacterRef, passiveId: AbilityId)
    local stateManager = character.StateManager
    if not stateManager then return end

    -- Get current passive modifiers
    local currentModifiers = stateManager:Get("PassiveModifiers") or {}
    
    -- For now, add basic stat modifiers based on passive ID
    -- This should be replaced with proper passive ability module loading
    if passiveId == "Keen" then
        currentModifiers.CriticalChance = (currentModifiers.CriticalChance or 0) + 0.15
        currentModifiers.CriticalDamage = (currentModifiers.CriticalDamage or 0) + 0.25
    end
    -- Add more passive abilities here as needed

    stateManager:Set("PassiveModifiers", currentModifiers)
end

-- Unequip a passive ability  
function AbilityService:_unequipPassive(character: AbilityTypes.CharacterRef, passiveId: AbilityId)
    local stateManager = character.StateManager
    if not stateManager then return end

    -- Get current passive modifiers
    local currentModifiers = stateManager:Get("PassiveModifiers") or {}
    
    -- Remove stat modifiers based on passive ID
    if passiveId == "Keen" then
        currentModifiers.CriticalChance = math.max(0, (currentModifiers.CriticalChance or 0) - 0.15)
        currentModifiers.CriticalDamage = math.max(0, (currentModifiers.CriticalDamage or 0) - 0.25)
    end
    -- Add more passive abilities here as needed

    stateManager:Set("PassiveModifiers", currentModifiers)
end

return AbilityService
