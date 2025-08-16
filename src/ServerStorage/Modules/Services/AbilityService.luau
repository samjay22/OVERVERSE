--!strict
-- AbilityService: manages per-character ability loadouts, cooldowns, and activation

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Modules.Utility.Constants)
local CombatComponent = require(game.ServerStorage.Modules.Components.CombatComponent)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)
local AbilityRegistry = require(game.ServerStorage.Modules.registery.Abilities)

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
    return AbilityRegistry.GetActive(id)
end

function AbilityService:GetPassive(id: AbilityId): PassiveAbilityDef?
    return AbilityRegistry.GetPassive(id)
end

function AbilityService:GetAllActives(): {[AbilityId]: ActiveAbilityDef}
    local allAbilities = AbilityRegistry.GetAllAbilities()
    local actives: {[AbilityId]: ActiveAbilityDef} = {}
    for id: AbilityId, def in allAbilities do
        if def.kind == "Active" then
            actives[id] = def :: ActiveAbilityDef
        end
    end
    return actives
end

function AbilityService:GetAllPassives(): {[AbilityId]: PassiveAbilityDef}
    local allAbilities = AbilityRegistry.GetAllAbilities()
    local passives: {[AbilityId]: PassiveAbilityDef} = {}
    for id: AbilityId, def in allAbilities do
        if def.kind == "Passive" then
            passives[id] = def :: PassiveAbilityDef
        end
    end
    return passives
end

function AbilityService:GetRegistry(): typeof(AbilityRegistry)
    return AbilityRegistry
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
        local def: PassiveAbilityDef? = self:GetPassive(initial.passive)
        if def and def.onEquip then
            def.onEquip({
                player = character.Player,
                character = character,
            })
        end
    end
end

function AbilityService:Update(character: AbilityTypes.CharacterRef, dt: number)
    local state: PerCharacterAbilityState? = self:_getState(character.PlayerId)
    if not state then return end
    local passiveId: AbilityId? = state.loadout.passive
    if passiveId then
        local def: PassiveAbilityDef? = self:GetPassive(passiveId)
        if def and def.onTick then
            def.onTick({
                player = character.Player,
                character = character,
            }, dt)
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
    local untilTime: number? = state.cooldowns[abilityId]
    return not untilTime or _now() >= untilTime
end

function AbilityService:_startCooldown(playerId: number, abilityId: string, cd: number?)
    local state: PerCharacterAbilityState? = self._perCharacter[playerId]
    if not state then return end
    local duration: number = cd or 0
    if duration <= 0 then return end
    state.cooldowns[abilityId] = _now() + duration
end

function AbilityService:Activate(player: Player, abilityId: string, ctxExtra: {[string]: any}?): boolean
    local Character = require(game.ServerStorage.Modules.Entities.Character)
    local character: AbilityTypes.CharacterRef? = Character:GetCharacterData(player)
    if not character then return false end
    local pId: number = player.UserId

    local def: ActiveAbilityDef? = self:GetActive(abilityId)
    if not def then return false end

    if not self:_isOffCooldown(pId, abilityId, def.cooldown) then
        return false
    end
    if not _canPayStamina(character, def.staminaCost) then
        return false
    end

    local ok: boolean, err: string? = def.serverActivate({
        player = player,
        character = character,
        extra = ctxExtra,
    })
    if ok then
        _spendStamina(character, def.staminaCost)
        self:_startCooldown(pId, abilityId, def.cooldown)
        return true
    else
        if err then warn("Ability failed:", abilityId, err) end
        return false
    end
end

function AbilityService:PrimaryAttack(player: Player, attackType: string?): boolean
    local Character = require(game.ServerStorage.Modules.Entities.Character)
    local character: AbilityTypes.CharacterRef? = Character:GetCharacterData(player)
    if not character then return false end
    return CombatComponent.PerformAttack(character, attackType)
end

return AbilityService
