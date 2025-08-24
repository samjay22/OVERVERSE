local LoadClientModule = game.ReplicatedStorage.Modules.ClientAbilities.Loaders.LoadModule
local LoadServerModule = game.ReplicatedStorage.Modules.ClientAbilities.Loaders.LoadServerModule

local _ = require(game.ReplicatedStorage.Modules.ClientAbilities)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

game:GetService("Players").PlayerAdded:Connect(function(player)
    print("[AbilityInitializer] Loading abilities for player:", player.Name)
    repeat task.wait() until #ReplicatedStorage.Modules.ClientAbilities:GetChildren() > 0

    for _, mod in ReplicatedStorage.Modules.ClientAbilities:GetChildren() do
        print("[AbilityInitializer] Loading ability:", mod.Name)
        local modClone = mod:Clone()
        modClone.Parent = ReplicatedStorage.Modules.ClientAbilities
        
        LoadClientModule:FireClient(player, mod.Name, modClone)
        print("[AbilityInitializer] Sent", mod.Name, "to client")
    end
    
    print("[AbilityInitializer] Finished loading abilities for player:", player.Name)
end)

repeat task.wait() until #ReplicatedStorage.Modules.ClientAbilities:GetChildren() > 0

print("[AbilityInitializer] Loading server abilities...")
for _, mod in ReplicatedStorage.Modules.ClientAbilities:GetChildren() do
    print("[AbilityInitializer Server] Loading ability:", mod.Name)
    LoadServerModule:Fire(mod.Name, mod)
    print("[AbilityInitializer Server] Loaded:", mod.Name)
end
print("[AbilityInitializer] Server abilities loaded")