--!strict
-- AbilityService: manages per-character ability loadouts, cooldowns, and activation

local _ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatComponent = require(game.ServerStorage.Modules.Components.CombatComponent)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)
local ImprovedAbilityRegistry = require(game.ServerStorage.Modules.registery.ImprovedAbilityRegistry)

export type IAbilityService = AbilityTypes.IAbilityService
export type Loadout = AbilityTypes.Loadout
export type PerCharacterAbilityState = AbilityTypes.PerCharacterAbilityState
export type ActiveAbilityDef = AbilityTypes.ActiveAbilityDef
export type PassiveAbilityDef = AbilityTypes.PassiveAbilityDef
export type AbilityId = AbilityTypes.AbilityId

local AbilityService = {}
AbilityService.__index = AbilityService

function AbilityService.New()
    local self = setmetatable({}, AbilityService)
    self._perCharacter = {} :: {[number]: PerCharacterAbilityState}
    return self
end

-- Registry functions (delegate to static registry)
function AbilityService:GetActive(id: AbilityId): ActiveAbilityDef?
    return ImprovedAbilityRegistry.GetActive(id)
end

function AbilityService:GetPassive(id: AbilityId): PassiveAbilityDef?
    return ImprovedAbilityRegistry.GetPassive(id)
end

function AbilityService:GetAllActives(): {[AbilityId]: ActiveAbilityDef}
    local allAbilities = ImprovedAbilityRegistry.GetAllActives()
    local actives: {[AbilityId]: ActiveAbilityDef} = {}
    for id, def in pairs(allAbilities) do
        local idCast: AbilityId = id :: any
        actives[idCast] = def :: any
    end
    return actives
end

function AbilityService:GetAllPassives(): {[AbilityId]: PassiveAbilityDef}
    local allAbilities = ImprovedAbilityRegistry.GetAllPassives()
    local passives: {[AbilityId]: PassiveAbilityDef} = {}
    for id, def in pairs(allAbilities) do
        local idCast: AbilityId = id :: any
        passives[idCast] = def :: any
    end
    return passives
end

function AbilityService:GetRegistry(): typeof(ImprovedAbilityRegistry)
    return ImprovedAbilityRegistry
end

function AbilityService:_getState(playerId: number): PerCharacterAbilityState?
    return self._perCharacter[playerId]
end

function AbilityService:Initialize(character: AbilityTypes.CharacterRef, loadout: Loadout?)
    local playerId: number = character.PlayerId
    local initial: Loadout = loadout or {
        primaryAttack = "Default",
        actives = {},
        passive = nil,
    }
    self._perCharacter[playerId] = {
        cooldowns = {},
        loadout = initial,
    }

    if initial.passive then
        local def: PassiveAbilityDef? = self:GetPassive(initial.passive :: any)
        if def and def.onEquip then
            def.onEquip({
                player = character.Player,
                character = character,
                abilityId = initial.passive :: any,
            } :: any)
        end
    end
end

function AbilityService:Update(character: AbilityTypes.CharacterRef, dt: number)
    local state: PerCharacterAbilityState? = self:_getState(character.PlayerId)
    if not state then return end
    local passiveId: AbilityId? = state.loadout.passive
    if passiveId then
        local def: PassiveAbilityDef? = self:GetPassive(passiveId :: any)
        if def and def.onTick then
            def.onTick({
                player = character.Player,
                character = character,
                abilityId = passiveId :: any,
            } :: any, dt)
        end
    end
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
    local Character = require(game.ServerStorage.Modules.Entities.Character)
    local character: AbilityTypes.CharacterRef? = Character:GetCharacterData(player)
    if not character then return false end
    local pId: number = player.UserId

    local def: ActiveAbilityDef? = self:GetActive(abilityId :: any)
    if not def then return false end

    if not self:_isOffCooldown(pId, abilityId, def.cooldown) then
        return false
    end
    if not _canPayStamina(character, def.staminaCost) then
        return false
    end

    -- No server-side execution; client performs ability and server validates elsewhere
    _spendStamina(character, def.staminaCost)
    self:_startCooldown(pId, abilityId, def.cooldown)
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

    if action == "M2" then
        -- If an ability override is set for M2 and key is pressed, activate it; otherwise block toggle
        local m2Ability = (keyBinds and keyBinds.M2Ability) :: any
        if isDown and m2Ability then
            return self:Activate(player, m2Ability, { source = "M2", ts = ts })
        end
        return self:M2(player, isDown)
    elseif action == "M1" then
        local m1Ability = (keyBinds and keyBinds.M1Ability) :: any
        if isDown and m1Ability then
            return self:Activate(player, m1Ability, { source = "M1", ts = ts })
        end
        if isDown then
            return self:M1(player, (meta and (meta :: any).attackType) or nil)
        end
        return true
    elseif action == "Slot" then
        if not isDown then return true end
        local slot: number? = meta and (meta :: any).slot
        if not slot then return false end
        local state: PerCharacterAbilityState? = self:_getState(player.UserId)
        if not state then return false end
        local abilityId: string? = state.loadout.actives[slot]
        if not abilityId then return false end
        return self:Activate(player, abilityId, { source = `Slot{slot}`, ts = ts })
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

    -- Unequip previous passive if changed
    local prevPassive = state.loadout.passive
    if prevPassive and prevPassive ~= newLoadout.passive then
        local def = self:GetPassive(prevPassive :: any)
        if def and def.onUnequip then
            pcall(def.onUnequip, {
                player = character.Player,
                character = character,
                abilityId = prevPassive :: any,
            } :: any)
        end
    end

    state.loadout = table.clone(newLoadout)

    -- Equip new passive
    if state.loadout.passive and state.loadout.passive ~= prevPassive then
        local def = self:GetPassive(state.loadout.passive :: any)
        if def and def.onEquip then
            pcall(def.onEquip, {
                player = character.Player,
                character = character,
                abilityId = state.loadout.passive :: any,
            } :: any)
        end
    end
end

return AbilityService
