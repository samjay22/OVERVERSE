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
    network: any -- Blink network module
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
    
    -- Get the network module
    local NetworkModule
    if self.isServer then
        NetworkModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Network"):WaitForChild("Server"))
    else
        NetworkModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Network"):WaitForChild("Client"))
    end
    
    self.network = NetworkModule
    
    -- Initialize based on context
    if self.isServer then
        self:_initServer()
    else
        self:_initClient()
    end
    
    instance = self
    return self
end


function TargetSystem:_initServer(): ()
    -- Handle client requests to set target using Blink network module
    self.network.SetTarget.On(function(player: Player, targetModel: Model?)
        self:_serverSetTarget(player, targetModel)
    end)
    
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
    
    -- Listen for target changes from server using Blink network module
    self.network.TargetChanged.On(function(targetModel: Model?)
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
    
    -- Notify client using Blink network module
    self.network.TargetChanged.Fire(player, targetModel)
    
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
        -- Client-side: send request to server using Blink network module
        if targetModel and not targetModel:IsA("Model") then
            warn("Target must be a Model")
            return false
        end
        
        self.network.SetTarget.Fire(targetModel)
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
