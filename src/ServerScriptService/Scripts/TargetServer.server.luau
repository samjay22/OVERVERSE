--!strict
-- ServerScriptService/TargetSystemServer
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local TargetSystem = require(ReplicatedStorage.Modules.CoreClient:WaitForChild("Targeting"))

-- Initialize the target system on server
local targetSystem = TargetSystem.new()
local TargetCache = {}


-- Example: Listen for target changes
targetSystem:OnTargetChanged(function(player: Player, newTarget: Model?, oldTarget: Model?)
    warn(`Target changed for {player.Name}: {oldTarget} -> {newTarget}`)
    local targetKey : string? = player:GetAttribute("targetKey") :: string
    if targetKey and TargetCache[targetKey] then
        local oldModel = TargetCache[targetKey]
        CollectionService:RemoveTag(oldModel, targetKey)
    end

    local newTargetKey = HttpService:GenerateGUID()
    if newTarget then
        TargetCache[newTargetKey] = newTarget
        CollectionService:AddTag(newTarget, newTargetKey)
        player:SetAttribute("targetKey", newTargetKey)
        player:SetAttribute("CurrentTargetName", newTarget.Name)
    end
end)