local Players = game:GetService("Players")
local AbilityComponent = require(game.ServerStorage.Modules.Components.AbilityComponent)
local AbilityInputHandler = require(game.ServerStorage.Modules.Handlers.AbilityInputHandler)

AbilityInputHandler.onAbilityActivated = function(inputType, abilityName, characterData)
    -- characterData is a table containing { loadout, keyBindings, character, name }
    local characterName = characterData.name or "Unknown"
    local character = characterData.character
    
    if not character then
        warn("No character in characterData for ability activation")
        return
    end
    
    -- Commented out to reduce spam
    -- print(`Ability activated: ${abilityName} for ${characterName}`)
    
    -- Get the player - character has Entity field with player reference
    local player = nil
    if character.Entity and character.Entity.player then
        player = character.Entity.player
    elseif character.Player then
        player = character.Player
    elseif character.PlayerId then
        -- PlayerId is actually the UserId for players
        for _, p in ipairs(Players:GetPlayers()) do
            if p.UserId == character.PlayerId then
                player = p
                break
            end
        end
    end
    
    if player then
        AbilityComponent.Activate(player, abilityName)
    else
        warn("Could not find player for ability activation - PlayerId:", character.PlayerId)
    end
end