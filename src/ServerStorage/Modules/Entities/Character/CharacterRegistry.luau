--!strict
-- CharacterRegistry - Manages character storage and fast lookup
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

type internalCharacter = CharacterTypes.internalCharacter

export type ICharacterRegistry = {
	Register: (self: ICharacterRegistry, playerId: number, characterData: internalCharacter) -> (),
	Unregister: (self: ICharacterRegistry, playerId: number) -> (),
	Get: (self: ICharacterRegistry, playerId: number) -> internalCharacter?,
	GetActive: (self: ICharacterRegistry, playerId: number) -> internalCharacter?,
	GetAll: (self: ICharacterRegistry) -> {[number]: internalCharacter},
	GetActiveList: (self: ICharacterRegistry) -> {number},
	GetActiveCount: (self: ICharacterRegistry) -> number,
	SetActive: (self: ICharacterRegistry, playerId: number, active: boolean) -> (),
	Clear: (self: ICharacterRegistry) -> (),
}

local CharacterRegistry = {}
CharacterRegistry.__index = CharacterRegistry

function CharacterRegistry.new(): ICharacterRegistry
	local self = setmetatable({}, CharacterRegistry)
	
	-- Storage for all characters (alive and dead)
	self._characters = {} :: {[number]: internalCharacter}
	
	-- Storage for only active (alive) characters
	self._activeCharacters = {} :: {[number]: internalCharacter}
	
	-- Fast int-indexed iteration structures for active characters
	self._activeList = {} :: {number} -- array of playerIds
	self._activeIndex = {} :: {[number]: number} -- playerId -> index in _activeList
	
	return self
end

function CharacterRegistry:Register(playerId: number, characterData: internalCharacter)
	self._characters[playerId] = characterData
	self:SetActive(playerId, true)
end

function CharacterRegistry:Unregister(playerId: number)
	self._characters[playerId] = nil
	self:SetActive(playerId, false)
end

function CharacterRegistry:Get(playerId: number): internalCharacter?
	return self._characters[playerId]
end

function CharacterRegistry:GetActive(playerId: number): internalCharacter?
	return self._activeCharacters[playerId]
end

function CharacterRegistry:GetAll(): {[number]: internalCharacter}
	return table.clone(self._characters)
end

function CharacterRegistry:GetActiveList(): {number}
	return table.clone(self._activeList)
end

function CharacterRegistry:GetActiveCount(): number
	return #self._activeList
end

function CharacterRegistry:SetActive(playerId: number, active: boolean)
	if active then
		local characterData = self._characters[playerId]
		if characterData then
			self._activeCharacters[playerId] = characterData
			self:_addToActiveList(playerId)
		end
	else
		self._activeCharacters[playerId] = nil
		self:_removeFromActiveList(playerId)
	end
end

function CharacterRegistry:Clear()
	table.clear(self._characters)
	table.clear(self._activeCharacters)
	table.clear(self._activeList)
	table.clear(self._activeIndex)
end

-- Private methods for managing the active list
function CharacterRegistry:_addToActiveList(playerId: number)
	-- Only add if not already in list
	if not self._activeIndex[playerId] then
		table.insert(self._activeList, playerId)
		self._activeIndex[playerId] = #self._activeList
	end
end

function CharacterRegistry:_removeFromActiveList(playerId: number)
	-- O(1) swap-remove for active character list
	local index = self._activeIndex[playerId]
	if index then
		local last = #self._activeList
		local lastId = self._activeList[last]
		
		if lastId then
			-- Move last element to the position of the element we're removing
			self._activeList[index] = lastId
			self._activeIndex[lastId] = index
		end
		
		-- Remove the last element and clear index
		self._activeList[last] = nil
		self._activeIndex[playerId] = nil
	end
end

return CharacterRegistry
