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

export type ICharacterFactory = {
	CreateCharacterModel: (self: ICharacterFactory, player: Player, config: CharacterConfig?, parentToWorkspace: boolean?) -> Model?,
	CreateCharacterData: (self: ICharacterFactory, player: Player, characterModel: Model, config: CharacterConfig?) -> internalCharacter?,
	SetupAnimations: (self: ICharacterFactory, characterModel: Model, player: Player, animationPack: string?) -> (),
}

local CharacterFactory = {}
CharacterFactory.__index = CharacterFactory

function CharacterFactory.new(assetLoader: any, eventManager: any, characterRegistry: any?): ICharacterFactory
	local self = setmetatable({}, CharacterFactory)
	
	self._assetLoader = assetLoader
	self._eventManager = eventManager
	self._characterRegistry = characterRegistry
	
	return self
end

function CharacterFactory:CreateCharacterModel(player: Player, config: CharacterConfig?, parentToWorkspace: boolean?): Model?
	print(`[CharacterFactory] Creating character model for: {player.Name}`)
	
	-- Get character asset
	local characterAsset = self._assetLoader:GetCharacterAsset()
	print(`[CharacterFactory] Asset received: {characterAsset ~= nil}`)
	if not characterAsset then
		warn(`[CharacterFactory] No character assets available for player {player.Name}`)
		return nil
	end
	
	-- Clone and set up character
	local characterModel = characterAsset:Clone()
	characterModel.Name = player.Name
	
	-- Only parent to workspace if explicitly requested (default true for backwards compatibility)
	if parentToWorkspace ~= false then
		characterModel.Parent = workspace
	end
	
	-- Guard non-standard APIs
	local modelAny = characterModel :: any
	if typeof(modelAny.AddPersistentPlayer) == "function" then
		pcall(function()
			modelAny:AddPersistentPlayer(player)
		end)
	end
	
	-- Set up humanoid
	local humanoid: Humanoid = characterModel:WaitForChild("Humanoid") :: Humanoid
	local maxHealth = (config and config.MaxHealth) or 100
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = (config and config.WalkSpeed) or 16

	--load effects
	local allEffects = Effects.GetAllAssets()
	local effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "Effects"
	local effectCount = 0
	for effectName, effectData in pairs(allEffects) do
		if effectName:find("Rem:") then 
			if effectData.Instance then
				local effectClone = effectData.Instance:Clone()
				-- Extract just the effect name after the colon (e.g., "Heal" from "Rem:Heal")
				local cleanName = effectName:split(":")[2] or effectName
				effectClone.Name = cleanName
				effectClone.Parent = effectsFolder
				effectCount = effectCount + 1
				print(`✅ Loaded Rem effect: {cleanName} from {effectName}`)
			end
		end
	end

	-- Parent the effects folder immediately to avoid race conditions
	effectsFolder.Parent = characterModel
	print(`✅ Created Effects folder with {effectCount} effects for Rem character`)
	
	-- Set player character
	player.Character = characterModel
	
	-- Set humanoid target point
	local primary: BasePart? = characterModel.PrimaryPart or characterModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if primary then
		humanoid.TargetPoint = (primary :: BasePart).Position
	end
	
	return characterModel
end

function CharacterFactory:CreateCharacterData(player: Player, characterModel: Model, config: CharacterConfig?): internalCharacter?
	local humanoid = characterModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(`No humanoid found in character model for {player.Name}`)
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
		PlayerId = player.UserId,
		Player = player,
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

function CharacterFactory:SetupAnimations(characterModel: Model, player: Player, animationPack: string?)
	-- Create and tag animations folder
	local characterAnimationsFolder: Folder = Instance.new("Folder")
	characterAnimationsFolder.Name = "Animations"
	characterAnimationsFolder.Parent = characterModel
	local animTag = tostring(player.UserId) .. "_Animations"
	
	-- Load animation pack
	local packName = animationPack or "Default"
	local animAsset = self._assetLoader:GetAnimationAsset(packName)
	
	-- Optimized animation setup - no more delays!
	if animAsset then
		-- Direct synchronous setup since assets should be preloaded
		for animName, assetValue in pairs(animAsset) do
			local anim = assetValue.Instance
			if anim and anim:IsA("Animation") then
				local clone = anim:Clone()
				clone.Name = animName
				clone.Parent = characterAnimationsFolder
			end
		end
		print(`✅ Instantly loaded {#characterAnimationsFolder:GetChildren()} animations for {player.Name}`)
	else
		-- Fallback: try to get individual animations if pack loading failed
		warn(`⚠️ Animation pack ${packName} not found, using fallback loading for {player.Name}`)
		
		local animationHandler = require(game.ReplicatedStorage.Modules.AssetHandlers).OnModuleLoaded("Animations")
		if animationHandler then
			-- Try to preload the pack immediately
			local success, _ = pcall(function()
				(animationHandler :: any).PreloadPack(packName)
			end)
			
			if success then
				-- Retry getting the animation asset
				animAsset = self._assetLoader:GetAnimationAsset(packName)
				if animAsset then
					for animName, assetValue in pairs(animAsset) do
						local anim = assetValue.Instance
						if anim and anim:IsA("Animation") then
							local clone = anim:Clone()
							clone.Name = animName
							clone.Parent = characterAnimationsFolder
						end
					end
					print(`⚠️ Fallback loaded {#characterAnimationsFolder:GetChildren()} animations for {player.Name}`)
				end
			end
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
