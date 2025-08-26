-- Network Server bridge to new NetworkServer with ultra-fast input processing

-- Load the new network server and object pools
local _NetworkServer = require(game.ReplicatedStorage.Modules.Network.Server)

local _CharacterManager = require(game.ServerStorage.Modules.Entities.Character.CharacterManager)
local _WeaponComponent = require(game.ServerStorage.Modules.Components.WeaponComponent)
local _Enums = require(game.ReplicatedStorage.Modules.Types.Enums)

local AllowedInput = {
    [Enum.UserInputType.MouseButton1.Name] = Enum.UserInputType.MouseButton1,
    [Enum.UserInputType.MouseButton2.Name] = Enum.UserInputType.MouseButton2,
    [Enum.UserInputType.Keyboard.Name] = Enum.UserInputType.Keyboard,
}


_NetworkServer.ClientInputEvent.On(function(player, data)
    local validKeycode = AllowedInput[data.KeyCode]  or AllowedInput[data.UserInputType] 
    if not validKeycode then
        return
    end

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

    _CharacterManager:UpdateInputState(characterEntity, validKeycode, data.IsPressed)
end)