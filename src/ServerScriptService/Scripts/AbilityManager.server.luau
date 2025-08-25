local _NetworkServer = require(game.ServerStorage.Modules.Core.NetworkServer) 
local CharacterManager = require(game.ServerStorage.Modules.Entities.Character.CharacterManager)

CharacterManager:OnCharacterAdded(function(character)
    character.OnStateChange.Event:Connect(function(name, value, old)
        if name == "ActiveKeys" then
            for key, abilityName in next, character.Components.Ability do
                print(value, key)
                if value[key.Value] then
                    warn(abilityName)
                end
            end
        end
    end)
end)