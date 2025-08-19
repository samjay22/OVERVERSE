local _NetworkServer = require(game.ServerStorage.Modules.Core.NetworkServer)

local CollectionService : CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local TargetCache : {[string] : Model} = {}

_NetworkServer:RegisterRemoteFunction("UpdatePlayerTarget").OnServerInvoke = (function(player: Player, target: Model?)
	local targetKey : string? = player:GetAttribute("targetKey") :: string
    if targetKey and TargetCache[targetKey] then
        local oldModel = TargetCache[targetKey]
        CollectionService:RemoveTag(oldModel, targetKey)
    end

    local newTargetKey = HttpService:GenerateGUID()
    if target then
        TargetCache[newTargetKey] = target
        CollectionService:AddTag(target, newTargetKey)
    end

    player:SetAttribute("targetKey", newTargetKey)
    return newTargetKey
end)