local Players = game:GetService("Players")
local AbilityComponent = require(game.ServerStorage.Modules.Components.AbilityComponent)
local AbilityInputHandler = require(game.ServerStorage.Modules.Handlers.AbilityInputHandler)

AbilityInputHandler.onAbilityActivated = function(inputType, abilityName, character)
    print(`Ability activated: ${abilityName} for ${character}`)
    AbilityComponent.Activate(Players:GetPlayerByUserId(character.PlayerId), abilityName)
end