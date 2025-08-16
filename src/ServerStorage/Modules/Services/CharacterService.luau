--!strict
-- CharacterService: Centralized character data management
-- Eliminates repeated character fetching patterns throughout the codebase

local Players = game:GetService("Players")
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

export type CharacterRef = AbilityTypes.CharacterRef
export type CharacterData = CharacterTypes.Character

export type ICharacterService = {
	GetCharacterData: (self: ICharacterService, player: Player) -> CharacterRef?,
	GetCharacterById: (self: ICharacterService, playerId: number) -> CharacterRef?,
	IsCharacterValid: (self: ICharacterService, character: CharacterRef?) -> boolean,
	RegisterCharacterAddedCallback: (self: ICharacterService, callback: (CharacterRef) -> ()) -> RBXScriptConnection,
	RegisterCharacterRemovedCallback: (self: ICharacterService, callback: (CharacterRef) -> ()) -> RBXScriptConnection,
}

local CharacterService = {}
CharacterService.__index = CharacterService

function CharacterService.New(): ICharacterService
	local self = setmetatable({}, CharacterService)
	
	self._characterManager = nil
	self._characterAddedCallbacks = {}
	self._characterRemovedCallbacks = {}
	
	-- Lazy load character manager to avoid circular dependencies
	task.spawn(function()
		local success, Character = pcall(require, game.ServerStorage.Modules.Entities.Character)
		if success then
			self._characterManager = Character
		else
			warn("CharacterService: Failed to load Character manager:", Character)
		end
	end)
	
	return (self :: any) :: ICharacterService
end

-- Get character data for a player
function CharacterService:GetCharacterData(player: Player): CharacterRef?
	if not self._characterManager then
		warn("CharacterService: Character manager not loaded")
		return nil
	end
	
	if not player or not player.Parent then
		return nil
	end
	
	local success, result = pcall(self._characterManager.GetCharacterData, self._characterManager, player)
	if success then
		return result
	else
		warn(`CharacterService: Failed to get character data for {player.Name}: {result}`)
		return nil
	end
end

-- Get character data by player ID
function CharacterService:GetCharacterById(playerId: number): CharacterRef?
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return nil
	end
	
	return self:GetCharacterData(player)
end

-- Validate that a character reference is still valid
function CharacterService:IsCharacterValid(character: CharacterRef?): boolean
	if not character then
		return false
	end
	
	-- Check if player is still in game
	if not character.Player or not character.Player.Parent then
		return false
	end
	
	-- Check if character model is still valid
	if character.Character and not character.Character.Parent then
		return false
	end
	
	-- Check if humanoid is still valid
	if character.Humanoid and not character.Humanoid.Parent then
		return false
	end
	
	return true
end

-- Register callback for when characters are added
function CharacterService:RegisterCharacterAddedCallback(callback: (CharacterRef) -> ()): RBXScriptConnection
	table.insert(self._characterAddedCallbacks, callback)
	
	-- TODO: Connect to actual character added event when available
	-- For now, return a dummy connection
	local connection = {
		Connected = true,
		Disconnect = function() end
	}
	
	return connection :: any
end

-- Register callback for when characters are removed
function CharacterService:RegisterCharacterRemovedCallback(callback: (CharacterRef) -> ()): RBXScriptConnection
	table.insert(self._characterRemovedCallbacks, callback)
	
	-- TODO: Connect to actual character removed event when available
	-- For now, return a dummy connection
	local connection = {
		Connected = true,
		Disconnect = function() end
	}
	
	return connection :: any
end

-- Utility method to execute a function with character validation
function CharacterService:WithCharacter<T>(
	player: Player, 
	func: (CharacterRef) -> T?
): T?
	local character = self:GetCharacterData(player)
	if not self:IsCharacterValid(character) then
		return nil
	end
	
	local success, result = pcall(func, character :: CharacterRef)
	if success then
		return result
	else
		warn(`CharacterService: Function execution failed for {player.Name}: {result}`)
		return nil
	end
end

-- Get multiple characters at once
function CharacterService:GetCharactersForPlayers(players: {Player}): {CharacterRef}
	local characters = {}
	
	for _, player in ipairs(players) do
		local character = self:GetCharacterData(player)
		if self:IsCharacterValid(character) then
			table.insert(characters, character :: CharacterRef)
		end
	end
	
	return characters
end

-- Check if character manager is ready
function CharacterService:IsReady(): boolean
	return self._characterManager ~= nil
end

return CharacterService
