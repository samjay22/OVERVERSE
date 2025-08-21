-- Network Server bridge to new NetworkServer with ultra-fast input processing

-- Load the new network server and object pools
local _NetworkServer: INetworkManager = require(game.ServerStorage.Modules.Core.NetworkServer)

local _WeaponComponent = require(game.ServerStorage.Modules.Components.WeaponComponent)
local _Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local _NetworkTypes = require(game.ReplicatedStorage.Modules.Types.NetworkTypes)

_NetworkServer:RegisterRemoteEvent("StartCharacterAnimation").OnServerEvent:Connect(function(p)
    warn(p, "tried to start character animation without server-side support")
    error("Not supported")
end)
