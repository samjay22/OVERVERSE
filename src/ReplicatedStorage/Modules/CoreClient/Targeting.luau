--!strict
-- ReplicatedStorage/TargetSystem
local TargetSystem = {}
TargetSystem.__index = TargetSystem

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

type TargetData = {
    target: Model?,
    timestamp: number,
    playerId: number
}

type TargetSystem = {
    isServer: boolean,
    targets: {[Player]: TargetData},
    callbacks: {[string]: (Player, Model?, Model?) -> ()},
    remotes: {
        SetTarget: RemoteEvent,
        GetTarget: RemoteFunction,
        TargetChanged: RemoteEvent,
        RequestTarget: RemoteFunction
    }
}

export type TargetSystemType = typeof(setmetatable({} :: TargetSystem, TargetSystem))

local instance: TargetSystemType? = nil

function TargetSystem.new(): TargetSystemType
    if instance then
        return instance
    end
    
    local self = setmetatable({} :: TargetSystem, TargetSystem)
    
    self.isServer = RunService:IsServer()
    self.targets = {}
    self.callbacks = {}
    
    -- Wait for ReplicatedStorage to be ready
    if not self.isServer then
        repeat
            task.wait()
        until ReplicatedStorage:FindFirstChild("Remotes")
    end
    
    -- Create or get remotes folder
    local remotesFolder: Folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder

    -- Setup remotes
    self.remotes = {
        SetTarget = self:_getOrCreateRemote(remotesFolder, "SetTarget", "RemoteEvent") :: RemoteEvent,
        GetTarget = self:_getOrCreateRemote(remotesFolder, "GetTarget", "RemoteFunction") :: RemoteFunction,
        TargetChanged = self:_getOrCreateRemote(remotesFolder, "TargetChanged", "RemoteEvent") :: RemoteEvent,
        RequestTarget = self:_getOrCreateRemote(remotesFolder, "RequestTarget", "RemoteFunction") :: RemoteFunction
    }
    
    -- Initialize based on context
    if self.isServer then
        self:_initServer()
    else
        self:_initClient()
    end
    
    instance = self
    return self
end

function TargetSystem:_getOrCreateRemote(parent: Folder, name: string, className: string): Instance
    local remote: Instance? = parent:FindFirstChild(name)
    if not remote then
        if self.isServer then
            remote = Instance.new(className :: any)
            remote.Name = name
            remote.Parent = parent
        else
            remote = parent:WaitForChild(name)
        end
    end
    return remote :: Instance
end

function TargetSystem:_initServer(): ()
    -- Handle client requests to set target
    self.remotes.SetTarget.OnServerEvent:Connect(function(player: Player, targetModel: Model?)
        self:_serverSetTarget(player, targetModel)
    end)
    
    -- Handle get target requests
    self.remotes.GetTarget.OnServerInvoke = function(player: Player): Model?
        return self:GetTarget(player)
    end
    
    -- Handle target info requests
    self.remotes.RequestTarget.OnServerInvoke = function(player: Player, queryPlayer: Player): Model?
        return self:GetTarget(queryPlayer)
    end
    
    -- Clean up on player removal
    Players.PlayerRemoving:Connect(function(player: Player)
        self.targets[player] = nil
    end)
    
    -- Periodic validation
    task.spawn(function()
        while true do
            task.wait(5)
            self:_validateTargets()
        end
    end)
end

function TargetSystem:_initClient(): ()
    local player: Player = Players.LocalPlayer
    
    -- Listen for target changes from server
    self.remotes.TargetChanged.OnClientEvent:Connect(function(targetModel: Model?)
        local oldTarget: Model? = self.targets[player] and self.targets[player].target
        
        if targetModel then
            self.targets[player] = {
                target = targetModel,
                timestamp = os.time(),
                playerId = player.UserId
            }
        else
            self.targets[player] = nil
        end
        
        self:_fireCallbacks(player, targetModel, oldTarget)
    end)
    
    -- Sync initial target
    task.spawn(function()
        task.wait(1) -- Give server time to initialize
        local success: boolean, result: any = pcall(function()
            return self.remotes.GetTarget:InvokeServer()
        end)
        
        if success and result then
            self.targets[player] = {
                target = result :: Model,
                timestamp = os.time(),
                playerId = player.UserId
            }
        end
    end)
end

function TargetSystem:_serverSetTarget(player: Player, targetModel: Model?): (boolean, string)
    -- Validate target model
    if targetModel then
        if not targetModel:IsA("Model") then
            return false, "Target must be a Model"
        end
        
        if not targetModel.Parent then
            return false, "Target model has no parent"
        end
        
        -- Check if model still exists in workspace
        if not targetModel:IsDescendantOf(workspace) then
            return false, "Target must be in workspace"
        end
    end
    
    local oldTarget: Model? = self.targets[player] and self.targets[player].target
    
    -- Update target data
    if targetModel then
        self.targets[player] = {
            target = targetModel,
            timestamp = os.time(),
            playerId = player.UserId
        }
    else
        self.targets[player] = nil
    end
    
    -- Notify client
    self.remotes.TargetChanged:FireClient(player, targetModel)
    
    -- Fire server callbacks
    self:_fireCallbacks(player, targetModel, oldTarget)
    
    return true, "Target set successfully"
end

function TargetSystem:SetTarget(player: Player, targetModel: Model?): boolean
    if self.isServer then
        local success: boolean, message: string = self:_serverSetTarget(player, targetModel)
        if not success then
            warn(`Failed to set target: {message}`)
        end
        return success
    else
        -- Client-side: send request to server
        if targetModel and not targetModel:IsA("Model") then
            warn("Target must be a Model")
            return false
        end
        
        self.remotes.SetTarget:FireServer(targetModel)
        return true
    end
end

function TargetSystem:GetTarget(player: Player): Model?
    local targetData: TargetData? = self.targets[player]
    
    if not targetData then
        return nil
    end
    
    -- Validate target still exists
    if targetData.target and not targetData.target.Parent then
        self.targets[player] = nil
        return nil
    end
    
    return targetData.target
end

function TargetSystem:GetLocalTarget(): Model?
    if self.isServer then
        warn("GetLocalTarget() can only be called on client")
        return nil
    end
    
    return self:GetTarget(Players.LocalPlayer)
end

function TargetSystem:ClearTarget(player: Player): boolean
    return self:SetTarget(player, nil)
end

function TargetSystem:HasTarget(player: Player): boolean
    return self:GetTarget(player) ~= nil
end

function TargetSystem:GetTargetData(player: Player): TargetData?
    return self.targets[player]
end

function TargetSystem:OnTargetChanged(callback: (Player, Model?, Model?) -> ()): () -> ()
    local id: string = tostring(tick()) .. tostring(math.random())
    self.callbacks[id] = callback
    
    -- Return disconnect function
    return function()
        self.callbacks[id] = nil
    end
end

function TargetSystem:_fireCallbacks(player: Player, newTarget: Model?, oldTarget: Model?): ()
    for _, callback in pairs(self.callbacks) do
        task.spawn(callback, player, newTarget, oldTarget)
    end
end

function TargetSystem:_validateTargets(): ()
    if not self.isServer then
        return
    end
    
    for player, targetData in pairs(self.targets) do
        -- Check if player still exists
        if not player.Parent then
            self.targets[player] = nil
            continue
        end
        
        -- Check if target still exists
        if targetData.target and not targetData.target.Parent then
            self:SetTarget(player, nil)
        end
    end
end

function TargetSystem:GetAllTargets(): {[Player]: Model?}
    local result: {[Player]: Model?} = {}
    for player, targetData in pairs(self.targets) do
        result[player] = targetData.target
    end
    return result
end

function TargetSystem:GetPlayersTargeting(targetModel: Model): {Player}
    local players: {Player} = {}
    
    for player, targetData in pairs(self.targets) do
        if targetData.target == targetModel then
            table.insert(players, player)
        end
    end
    
    return players
end

return TargetSystem
