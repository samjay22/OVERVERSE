--!strict
-- NetworkManager: Centralized network event management with strong typing
-- Provides event-driven architecture with bindable events triggering network calls

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventBus = require(game.ServerStorage.Modules.Events.EventBus)

-- Core network types
export type NetworkEventData = {
	eventName: string,
	targetPlayer: Player?,
	targetPlayers: {Player}?,
	data: {[string]: any}?,
	reliable: boolean?,
	ordered: boolean?,
}

export type NetworkEventHandler = (player: Player, data: any) -> any
export type NetworkSubscriber = (eventData: NetworkEventData) -> ()

export type INetworkManager = {
	RegisterRemoteEvent: (self: INetworkManager, eventName: string) -> RemoteEvent,
	RegisterRemoteFunction: (self: INetworkManager, functionName: string) -> RemoteFunction,
	
	RegisterServerHandler: (self: INetworkManager, eventName: string, handler: NetworkEventHandler) -> (),
	
	SubscribeToOutbound: (self: INetworkManager, eventName: string, subscriber: NetworkSubscriber) -> RBXScriptConnection,
	
	FireClient: (self: INetworkManager, eventName: string, targetPlayer: Player, data: any?) -> (),
	FireAllClients: (self: INetworkManager, eventName: string, data: any?) -> (),
	FireAllClientsExcept: (self: INetworkManager, eventName: string, excludePlayer: Player, data: any?) -> (),
	
	TriggerOutbound: (self: INetworkManager, eventData: NetworkEventData) -> (),
	
	Destroy: (self: INetworkManager) -> (),
}

local NetworkManager = {}
NetworkManager.__index = NetworkManager

function NetworkManager.New(): INetworkManager
	local self = setmetatable({}, NetworkManager)
	
	-- Event management with pre-allocated tables
	self._eventBus = EventBus.New()
	self._remoteEvents = {} :: {[string]: RemoteEvent}
	self._remoteFunctions = {} :: {[string]: RemoteFunction}
	self._serverHandlers = {} :: {[string]: NetworkEventHandler}
	self._connections = table.create(32) :: {RBXScriptConnection}
	
	-- Connection pool for performance
	self._connectionPool = table.create(64) :: {RBXScriptConnection}
	self._poolSize = 0
	
	-- Create remotes folder if it doesn't exist
	local remotesFolder: Folder? = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
	if not remotesFolder or not remotesFolder:IsA("Folder") then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Remotes"
		newFolder.Parent = ReplicatedStorage
		remotesFolder = newFolder
	end
	self._remotesFolder = remotesFolder :: any
	
	return (self :: any) :: INetworkManager
end

-- Register a new RemoteEvent and return it
function NetworkManager:RegisterRemoteEvent(eventName: string): RemoteEvent
	local existing = self._remoteEvents[eventName]
	if existing then
		return existing
	end
	-- Reuse an existing RemoteEvent in the Remotes folder if present (pre-created elsewhere)
	local found = (self._remotesFolder :: Folder):FindFirstChild(eventName)
	local remoteEvent: RemoteEvent
	if found and found:IsA("RemoteEvent") then
		remoteEvent = found
	else
		remoteEvent = Instance.new("RemoteEvent")
		remoteEvent.Name = eventName
		remoteEvent.Parent = (self._remotesFolder :: Folder)
	end
    
	self._remoteEvents[eventName] = remoteEvent
	
	-- Connect server handler if one exists
	local handler = self._serverHandlers[eventName]
	if handler then
		local connection = remoteEvent.OnServerEvent:Connect(handler)
		table.insert(self._connections, connection)
	end
	
	return remoteEvent
end

-- Register a new RemoteFunction and return it
function NetworkManager:RegisterRemoteFunction(functionName: string): RemoteFunction
	local existing = self._remoteFunctions[functionName]
	if existing then
		return existing
	end
	-- Reuse an existing RemoteFunction in the Remotes folder if present
	local found = (self._remotesFolder :: Folder):FindFirstChild(functionName)
	local remoteFunction: RemoteFunction
	if found and found:IsA("RemoteFunction") then
		remoteFunction = found
	else
		remoteFunction = Instance.new("RemoteFunction")
		remoteFunction.Name = functionName
		remoteFunction.Parent = (self._remotesFolder :: Folder)
	end
    
	self._remoteFunctions[functionName] = remoteFunction
	
	return remoteFunction
end

-- Register a server-side handler for incoming client events
function NetworkManager:RegisterServerHandler(eventName: string, handler: NetworkEventHandler): ()
	self._serverHandlers[eventName] = handler
	
	-- If remote already exists, connect the handler
	local remoteEvent = self._remoteEvents[eventName]
	if remoteEvent then
		local connection = remoteEvent.OnServerEvent:Connect(handler)
		table.insert(self._connections, connection)
	end
end

-- Subscribe to outbound network events (for services to listen to network calls)
function NetworkManager:SubscribeToOutbound(eventName: string, subscriber: NetworkSubscriber): RBXScriptConnection
	local event = self._eventBus:Get(eventName)
	return event:Connect(subscriber)
end

-- Fire event to specific client
function NetworkManager:FireClient(eventName: string, targetPlayer: Player, data: any?): ()
	local remoteEvent = self._remoteEvents[eventName]
	if not remoteEvent then
		warn(`NetworkManager: RemoteEvent '{eventName}' not registered`)
		return
	end
	
	remoteEvent:FireClient(targetPlayer, data)
	
	-- Trigger outbound event for subscribers
	self:TriggerOutbound({
		eventName = eventName,
		targetPlayer = targetPlayer,
		data = data,
		reliable = true,
	})
end

-- Fire event to all clients
function NetworkManager:FireAllClients(eventName: string, data: any?): ()
	local remoteEvent = self._remoteEvents[eventName]
	if not remoteEvent then
		warn(`NetworkManager: RemoteEvent '{eventName}' not registered`)
		return
	end
	
	remoteEvent:FireAllClients(data)
	
	-- Trigger outbound event for subscribers
	self:TriggerOutbound({
		eventName = eventName,
		data = data,
		reliable = true,
	})
end

-- Fire event to all clients except one
function NetworkManager:FireAllClientsExcept(eventName: string, excludePlayer: Player, data: any?): ()
	local remoteEvent = self._remoteEvents[eventName]
	if not remoteEvent then
		warn(`NetworkManager: RemoteEvent '{eventName}' not registered`)
		return
	end
	
	for _, player in pairs(game.Players:GetPlayers()) do
		if player ~= excludePlayer then
			remoteEvent:FireClient(player, data)
		end
	end
	
	-- Trigger outbound event for subscribers
	self:TriggerOutbound({
		eventName = eventName,
		data = data,
		reliable = true,
	})
end

-- Trigger outbound event (for internal use and external triggering)
function NetworkManager:TriggerOutbound(eventData: NetworkEventData): ()
	local event = self._eventBus:Get(eventData.eventName)
	event:Fire(eventData)
end

function NetworkManager:Destroy(): ()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	
	for _, remoteEvent in pairs(self._remoteEvents) do
		remoteEvent:Destroy()
	end
	
	for _, remoteFunction in pairs(self._remoteFunctions) do
		remoteFunction:Destroy()
	end
	
	self._eventBus:Destroy()
	table.clear(self._connections)
	table.clear(self._remoteEvents)
	table.clear(self._remoteFunctions)
	table.clear(self._serverHandlers)
end

return NetworkManager
