local LoadClientModule = game.ReplicatedStorage.Modules.ClientAbilities.Loaders.LoadModule
local LoadServerModule = game.ReplicatedStorage.Modules.ClientAbilities.Loaders.LoadServerModule

local ClientAbilities = require(game.ReplicatedStorage.Modules.ClientAbilities)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

game:GetService("Players").PlayerAdded:Connect(function(player)
    task.delay(2, function()
        warn(ServerStorage.Abilities:GetChildren())
        for _, mod in ServerStorage.Abilities:GetChildren() do
            local modClone = mod:Clone()
            modClone.Parent = ReplicatedStorage.Modules.ClientAbilities

            LoadClientModule:FireClient(player, modClone.Name, modClone)
        end
    end)
end)


 for _, mod in ServerStorage.Abilities:GetChildren() do
    local modClone = mod:Clone()
    modClone.Parent = ReplicatedStorage.Modules.ClientAbilities
    LoadServerModule:Fire(modClone.Name, modClone)
    print(mod)
end