--!strict
-- AbilityStateMachine: Centralized state management for abilities with built-in synchronization

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local StateManager = require(script.Parent.StateManager)
local NetworkClient = RunService:IsClient() and require(game.ReplicatedStorage.Modules.Network.Client) or nil
local NetworkServer = RunService:IsServer() and require(game.ReplicatedStorage.Modules.Network.Server) or nil

-- Types
export type StateConfig = {
    name: string,
    defaultValue: any,
    validator: ((value: any) -> boolean)?,
    syncToClient: boolean?, -- Should this state be synced to client?
}

export type AbilityConfig = {
    abilityName: string,
    states: {StateConfig},
    syncRate: number?, -- How often to sync (default 0.1)
    syncOnChange: boolean?, -- Sync immediately on state change (default false)
}

export type AbilityStateMachine = {
    abilityName: string,
    stateManager: StateManager.StateManager,
    config: AbilityConfig,
    playerId: number?,
    isServer: boolean,
    lastSyncTime: number,
    syncRate: number,
    syncOnChange: boolean,
    pendingSync: boolean,
    
    -- Methods
    Get: (self: AbilityStateMachine, stateName: string) -> any,
    Set: (self: AbilityStateMachine, stateName: string, value: any) -> boolean,
    SetMultiple: (self: AbilityStateMachine, updates: {[string]: any}) -> (),
    GetAll: (self: AbilityStateMachine) -> {[string]: any},
    
    -- Sync methods
    SyncToClient: (self: AbilityStateMachine, player: Player?, force: boolean?) -> (),
    ApplySyncData: (self: AbilityStateMachine, syncData: {[string]: any}) -> (),
    OnStateChange: (self: AbilityStateMachine, stateName: string, callback: (newValue: any, oldValue: any) -> ()) -> () -> (),
    
    -- Lifecycle
    Reset: (self: AbilityStateMachine) -> (),
    Destroy: (self: AbilityStateMachine) -> (),
}

local AbilityStateMachine = {}
AbilityStateMachine.__index = AbilityStateMachine

-- Static registry for managing state machines
local StateMachineRegistry: {[string]: {[number]: AbilityStateMachine}} = {}

-- Create a new state machine
function AbilityStateMachine.new(config: AbilityConfig, playerId: number?): AbilityStateMachine
    local self = setmetatable({} :: any, AbilityStateMachine)
    
    self.abilityName = config.abilityName
    self.config = config
    self.playerId = playerId
    self.isServer = RunService:IsServer()
    self.lastSyncTime = 0
    self.syncRate = config.syncRate or 0.1
    self.syncOnChange = config.syncOnChange or false
    self.pendingSync = false
    
    -- Create state manager
    self.stateManager = StateManager.New()
    
    -- Define states from config
    for _, stateConfig in ipairs(config.states) do
        self.stateManager:DefineState(
            stateConfig.name,
            stateConfig.defaultValue,
            stateConfig.validator
        )
    end
    
    -- Register in registry
    if not StateMachineRegistry[config.abilityName] then
        StateMachineRegistry[config.abilityName] = {}
    end
    if playerId then
        StateMachineRegistry[config.abilityName][playerId] = self
    end
    
    -- Set up auto-sync on state changes if configured
    if self.isServer and self.syncOnChange then
        for _, stateConfig in ipairs(config.states) do
            if stateConfig.syncToClient ~= false then
                self.stateManager:OnStateChange(stateConfig.name, function()
                    self.pendingSync = true
                end)
            end
        end
    end
    
    return self
end

-- Get state value
function AbilityStateMachine:Get(stateName: string): any
    return self.stateManager:Get(stateName)
end

-- Set state value
function AbilityStateMachine:Set(stateName: string, value: any): boolean
    local success = self.stateManager:Set(stateName, value)
    
    -- Mark for sync if needed
    if success and self.isServer and self.syncOnChange then
        self.pendingSync = true
    end
    
    return success
end

-- Set multiple states at once
function AbilityStateMachine:SetMultiple(updates: {[string]: any})
    self.stateManager:SetMultiple(updates)
    
    -- Mark for sync if needed
    if self.isServer and self.syncOnChange then
        self.pendingSync = true
    end
end

-- Get all states
function AbilityStateMachine:GetAll(): {[string]: any}
    return self.stateManager:GetAllStates()
end

-- Sync state to client
function AbilityStateMachine:SyncToClient(player: Player?, force: boolean?)
    if not self.isServer then
        return
    end
    
    local currentTime = tick()
    
    -- Rate limiting unless forced or pending
    if not force and not self.pendingSync then
        if currentTime - self.lastSyncTime < self.syncRate then
            return
        end
    end
    
    -- Determine which player to sync to
    local targetPlayer = player
    if not targetPlayer and self.playerId then
        targetPlayer = Players:GetPlayerByUserId(self.playerId)
    end
    
    if not targetPlayer then
        return
    end
    
    -- Build sync data with only syncable states
    local syncData = {}
    for _, stateConfig in ipairs(self.config.states) do
        if stateConfig.syncToClient ~= false then
            syncData[stateConfig.name] = self.stateManager:Get(stateConfig.name)
        end
    end
    
    -- Send via network
    if NetworkServer and NetworkServer.stateSync then
        NetworkServer.stateSync.Fire(targetPlayer, {
            States = {
                [self.abilityName] = syncData
            }
        })
    end
    
    self.lastSyncTime = currentTime
    self.pendingSync = false
end

-- Apply sync data from server (client-side)
function AbilityStateMachine:ApplySyncData(syncData: {[string]: any})
    if self.isServer then
        return -- Server doesn't receive sync data
    end
    
    -- Apply all synced states
    local updates = {}
    for stateName, value in pairs(syncData) do
        -- Only apply if it's a defined state
        if self.stateManager:Has(stateName) then
            updates[stateName] = value
        end
    end
    
    if next(updates) then
        self.stateManager:SetMultiple(updates)
    end
end

-- Listen for state changes
function AbilityStateMachine:OnStateChange(stateName: string, callback: (newValue: any, oldValue: any) -> ()): () -> ()
    return self.stateManager:OnStateChange(stateName, callback)
end

-- Reset all states to defaults
function AbilityStateMachine:Reset()
    for _, stateConfig in ipairs(self.config.states) do
        self.stateManager:Set(stateConfig.name, stateConfig.defaultValue)
    end
end

-- Clean up
function AbilityStateMachine:Destroy()
    -- Remove from registry
    if self.playerId and StateMachineRegistry[self.abilityName] then
        StateMachineRegistry[self.abilityName][self.playerId] = nil
    end
end

-- Static method to get state machine for a player
function AbilityStateMachine.getForPlayer(abilityName: string, playerId: number): AbilityStateMachine?
    if StateMachineRegistry[abilityName] then
        return StateMachineRegistry[abilityName][playerId]
    end
    return nil
end

-- Static method to handle sync updates (for client)
function AbilityStateMachine.handleSyncUpdate(data: {States: {[string]: any}})
    for abilityName, syncData in pairs(data.States) do
        -- Find the state machine for this ability
        if StateMachineRegistry[abilityName] then
            -- On client, there should be only one instance (local player)
            for _, stateMachine in pairs(StateMachineRegistry[abilityName]) do
                stateMachine:ApplySyncData(syncData)
            end
        end
    end
end

-- Set up client-side sync listener
if RunService:IsClient() and NetworkClient then
    NetworkClient.StateSync.On(function(data)
        AbilityStateMachine.handleSyncUpdate(data)
    end)
end

return AbilityStateMachine