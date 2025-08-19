--!strict
-- CharacterManager - Main orchestrator for character management
-- Simplified and modular design with clear separation of concerns
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CharacterTypes = require(ServerStorage.Modules.Types.CharacterTypes)
local Constants = require(ReplicatedStorage.Modules.Utility.Constants)
local NetworkServer = require(ServerStorage.Modules.Core.NetworkServer)

local LoadoutRegistry = require(ServerStorage.Modules.registery.Loadouts)

-- Import our abstracted modules (use absolute paths to avoid script context issues)
local characterFolder = ServerStorage.Modules.Entities.Character
local CharacterAssetLoader = require(characterFolder.CharacterAssetLoader)
local CharacterEventManager = require(characterFolder.CharacterEventManager)
local ComponentManager = require(characterFolder.ComponentManager)
local CharacterFactory = require(characterFolder.CharacterFactory)
local CharacterLifecycle = require(characterFolder.CharacterLifecycle)
local CharacterUpdateLoop = require(characterFolder.CharacterUpdateLoop)
local CharacterRegistry = require(characterFolder.CharacterRegistry)

type internalCharacter = CharacterTypes.internalCharacter
type CharacterConfig = CharacterTypes.CharacterConfig
type CharacterData = CharacterTypes.Character

-- Events
local CharacterAdded = Instance.new("BindableEvent")

-- Main CharacterManager class
local CharacterManager = {}
CharacterManager.__index = CharacterManager

export type ICharacterManager = {
	SpawnCharacter: (self: ICharacterManager, player: Player, config: CharacterConfig?) -> CharacterData?,
	CleanupCharacter: (self: ICharacterManager, player: Player) -> (),
	GetCharacterData: (self: ICharacterManager, player: Player) -> CharacterData?,
	DamageCharacter: (self: ICharacterManager, player: Player, damage: number) -> boolean,
	TakeDamage: (self: ICharacterManager, player: Player, damage: number, canBlock: boolean?) -> number,
	ApplyEffect: (self: ICharacterManager, player: Player, effectOrId: any, ctxExtra: {[string]: any}?) -> boolean,
	RemoveEffect: (self: ICharacterManager, player: Player, effectId: string) -> boolean,
	GetCharacterState: (self: ICharacterManager, player: Player, stateName: string) -> any?,
	SetCharacter: (self: ICharacterManager, player: Player, config: CharacterConfig?) -> CharacterData?,
	SetCharacterState: (self: ICharacterManager, player: Player, stateName: string, value: any) -> boolean,
	RegisterComponent: (self: ICharacterManager, name: string, component: any) -> (),
	UnregisterComponent: (self: ICharacterManager, name: string) -> (),
	GetAbilityComponent: (self: ICharacterManager) -> any?,
	OnCharacterAdded: (self: ICharacterManager, callback: (CharacterData) -> ()) -> RBXScriptConnection,
	GetPerformanceMetrics: (self: ICharacterManager) -> any,
	Destroy: (self: ICharacterManager) -> (),
}

function CharacterManager.New(): ICharacterManager
	Players.CharacterAutoLoads = false
	
	local self = setmetatable({}, CharacterManager)
		-- Configuration
	self.Config = {
		DefaultRespawnTime = Constants.DEFAULT_RESPAWN_TIME or 5,
		UpdateInterval = 1/120, -- 120 Hz fixed-step to reduce server load
		MaxCharacters = 100,
		EnableAutoRespawn = false
	}
	
	-- Initialize subsystems
	self._assetLoader = CharacterAssetLoader.new()
	self._eventManager = CharacterEventManager.new()
	self._componentManager = ComponentManager.new()
	self._lifecycle = CharacterLifecycle.new()
	self._updateLoop = CharacterUpdateLoop.new(self.Config.UpdateInterval) -- Pass the interval
	self._registry = CharacterRegistry.new()
	
	-- Character registry from external module (if available)
	self._characterRegistry = nil
	do
		local ok, mod = pcall(function()
			return require((game.ServerStorage.Modules.registery :: any).Characters)
		end)
		if ok then 
			self._characterRegistry = mod
			print(`✅ CharacterRegistry loaded successfully with {mod.Count()} definitions`)
			
			-- Debug: List all loaded character definitions
			local ids = mod.GetIds()
			for _, id in ids do
				print(`  - Character definition: {id}`)
			end
		else
			warn(`❌ Failed to load CharacterRegistry: {mod}`)
		end
	end
	
	-- Create character factory with dependencies
	self._factory = CharacterFactory.new(self._assetLoader, self._eventManager, self._characterRegistry)
	
	-- Character creation hook - called before character is put in workspace
	self.OnCharacterCreation = nil :: ((player: Player, characterModel: Model, config: CharacterConfig?) -> ())?
	
	-- Remote for client communication
	self._coreRemote = nil :: RemoteEvent?
	local ok, remote = pcall(function()
		return ReplicatedStorage:WaitForChild("Remotes", 1) and ReplicatedStorage.Remotes:FindFirstChild("CoreEvent")
	end)
	if ok then
		self._coreRemote = remote :: RemoteEvent?
	end
	
	-- Initialize
	self:_Initialize()
	
	return self
end

function CharacterManager:_Initialize()
	-- Set up update loop
	self._updateLoop:SetUpdateCallback(function(dt: number)
		self:_UpdateCharacters(dt)
	end)
	
	-- Configure lifecycle
	self._lifecycle:SetConfig({
		DefaultRespawnTime = self.Config.DefaultRespawnTime,
		EnableAutoRespawn = self.Config.EnableAutoRespawn,
		MaxCharacters = self.Config.MaxCharacters,
	})
	
	-- Register built-in components
	self:_RegisterBuiltinComponents()
	
	-- Set up player events
	self:_SetupPlayerEvents()
	
	-- Load cyclic components after initial setup
	self:_LoadCyclicComponents()
	
	-- Start update loop
	self._updateLoop:Start()
end

function CharacterManager:_RegisterBuiltinComponents()
	-- Register core components
	local HealthComponent = require(ServerStorage.Modules.Components.HealthComponent)
	local StaminaComponent = require(ServerStorage.Modules.Components.StaminaComponent)
	local MovementComponent = require(ServerStorage.Modules.Components.MovementComponent)
	local CombatComponent = require(ServerStorage.Modules.Components.CombatComponent)
	local EffectComponent = require(ServerStorage.Modules.Components.EffectComponent)
	
	self._componentManager:RegisterComponent("Health", HealthComponent :: any)
	self._componentManager:RegisterComponent("Stamina", StaminaComponent :: any)
	self._componentManager:RegisterComponent("Movement", MovementComponent :: any)
	self._componentManager:RegisterComponent("Combat", CombatComponent :: any)
	self._componentManager:RegisterComponent("Effect", EffectComponent :: any)
end

function CharacterManager:_LoadCyclicComponents()
	-- Load components that have cyclic dependencies
	task.spawn(function()
		local success, AbilityComponent = pcall(require, ServerStorage.Modules.Components.AbilityComponent)
		if success then
			self._componentManager:RegisterComponent("Ability", AbilityComponent)
		else
			warn("Failed to load AbilityComponent:", AbilityComponent)
		end
		
		local success2, WeaponComponent = pcall(require, ServerStorage.Modules.Components.WeaponComponent)
		if success2 then
			self._componentManager:RegisterComponent("Weapon", WeaponComponent)
		else
			warn("Failed to load WeaponComponent:", WeaponComponent)
		end
		
		local success3, InputComponent = pcall(require, ServerStorage.Modules.Components.InputComponent)
		if success3 then
			self._componentManager:RegisterComponent("Input", InputComponent)
		else
			warn("Failed to load InputComponent:", InputComponent)
		end
	end)
end

function CharacterManager:_SetupPlayerEvents()
	print("[CharacterManager] Setting up player events...")
	-- Connect player added/removed events
	Players.PlayerAdded:Connect(function(player: Player)
		print(`[CharacterManager] Player added: {player.Name}`)
		player:SetAttribute("ClassId", "Rem")
		-- Character spawning is now manual only - no automatic spawning
		print(`[CharacterManager] Player {player.Name} ready for manual character spawn`)
	end)
	
	Players.PlayerRemoving:Connect(function(player: Player)
		print(`[CharacterManager] Player removing: {player.Name}`)
		self:CleanupCharacter(player)
	end)
end

-- Public API Methods
function CharacterManager:SpawnCharacter(player: Player, config: CharacterConfig?): CharacterData?
	print(`[CharacterManager] SpawnCharacter called for: {player.Name}`)
	local playerId = player.UserId
	
	-- Check limits
	if self._registry:GetActiveCount() >= self.Config.MaxCharacters then
		warn(`Maximum character limit ({self.Config.MaxCharacters}) reached`)
		return nil
	end
	
	-- Clean up existing character
	self:CleanupCharacter(player)
	
	-- Resolve character class definition
	local classId: CharacterTypes.CharacterClassId = (config and (config.ClassId or (config :: any).classId)) or (player:GetAttribute("ClassId") :: any) or "Default"
	local classDef = nil
	if self._characterRegistry and self._characterRegistry.Get then
		classDef = self._characterRegistry.Get(classId)
		if classDef then
			print(`✅ Found character definition for class: {classId}`)
		else
			warn(`❌ No character definition found for class: {classId}`)
		end
	else
		warn(`❌ Character registry not available`)
	end
	
	-- Create character model (but don't put it in workspace yet)
	print(`[CharacterManager] Creating character model...`)
	local characterModel = self._factory:CreateCharacterModel(player, config, false)
	if not characterModel then
		warn(`[CharacterManager] Failed to create character model for {player.Name}`)
		return nil
	end
	print(`[CharacterManager] Character model created successfully`)
	
	-- Call OnCharacterCreation hook before the character is put in workspace
	if self.OnCharacterCreation then
		local success = pcall(self.OnCharacterCreation, player, characterModel, config)
		if not success then
			warn(`OnCharacterCreation hook failed for {player.Name}`)
		end
	end
	
	local characterData = self._factory:CreateCharacterData(player, characterModel, config)
	if not characterData then
		characterModel:Destroy()
		return nil
	end

	task.spawn(function()
		-- Set up animations
		local shiftState = self:GetCharacterState(player, "ShiftState")
		local animationPack = (shiftState and LoadoutRegistry.Get(shiftState) or LoadoutRegistry.Get(classId)).animationPack
		if not animationPack then
			error(`No animation pack found for class {classId} or shift state {shiftState}`)
		end

		self._factory:SetupAnimations(characterModel, player, animationPack)
	end)
	
	-- Now put the character in the workspace
	characterModel.Parent = workspace
	
	-- Attach class information and custom fields
	characterData.Definition = classDef
	characterData.ClassId = classId
	characterData.Custom = {}
	if classDef and classDef.customFields then
		for k, v in pairs(classDef.customFields) do
			(characterData.Custom :: any)[k] = v
		end
	end
	if config and (config :: any).Custom then
		for k, v in pairs((config :: any).Custom) do
			(characterData.Custom :: any)[k] = v
		end
	end
	
	-- Run class onInit hook before components
	if classDef and classDef.hooks and classDef.hooks.onInit then
		print(`✅ Calling onInit hook for class: {classId}`)
		local success, err = pcall(classDef.hooks.onInit, characterData)
		if not success then 
			warn("Class onInit failed:", err) 
		else
			print(`✅ onInit hook completed successfully for class: {classId}`)
		end
	else
		if not classDef then
			warn(`❌ No classDef found for onInit hook`)
		elseif not classDef.hooks then
			warn(`❌ No hooks found in classDef for class: {classId}`)
		elseif not classDef.hooks.onInit then
			warn(`❌ No onInit hook found in classDef for class: {classId}`)
		end
	end
	
	-- Initialize components
	self._componentManager:InitializeComponents(characterData, config)
	
	-- Set up event connections
	self._eventManager:SetupSignalConnections(characterData, function()
		self:_HandleCharacterDeath(player)
	end)
	
	self._eventManager:SetupStateChangeSignals(characterData)
	
	-- Set up ability loadout switching based on shift state
	self:_SetupShiftStateHandling(characterData)
	
	-- Register character
	self._registry:Register(playerId, characterData)
	
	-- Handle lifecycle spawn
	self._lifecycle:HandleSpawn(characterData)
	
	-- Notify listeners
	CharacterAdded:Fire(characterData)
	
	NetworkServer:FireClient("StartCharacterAnimation", player, { "Idle" })

	-- Notify client
	if self._coreRemote then
		pcall(function()
			(self._coreRemote :: RemoteEvent):FireClient(player, "CharacterSpawned", time(), characterData.Character)
		end)
	end
	
	return characterData
end

function CharacterManager:CleanupCharacter(player: Player)
	local playerId = player.UserId
	local characterData = self._registry:Get(playerId)
	
	if not characterData then return end
	
	-- Handle lifecycle cleanup
	self._lifecycle:HandleCleanup(characterData)
	
	-- Cleanup components
	self._componentManager:CleanupComponents(characterData)
	
	-- Cleanup signals
	self._eventManager:CleanupSignals(characterData.Signals)
	
	-- Remove from registry
	self._registry:Unregister(playerId)
	
	print(`Character cleaned up for {player.Name}`)
end

function CharacterManager:GetCharacterData(player: Player): CharacterData?
	local data = self._registry:Get(player.UserId)
	return data and (data :: CharacterData) or nil
end

function CharacterManager:DamageCharacter(player: Player, damage: number): boolean
	local characterData = self._registry:Get(player.UserId)
	if not characterData or not characterData.Humanoid then
		warn(`Character data not found for player {player.Name}`)
		return false
	end
	
	local newHealth = math.max(characterData.Humanoid.Health - damage, 0)
	characterData.Humanoid.Health = newHealth
	characterData.StateManager:Set("Health", newHealth)
	
	if newHealth <= 0 then
		self:_HandleCharacterDeath(player)
	end
	
	return true
end

function CharacterManager:TakeDamage(player: Player, damage: number, canBlock: boolean?): number
	local characterData = self._registry:Get(player.UserId)
	if not characterData then return 0 end
	
	local combat = self._componentManager:GetComponent("Combat")
	local actual = damage
	if combat and combat.TakeDamage then
		local success, result = pcall(combat.TakeDamage, characterData, damage, canBlock)
		if success then actual = result end
	else
		-- Fallback direct health change
		local current = characterData.StateManager:Get("Health")
		characterData.StateManager:Set("Health", math.max(0, current - damage))
	end
	characterData.StateManager:Set("LastDamage", actual)
	return actual
end

function CharacterManager:ApplyEffect(player: Player, effectOrId: any, ctxExtra: {[string]: any}?): boolean
	local characterData = self._registry:Get(player.UserId)
	if not characterData then return false end
	
	local effectComp = self._componentManager:GetComponent("Effect")
	if not effectComp or not effectComp.GetService then return false end
	
	local service = effectComp.GetService()
	local success, err = pcall(function()
		service:Apply(characterData, effectOrId, ctxExtra)
	end)
	if not success then
		warn(`ApplyEffect failed for {player.Name}: {err}`)
	end
	return success
end

function CharacterManager:RemoveEffect(player: Player, effectId: string): boolean
	local characterData = self._registry:Get(player.UserId)
	if not characterData then return false end
	
	local effectComp = self._componentManager:GetComponent("Effect")
	if not effectComp or not effectComp.GetService then return false end
	
	local service = effectComp.GetService()
	local success, err = pcall(function()
		service:Remove(characterData, effectId)
	end)
	if not success then
		warn(`RemoveEffect failed for {player.Name}: {err}`)
	end
	return success
end

function CharacterManager:GetCharacterState(player: Player, stateName: string): any?
	local characterData = self._registry:Get(player.UserId)
	return characterData and characterData.StateManager:Get(stateName) or nil
end

function CharacterManager:SetCharacter(player: Player, config: CharacterConfig?): CharacterData?
	-- Set character configuration by respawning the character with new config
	if config then
		-- Set player attributes for persistence (handle both ClassId and classId)
		local classId = config.ClassId or (config :: any).classId
		if classId then
			player:SetAttribute("ClassId", classId)
		end
		local loadoutAssetKey = (config :: any).loadoutAssetKey
		if loadoutAssetKey then
			player:SetAttribute("LoadoutAssetKey", loadoutAssetKey)
		end
	end
	
	-- Respawn the character with the new configuration
	return self:SpawnCharacter(player, config)
end

function CharacterManager:SetCharacterState(player: Player, stateName: string, value: any): boolean
	local characterData = self._registry:Get(player.UserId)
	if characterData and characterData.StateManager then
		characterData.StateManager:Set(stateName, value)
		return true
	end
	return false
end

function CharacterManager:RegisterComponent(name: string, component: any)
	self._componentManager:RegisterComponent(name, component)
end

function CharacterManager:UnregisterComponent(name: string)
	self._componentManager:UnregisterComponent(name)
end

function CharacterManager:GetAbilityComponent()
	return self._componentManager:GetComponent("Ability")
end

function CharacterManager:OnCharacterAdded(callback: (CharacterData) -> ()): RBXScriptConnection
	return CharacterAdded.Event:Connect(function(characterData: internalCharacter)
		callback(characterData :: CharacterData)
	end)
end

function CharacterManager:GetPerformanceMetrics()
	return self._updateLoop:GetPerformanceMetrics()
end

function CharacterManager:Destroy()
	self._updateLoop:Stop()
	self._registry:Clear()
	
	-- Cleanup any remaining characters
	local playersToCleanup = {}
	for playerId, characterData in pairs(self._registry:GetAll()) do
		table.insert(playersToCleanup, characterData.Player)
	end
	for _, player in ipairs(playersToCleanup) do
		self:CleanupCharacter(player)
	end
end

-- Private helper methods
function CharacterManager:_UpdateCharacters(dt: number)
	local startTime = time()
	
	local activeList = self._registry:GetActiveList()
	
	-- Reverse iteration so we can safely remove during iteration
	for i = #activeList, 1, -1 do
		local playerId = activeList[i]
		local characterData = self._registry:GetActive(playerId)
		
		if not characterData then
			-- Orphan entry; remove from active list
			self._registry:SetActive(playerId, false)
			continue
		end
		
		-- Validate character still exists
		local char = characterData.Character
		if not char or not char.Parent then
			-- Clean up
			local player = characterData.Player or Players:GetPlayerByUserId(playerId)
			if player then
				self:CleanupCharacter(player)
			else
				-- Fallback if player vanished
				self._registry:SetActive(playerId, false)
			end
			continue
		end
		
		-- Class onUpdate hook
		local def = characterData.Definition
		if def and def.hooks and def.hooks.onUpdate then
			local success, err = pcall(def.hooks.onUpdate, characterData, dt)
			if not success then warn("Class onUpdate failed:", err) end
		end
		
		-- Update components
		self._componentManager:UpdateComponents(characterData, dt)
		
		-- Per-tick update event
		characterData.Signals.OnUpdate:Fire(dt)
		characterData._lastUpdate = time()
	end
	
	-- Update performance metrics
	local metrics = self._updateLoop:GetPerformanceMetrics()
	metrics.UpdateTime = time() - startTime
	metrics.CharacterCount = #activeList
	metrics.LastCleanup = time()
end

function CharacterManager:_HandleCharacterDeath(player: Player)
	local characterData = self._registry:Get(player.UserId)
	if not characterData then return end
	
	-- Remove from active characters
	self._registry:SetActive(player.UserId, false)
	
	-- Handle lifecycle death
	self._lifecycle:HandleDeath(characterData)
	
	-- Clean up immediately after death (triggers scheduled respawn task)
	self:CleanupCharacter(player)
end

function CharacterManager:_SetupShiftStateHandling(characterData: internalCharacter)
	-- Hook ShiftState to swap ability loadouts between Human and Beast forms
	characterData.StateManager:OnStateChange("ShiftState", function(newVal: any, _oldVal: any)
		local AbilityComponentMod = self._componentManager:GetComponent("Ability")
		if not AbilityComponentMod or not AbilityComponentMod.SetLoadout then return end
		
		-- Choose loadout assetKey per form; fallback to Default
		local AbilityLoadouts = require(game.ServerStorage.Modules.registery.Loadouts)
		local loadout = AbilityLoadouts.Get(newVal)
		AbilityComponentMod.SetLoadout(characterData, loadout)
		print("Shift state changed")
	end)
end

return CharacterManager.New()
