--!strict
-- CharacterLifecycle - Manages spawn, death, cleanup logic
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

type internalCharacter = CharacterTypes.internalCharacter
type CharacterConfig = CharacterTypes.CharacterConfig

export type LifecycleConfig = {
	DefaultRespawnTime: number,
	EnableAutoRespawn: boolean,
	MaxCharacters: number,
}

export type ICharacterLifecycle = {
	HandleSpawn: (self: ICharacterLifecycle, characterData: internalCharacter) -> (),
	HandleDeath: (self: ICharacterLifecycle, characterData: internalCharacter) -> (),
	HandleCleanup: (self: ICharacterLifecycle, characterData: internalCharacter) -> (),
	SetConfig: (self: ICharacterLifecycle, config: LifecycleConfig) -> (),
	SetSpawnCallback: (self: ICharacterLifecycle, callback: (Player, CharacterConfig?) -> ()) -> (),
}

local CharacterLifecycle = {}
CharacterLifecycle.__index = CharacterLifecycle

function CharacterLifecycle.new(): ICharacterLifecycle
	local self = setmetatable({}, CharacterLifecycle)
	
	self._config = {
		DefaultRespawnTime = 5,
		EnableAutoRespawn = true,
		MaxCharacters = 100,
	} :: LifecycleConfig
	
	self._spawnCallback = nil :: ((Player, CharacterConfig?) -> ())?
	
	return self
end

function CharacterLifecycle:SetConfig(config: LifecycleConfig)
	self._config = config
end

function CharacterLifecycle:SetSpawnCallback(callback: (Player, CharacterConfig?) -> ())
	self._spawnCallback = callback
end

function CharacterLifecycle:HandleSpawn(characterData: internalCharacter)
	-- Fire spawn signal
	characterData.Signals.OnSpawn:Fire(characterData.Character)
	
	-- Set spawn state
	characterData.StateManager:Set("IsDead", false)
	characterData.StateManager:Set("LastSpawn", time())
end

function CharacterLifecycle:HandleDeath(characterData: internalCharacter)
	if not characterData.Player then return end
	
	-- Set death state
	characterData.StateManager:Set("IsDead", true)
	characterData.StateManager:Set("LastDeath", time())
	
	-- Clean up animations
	local playerId = characterData.PlayerId
	local tagged = CollectionService:GetTagged(tostring(playerId) .. "_Animations")
	if tagged and #tagged > 0 then
		for _, inst in ipairs(tagged) do
			pcall(function()
				CollectionService:RemoveTag(inst, tostring(playerId) .. "_Animations")
				inst:Destroy()
			end)
		end
	end
	
	-- Schedule respawn if enabled
	if self._config.EnableAutoRespawn and self._spawnCallback then
		local respawnTime = self._config.DefaultRespawnTime
		table.insert(characterData._cleanupTasks, function()
			task.wait(respawnTime)
			if Players:FindFirstChild(characterData.Player.Name) then
				self._spawnCallback(characterData.Player, nil)
			end
		end)
	end
end

function CharacterLifecycle:HandleCleanup(characterData: internalCharacter)
	-- Run class onCleanup hook
	if characterData.Definition and characterData.Definition.hooks and characterData.Definition.hooks.onCleanup then
		pcall(characterData.Definition.hooks.onCleanup, characterData)
	end
	
	-- Disconnect connections
	for _, connection in pairs(characterData._connections) do
		if connection then
			connection:Disconnect()
		end
	end
	
	-- Execute cleanup tasks
	for _, cleanupTask in pairs(characterData._cleanupTasks) do
		if typeof(cleanupTask) == "function" then
			task.defer(function()
				local success = pcall(cleanupTask)
				if not success then
					warn("Cleanup task failed")
				end
			end)
		end
	end
	
	-- Fire cleanup signal before destruction
	characterData.Signals.OnCleanup:Fire()
	
	-- Clean up character model
	if characterData.Character then
		characterData.Character:Destroy()
	end
end

return CharacterLifecycle
