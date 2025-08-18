--!strict

-- Route all RemoteEvents through the central NetworkServer to keep a single networking surface
local _NetworkServer = require(game.ServerStorage.Modules.Core.NetworkServer)

local Remotes = {}
Remotes.__index = Remotes

function Remotes.init()
    local predictionRemote = _NetworkServer:RegisterRemoteEvent("AbilityPrediction")
    local validationRemote = _NetworkServer:RegisterRemoteEvent("AbilityValidation")
    return predictionRemote, validationRemote
end

return Remotes
