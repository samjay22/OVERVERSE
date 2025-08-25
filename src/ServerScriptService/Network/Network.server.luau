-- Network Server bridge to new NetworkServer with ultra-fast input processing

-- Load the new network server and object pools
local _NetworkServer = require(game.ServerStorage.Modules.Core.NetworkServer)

local _CharacterManager = require(game.ServerStorage.Modules.Entities.Character.CharacterManager)
local _WeaponComponent = require(game.ServerStorage.Modules.Components.WeaponComponent)
local _Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local _NetworkTypes = require(game.ReplicatedStorage.Modules.Types.NetworkTypes)

_NetworkServer:RegisterRemoteEvent("StartCharacterAnimation").OnServerEvent:Connect(function(p)
    warn(p, "tried to start character animation without server-side support")
    error("Not supported")
end)

_NetworkServer:RegisterRemoteEvent("ClientInputEvent").OnServerEvent:Connect(function(player: Player, key, state)
    local character = player.Character
    if not character then
        return
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end
    
    local characterEntity = _CharacterManager:GetCharacterData(player)
    if not characterEntity then
        return warn("Character data not found")
    end

    _= _CharacterManager:UpdateInputState(characterEntity, key, state)
end)