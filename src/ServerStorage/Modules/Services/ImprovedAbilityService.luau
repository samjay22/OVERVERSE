--!strict
-- ImprovedAbilityService: Clean, abstracted ability management with proper dependency injection
-- Separates concerns: ability logic, input handling, and character management

local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)
local CharacterService = require(game.ServerStorage.Modules.Services.CharacterService)
local ErrorHandler = require(game.ServerStorage.Modules.Utilities.ErrorHandler)

export type IAbilityService = AbilityTypes.IAbilityService
export type Loadout = AbilityTypes.Loadout
export type PerCharacterAbilityState = AbilityTypes.PerCharacterAbilityState
export type ActiveAbilityDef = AbilityTypes.ActiveAbilityDef
export type PassiveAbilityDef = AbilityTypes.PassiveAbilityDef
export type AbilityId = AbilityTypes.AbilityId
export type CharacterRef = AbilityTypes.CharacterRef

type AbilityActivationContext = {
	player: Player,
	character: CharacterRef,
	abilityId: AbilityId,
	extra: {[string]: any}?,
}

type AbilityServiceDependencies = {
	characterService: CharacterService.ICharacterService,
	abilityRegistry: any, -- Will be injected
}

local ImprovedAbilityService = {}
ImprovedAbilityService.__index = ImprovedAbilityService

-- Constructor with dependency injection
function ImprovedAbilityService.New(dependencies: AbilityServiceDependencies): IAbilityService
	local self = setmetatable({}, ImprovedAbilityService)
	
	self._perCharacter = {} :: {[number]: PerCharacterAbilityState}
	self._characterService = dependencies.characterService
	self._abilityRegistry = dependencies.abilityRegistry
	self._errorContext = ErrorHandler.CreateContext("AbilityService")
	
	return (self :: any) :: IAbilityService
end

-- Registry delegation (clean interface)
function ImprovedAbilityService:GetActive(id: AbilityId): ActiveAbilityDef?
	return ErrorHandler.SafeCallWithHandler(
		function() return self._abilityRegistry.GetActive(id) end,
		function(err) ErrorHandler.Warn(`Failed to get active ability {id}: {err}`, self._errorContext) end,
		self._errorContext
	)
end

function ImprovedAbilityService:GetPassive(id: AbilityId): PassiveAbilityDef?
	return ErrorHandler.SafeCallWithHandler(
		function() return self._abilityRegistry.GetPassive(id) end,
		function(err) ErrorHandler.Warn(`Failed to get passive ability {id}: {err}`, self._errorContext) end,
		self._errorContext
	)
end

function ImprovedAbilityService:GetAllActives(): {[AbilityId]: ActiveAbilityDef}
	local result = ErrorHandler.SafeCall(
		function() return self._abilityRegistry.GetAllActives() end,
		self._errorContext
	)
	return result.data or {}
end

function ImprovedAbilityService:GetAllPassives(): {[AbilityId]: PassiveAbilityDef}
	local result = ErrorHandler.SafeCall(
		function() return self._abilityRegistry.GetAllPassives() end,
		self._errorContext
	)
	return result.data or {}
end

-- Character state management
function ImprovedAbilityService:_getState(playerId: number): PerCharacterAbilityState?
	return self._perCharacter[playerId]
end

function ImprovedAbilityService:Initialize(character: CharacterRef, loadout: Loadout?)
	local playerId = character.PlayerId
	local initial: Loadout = loadout or self:_getDefaultLoadout()
	
	self._perCharacter[playerId] = {
		cooldowns = {},
		loadout = initial,
	}
	
	-- Equip passive if present
	if initial.passive then
		self:_equipPassive(character, initial.passive)
	end
end

function ImprovedAbilityService:Update(character: CharacterRef, dt: number)
	local state = self:_getState(character.PlayerId)
	if not state or not self._characterService:IsCharacterValid(character) then 
		return 
	end
	
	-- Update passive abilities
	if state.loadout.passive then
		self:_updatePassive(character, state.loadout.passive, dt)
	end
end

-- Ability activation with improved error handling and validation
function ImprovedAbilityService:Activate(player: Player, abilityId: string, ctxExtra: {[string]: any}?): boolean
	local context = ErrorHandler.CreateContext("AbilityService", "Activate", player.UserId)
	
	-- Validate parameters
	if not ErrorHandler.ValidateParams({player = player, abilityId = abilityId}, {"player", "abilityId"}, context) then
		return false
	end
	
	return self._characterService:WithCharacter(player, function(character)
		return self:_performActivation(player, character, abilityId, ctxExtra, context)
	end) or false
end

-- Separated activation logic for better testability
function ImprovedAbilityService:_performActivation(
	player: Player, 
	character: CharacterRef, 
	abilityId: string, 
	ctxExtra: {[string]: any}?,
	errorContext: any
): boolean
	local def = self:GetActive(abilityId :: any)
	if not def then
		ErrorHandler.Warn(`Ability not found: {abilityId}`, errorContext)
		return false
	end
	
	-- Check cooldown
	if not self:_isOffCooldown(player.UserId, abilityId, def.cooldown) then
		ErrorHandler.Debug(`Ability {abilityId} on cooldown`, errorContext)
		return false
	end
	
	-- Check stamina cost
	if not self:_canPayStamina(character, def.staminaCost) then
		ErrorHandler.Debug(`Insufficient stamina for {abilityId}`, errorContext)
		return false
	end
	
	-- Execute ability
	local _activationContext: AbilityActivationContext = {
		player = player,
		character = character,
		abilityId = abilityId :: any,
		extra = ctxExtra,
	}
	
	-- No server-side execution; assume client performs the ability and server validates elsewhere
	self:_spendStamina(character, def.staminaCost)
	self:_startCooldown(player.UserId, abilityId, def.cooldown)
	ErrorHandler.Debug(`Client-activated {abilityId} (server did not execute)`, errorContext)
	return true
end

-- Improved M1/M2 handling with delegation to combat system
function ImprovedAbilityService:M1(player: Player, attackType: string?): boolean
	return self._characterService:WithCharacter(player, function(character)
		local CombatComponent = require(game.ServerStorage.Modules.Components.CombatComponent)
		return CombatComponent.PerformAttack(character, attackType)
	end) or false
end

function ImprovedAbilityService:M2(player: Player, isDown: boolean): boolean
	return self._characterService:WithCharacter(player, function(character)
		local CombatComponent = require(game.ServerStorage.Modules.Components.CombatComponent)
		return CombatComponent.PerformBlock(character, isDown)
	end) or false
end

-- Legacy compatibility
function ImprovedAbilityService:PrimaryAttack(player: Player, attackType: string?): boolean
	return self:M1(player, attackType)
end

-- Helper methods (extracted for clarity)
function ImprovedAbilityService:_getDefaultLoadout(): Loadout
	return {
		primaryAttack = "Default",
		actives = {},
		passive = nil,
	}
end

function ImprovedAbilityService:_isOffCooldown(playerId: number, abilityId: string, cooldown: number?): boolean
	local state = self._perCharacter[playerId]
	if not state then return false end
	
	local untilTime = state.cooldowns[abilityId :: any]
	return not untilTime or time() >= untilTime
end

function ImprovedAbilityService:_startCooldown(playerId: number, abilityId: string, cooldown: number?): ()
	local state = self._perCharacter[playerId]
	if not state then return end
	
	local duration = cooldown or 0
	if duration <= 0 then return end
	
	state.cooldowns[abilityId :: any] = time() + duration
end

function ImprovedAbilityService:_canPayStamina(character: CharacterRef, cost: number?): boolean
	local staminaCost = cost or 0
	if staminaCost <= 0 then return true end
	
	local current = character.StateManager:Get("Stamina") :: number
	return current >= staminaCost
end

function ImprovedAbilityService:_spendStamina(character: CharacterRef, cost: number?): ()
	local staminaCost = cost or 0
	if staminaCost <= 0 then return end
	
	local current = character.StateManager:Get("Stamina") :: number
	character.StateManager:Set("Stamina", math.max(0, current - staminaCost))
end

function ImprovedAbilityService:_equipPassive(character: CharacterRef, passiveId: AbilityId): ()
	local def = self:GetPassive(passiveId)
	if not def or not def.onEquip then return end
	
	ErrorHandler.SafeCallWithHandler(
		function() 
			def.onEquip({
				player = character.Player,
				character = character,
				abilityId = passiveId,
			} :: any)
			return true
		end,
		function(err) 
			ErrorHandler.Warn(`Failed to equip passive {passiveId}: {err}`, self._errorContext) 
			return false
		end,
		self._errorContext
	)
end

function ImprovedAbilityService:_updatePassive(character: CharacterRef, passiveId: AbilityId, dt: number): ()
	local def = self:GetPassive(passiveId)
	if not def or not def.onTick then return end
	
	ErrorHandler.SafeCallWithHandler(
		function() 
			def.onTick({
				player = character.Player,
				character = character,
				abilityId = passiveId,
			} :: any, dt)
			return true
		end,
		function(err) 
			ErrorHandler.Debug(`Passive tick failed for {passiveId}: {err}`, self._errorContext) 
			return false
		end,
		self._errorContext
	)
end

-- Loadout management
function ImprovedAbilityService:GetLoadout(playerId: number): Loadout?
	local state = self._perCharacter[playerId]
	return state and state.loadout or nil
end

function ImprovedAbilityService:SetLoadout(character: CharacterRef, newLoadout: Loadout): ()
	local playerId = character.PlayerId
	local state = self._perCharacter[playerId]
	
	if not state then
		self:Initialize(character, newLoadout)
		return
	end
	
	-- Handle passive transitions
	local prevPassive = state.loadout.passive
	if prevPassive and prevPassive ~= newLoadout.passive then
		self:_unequipPassive(character, prevPassive)
	end
	
	state.loadout = table.clone(newLoadout)
	
	-- Equip new passive
	if state.loadout.passive and state.loadout.passive ~= prevPassive then
		self:_equipPassive(character, state.loadout.passive)
	end
end

function ImprovedAbilityService:_unequipPassive(character: CharacterRef, passiveId: AbilityId): ()
	local def = self:GetPassive(passiveId)
	if not def or not def.onUnequip then return end
	
	ErrorHandler.SafeCallWithHandler(
		function() 
			def.onUnequip({
				player = character.Player,
				character = character,
				abilityId = passiveId,
			} :: any)
			return true
		end,
		function(err) 
			ErrorHandler.Warn(`Failed to unequip passive {passiveId}: {err}`, self._errorContext) 
			return false
		end,
		self._errorContext
	)
end

return ImprovedAbilityService
