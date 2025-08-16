--!strict
-- Improved Network Server with event-driven architecture

local NetworkManager = require(game.ServerStorage.Modules.Core.NetworkManager)
local AbilityComponent = require(game.ServerStorage.Modules.Components.AbilityComponent)
local WeaponComponent = require(game.ServerStorage.Modules.Components.WeaponComponent)
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local NetworkTypes = require(game.ReplicatedStorage.Modules.Types.NetworkTypes)

-- Create network manager instance
local networkManager = NetworkManager.New()

-- Register core events
local _coreEvent = networkManager:RegisterRemoteEvent("CoreEvent")
local _abilityEvent = networkManager:RegisterRemoteEvent("AbilityEvent")
local _weaponEvent = networkManager:RegisterRemoteEvent("WeaponEvent")
local _combatEvent = networkManager:RegisterRemoteEvent("CombatEvent")
local _characterEvent = networkManager:RegisterRemoteEvent("CharacterEvent")

-- Network event handlers
local function handleCoreEvent(player: Player, message: any)
	if typeof(message) ~= "table" or typeof(message.t) ~= "string" then 
		warn(`Invalid core message from {player.Name}`)
		return 
	end
	
	-- Legacy support for old CoreEvent messages
	if message.t == Enums.CoreMessageType.PrimaryWeapon then
		WeaponComponent.Primary(player, message.action)
	elseif message.t == Enums.CoreMessageType.Ability and message.id then
		AbilityComponent.Activate(player, message.id, message.extra)
	else
		warn(`Unknown core message type: {message.t}`)
	end
end

local function handleAbilityEvent(player: Player, message: NetworkTypes.AbilityActivateMessage)
	if not message or not message.data then
		warn(`Invalid ability message from {player.Name}`)
		return
	end
	
	local data = message.data
	local result = AbilityComponent.Activate(player, data.abilityId, {
		targetPosition = data.targetPosition,
		targetPlayerId = data.targetPlayerId,
		extra = data.extra,
	})
	
	-- Send result back to client
	networkManager:FireClient("AbilityResult", player, {
		type = Enums.NetworkEventType.Ability,
		messageType = Enums.NetworkMessageType.Response,
		timestamp = tick(),
		playerId = player.UserId,
		data = {
			abilityId = data.abilityId,
			success = result,
			errorMessage = nil, -- TODO: Include error details
		},
	})
end

local function handleWeaponEvent(player: Player, message: NetworkTypes.WeaponActionMessage)
	if not message or not message.data then
		warn(`Invalid weapon message from {player.Name}`)
		return
	end
	
	local data = message.data
	local result = WeaponComponent.Primary(player, data.action)
	
	-- Broadcast weapon action to other players for visual effects
	if result then
		networkManager:FireAllClientsExcept("WeaponAction", player, {
			type = Enums.NetworkEventType.Weapon,
			messageType = Enums.NetworkMessageType.Notification,
			timestamp = tick(),
			playerId = player.UserId,
			data = {
				weaponId = data.weaponId,
				action = data.action,
				targetPosition = data.targetPosition,
				direction = data.direction,
			},
		})
	end
end

local function handleCombatEvent(player: Player, message: any)
	-- Handle combat-related events (damage, healing, etc.)
	warn("Combat events not yet implemented")
end

local function handleCharacterEvent(player: Player, message: any)
	-- Handle character-related events (state changes, spawning, etc.)
	warn("Character events not yet implemented")
end

-- Register server handlers
networkManager:RegisterServerHandler("CoreEvent", handleCoreEvent)
networkManager:RegisterServerHandler("AbilityEvent", handleAbilityEvent)
networkManager:RegisterServerHandler("WeaponEvent", handleWeaponEvent)
networkManager:RegisterServerHandler("CombatEvent", handleCombatEvent)
networkManager:RegisterServerHandler("CharacterEvent", handleCharacterEvent)

-- Subscribe to outbound events for logging/analytics
networkManager:SubscribeToOutbound("AbilityEvent", function(eventData)
	print(`Ability event sent: {eventData.eventName}`)
end)

networkManager:SubscribeToOutbound("WeaponEvent", function(eventData)
	print(`Weapon event sent: {eventData.eventName}`)
end)

-- Set up component event subscriptions
local Character = require(game.ServerStorage.Modules.Entities.Character)

-- Subscribe to ability activation events
-- Note: Will be connected once component services have event systems

-- Subscribe to weapon hit events  
-- Note: Will be connected once component services have event systems

-- Subscribe to character events
Character:OnCharacterAdded(function(characterData)
	local player = characterData.Player
	networkManager:FireClient("CharacterSpawned", player, {
		type = Enums.NetworkEventType.Character,
		messageType = Enums.NetworkMessageType.Notification,
		timestamp = tick(),
		playerId = player.UserId,
		data = {
			playerId = player.UserId,
			position = characterData.Character and characterData.Character.PrimaryPart and characterData.Character.PrimaryPart.Position or Vector3.zero,
		},
	})
end)

print("Network server initialized with event-driven architecture")

-- Export network manager for other modules to use
return networkManager
