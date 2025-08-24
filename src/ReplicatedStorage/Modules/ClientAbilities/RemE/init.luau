local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(game.ReplicatedStorage.Modules.Types.ClientAbilityTypes)

local Package : Types.AbilityPackage = {
    Config = script.Config,
    Server = script.Server,
    Shared = script.Shared,
    Assets = script.Assets,
    Client = script.Client,
}

return Package