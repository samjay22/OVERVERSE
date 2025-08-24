local LoadClientModule = game.ReplicatedStorage.Modules.ClientAbilities.Loaders.LoadModule
local LoadServerModule = game.ReplicatedStorage.Modules.ClientAbilities.Loaders.LoadServerModule

local _ = require(game.ReplicatedStorage.Modules.ClientAbilities)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

game:GetService("Players").PlayerAdded:Connect(function(player)
    repeat task.wait() until #ReplicatedStorage.Modules.ClientAbilities:GetChildren() > 0

    for _, mod in ReplicatedStorage.Modules.ClientAbilities:GetChildren() do
        LoadClientModule:FireClient(player, mod.Name, mod)
    end
    
    print("[AbilityInitializer] Finished loading abilities for player:", player.Name)
end)

repeat task.wait() until #ReplicatedStorage.Modules.ClientAbilities:GetChildren() > 0

for _, mod in ReplicatedStorage.Modules.ClientAbilities:GetChildren() do
    LoadServerModule:Fire(mod.Name, mod)
end
print("[AbilityInitializer] Server abilities loaded")