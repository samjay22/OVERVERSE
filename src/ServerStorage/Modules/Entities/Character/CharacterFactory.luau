--!strict
-- CharacterFactory - Responsible for creating character models and data
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)
local StateManager = require(game.ReplicatedStorage.Modules.Utility.StateManager)
local CharacterStates = require(game.ServerStorage.Modules.Utilities.CharacterStates)
local Effects = require(game.ReplicatedStorage.Modules.AssetHandlers).OnModuleLoaded("Effects")

type internalCharacter = CharacterTypes.internalCharacter
type CharacterConfig = CharacterTypes.CharacterConfig
type CharacterDefinition = CharacterTypes.CharacterDefinition
type CharacterClassId = CharacterTypes.CharacterClassId
type EntityRef = CharacterTypes.EntityRef

export type ICharacterFactory = {
	CreateCharacterModel: (self: ICharacterFactory, entity: EntityRef, config: CharacterConfig?, parentToWorkspace: boolean?) -> Model?,
	CreateCharacterData: (self: ICharacterFactory, entity: EntityRef, characterModel: Model, config: CharacterConfig?) -> internalCharacter?,
	SetupAnimations: (self: ICharacterFactory, characterModel: Model, entity: EntityRef, animationPack: string?) -> (),
}

local CharacterFactory = {}
CharacterFactory.__index = CharacterFactory

function CharacterFactory.new(assetLoader: any, eventManager: any, characterRegistry: any?): ICharacterFactory
	local self = setmetatable({}, CharacterFactory)
	
	self._assetLoader = assetLoader
	self._eventManager = eventManager
	self._characterRegistry = characterRegistry
	
	-- Performance optimization: Pre-cache frequently used data
	self._defaultEffects = {} :: {[string]: Instance}
	self._animationCache = {} :: {[string]: {[string]: Animation}}
	self._modelPool = {} :: {Model} -- Pool of pre-created character models
	
	-- Async initialization of caches
	task.spawn(function()
		self:_PreloadAssets()
	end)
	
	return (self :: any) :: ICharacterFactory
end

-- Preload commonly used assets for better performance
function CharacterFactory:_PreloadAssets()
	-- Preload default effects
	local effects = Effects
	if effects then
		local allEffects = effects.GetAllAssets()
		local effectCount = 0
		for effectName, effectData in pairs(allEffects) do
			if effectName:find("Rem:") and effectData.Instance then
				local cleanName = effectName:split(":")[2] or effectName
				self._defaultEffects[cleanName] = effectData.Instance
				effectCount = effectCount + 1
			end
		end
	end
	
	-- Preload common animation packs
	local commonPacks = {"Default", "Rem", "Ram"}
	local packCount = 0
	for _, packName in ipairs(commonPacks) do
		local animAsset = self._assetLoader:GetAnimationAsset(packName)
		if animAsset then
			self._animationCache[packName] = {}
			for animName, assetValue in pairs(animAsset) do
				if assetValue.Instance and assetValue.Instance:IsA("Animation") then
					self._animationCache[packName][animName] = assetValue.Instance
				end
			end
			packCount = packCount + 1
		end
	end
	
	local effectCount = 0
	for _ in pairs(self._defaultEffects) do
		effectCount = effectCount + 1
	end
	
	print(`✅ CharacterFactory preloaded {effectCount} effects and {packCount} animation packs`)
end

function CharacterFactory:CreateCharacterModel(entity: EntityRef, config: CharacterConfig?, parentToWorkspace: boolean?): Model?
	print(`[CharacterFactory] Creating character model for: {entity.name}`)
	
	-- Get character asset
	local characterAsset = self._assetLoader:GetCharacterAsset()
	print(`[CharacterFactory] Asset received: {characterAsset ~= nil}`)
	if not characterAsset then
		warn(`[CharacterFactory] No character assets available for entity {entity.name}`)
		return nil
	end
	
	-- Clone and set up character
	local characterModel: Model = characterAsset:Clone()
	characterModel.Name = entity.name
	
	-- Only parent to workspace if explicitly requested (default true for backwards compatibility)
	if parentToWorkspace ~= false then
		characterModel.Parent = workspace
	end
	
	-- Guard non-standard APIs - only for players
	if entity.entityType == "Player" and entity.player then
		local modelAny = characterModel :: any
		if typeof(modelAny.AddPersistentPlayer) == "function" then
			pcall(function()
				modelAny:AddPersistentPlayer(entity.player)
			end)
		end
	end
	
	-- Set up humanoid
	local humanoid: Humanoid = characterModel:WaitForChild("Humanoid") :: Humanoid
	local maxHealth = (config and config.MaxHealth) or 100
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = (config and config.WalkSpeed) or 16

	-- Optimized effects loading using cache
	self:_LoadEffectsOptimized(characterModel)
	
	-- Set player character only for players
	if entity.entityType == "Player" and entity.player then
		entity.player.Character = characterModel
	end
	
	-- Set humanoid target point
	local primary: BasePart? = characterModel.PrimaryPart or characterModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if primary then
		humanoid.TargetPoint = (primary :: BasePart).Position
	end
	
	return characterModel
end

-- Optimized effects loading using preloaded cache
function CharacterFactory:_LoadEffectsOptimized(characterModel: Model)
	local effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "Effects"
	
	-- Use cached effects if available, otherwise fallback to dynamic loading
	local effectCount = 0
	if next(self._defaultEffects) then
		-- Use preloaded effects (faster)
		for cleanName, effectInstance in pairs(self._defaultEffects) do
			local effectClone = effectInstance:Clone()
			effectClone.Name = cleanName
			effectClone.Parent = effectsFolder
			effectCount = effectCount + 1
		end
	else
		-- Fallback to dynamic loading if cache not ready
		local effects = Effects
		if effects then
			local allEffects = effects.GetAllAssets()
			for effectName, effectData in pairs(allEffects) do
				if effectName:find("Rem:") and effectData.Instance then
					local effectClone = effectData.Instance:Clone()
					local cleanName = effectName:split(":")[2] or effectName
					effectClone.Name = cleanName
					effectClone.Parent = effectsFolder
					effectCount = effectCount + 1
				end
			end
		end
	end
	
	-- Parent the effects folder immediately to avoid race conditions
	effectsFolder.Parent = characterModel
	print(`✅ Created Effects folder with {effectCount} effects for character`)
end

function CharacterFactory:CreateCharacterData(entity: EntityRef, characterModel: Model, config: CharacterConfig?): internalCharacter?
	local humanoid = characterModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(`No humanoid found in character model for {entity.name}`)
		return nil
	end
	
	-- Create all character-level signals
	local signals = self._eventManager:CreateCharacterSignals()
	
	-- Find weapon sheath
	local sheathInst = characterModel:FindFirstChild("WeaponSheath")
	local sheathPart: BasePart? = nil
	if sheathInst and sheathInst:IsA("BasePart") then
		sheathPart = sheathInst
	end
	
	-- Create character data structure
	local characterData: internalCharacter = {
		PlayerId = entity.userId,
		Entity = entity, -- Use EntityRef instead of Player
		Character = characterModel,
		Humanoid = humanoid,
		WeaponSheath = sheathPart,
		ClassId = nil, -- Will be set later
		
		-- Individual signal references for backward compatibility
		OnSpawn = signals.OnSpawn,
		OnDeath = signals.OnDeath,
		OnDamage = signals.OnDamage,
		OnAttack = signals.OnAttack,
		OnUpdate = signals.OnUpdate,
		OnStaminaChange = signals.OnStaminaChange,
		OnGuardChange = signals.OnGuardChange,
		OnStateChange = signals.OnStateChange,
		OnCleanup = signals.OnCleanup,
		
		-- Consolidated signals
		Signals = signals,
		
		-- Internal state
		_connections = {},
		_cleanupTasks = {},
		_lastUpdate = 0,
		
		-- Systems
		StateManager = StateManager.New(),
		Components = {},
		Definition = nil,
		Custom = {},
		
		Animations = nil,
	}
	
	-- Initialize state manager with default states
	self:_InitializeStateManager(characterData, config)
	
	return characterData
end

function CharacterFactory:SetupAnimations(characterModel: Model, entity: EntityRef, animationPack: string?)
	-- Create and tag animations folder
	local characterAnimationsFolder: Folder = Instance.new("Folder")
	characterAnimationsFolder.Name = "Animations"
	characterAnimationsFolder.Parent = characterModel
	local animTag = tostring(entity.userId) .. "_Animations"
	
	-- Load animation pack with cache optimization
	local packName = animationPack or "Default"
	local animCount = 0
	
	-- Try cache first for better performance
	if self._animationCache[packName] then
		for animName, animation in pairs(self._animationCache[packName]) do
			local clone = animation:Clone()
			clone.Name = animName
			clone.Parent = characterAnimationsFolder
			animCount = animCount + 1
		end
		print(`✅ Loaded {animCount} cached animations for {entity.name}`)
	else
		-- Fallback to asset loader
		local animAsset = self._assetLoader:GetAnimationAsset(packName)
		if animAsset then
			for animName, assetValue in pairs(animAsset) do
				local anim = assetValue.Instance
				if anim and anim:IsA("Animation") then
					local clone = anim:Clone()
					clone.Name = animName
					clone.Parent = characterAnimationsFolder
					animCount = animCount + 1
				end
			end
			print(`✅ Loaded {animCount} animations from asset loader for {entity.name}`)
		else
			warn(`⚠️ Animation pack {packName} not found for {entity.name}`)
		end
	end

	-- Tag the animations folder with the player's user ID
	CollectionService:AddTag(characterAnimationsFolder, animTag)
end

function CharacterFactory:_InitializeStateManager(characterData: internalCharacter, config: CharacterConfig?)
	local stateManager = characterData.StateManager
	
	-- Apply default character states
	local stateDefinitions = CharacterStates.GetDefinitions()
	CharacterStates.applyTo(stateManager, stateDefinitions)
	
	-- Apply character class initial states if any
	local def = characterData.Definition
	if def and def.initialStates then
		for stateName, v in pairs(def.initialStates :: any) do
			if typeof(v) == "table" and (v :: any).default ~= nil then
				stateManager:DefineState(stateName, (v :: any).default, (v :: any).validator)
			else
				stateManager:DefineState(stateName, v, nil)
			end
		end
	end
	
	-- Apply config overrides
	if config then
		if config.MaxHealth then stateManager:Set("MaxHealth", config.MaxHealth) end
		if config.MaxStamina then stateManager:Set("MaxStamina", config.MaxStamina) end
		if config.MaxGuard then stateManager:Set("MaxGuard", config.MaxGuard) end
	end
	
	-- Set initial values
	stateManager:Set("Health", characterData.Humanoid.Health)
	stateManager:Set("MaxHealth", characterData.Humanoid.MaxHealth)
end

return CharacterFactory
