local LoadClientModule = game.ReplicatedStorage.Modules.ClientAbilities.Loaders.LoadModule
local LoadServerModule = game.ReplicatedStorage.Modules.ClientAbilities.Loaders.LoadServerModule

local ClientAbilities = require(game.ReplicatedStorage.Modules.ClientAbilities)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

game:GetService("Players").PlayerAdded:Connect(function(player)
    print("[AbilityInitializer] Loading abilities for player:", player.Name)
    print("[AbilityInitializer] Available abilities:", ServerStorage.Abilities:GetChildren())
    
    for _, mod in ServerStorage.Abilities:GetChildren() do
        print("[AbilityInitializer] Loading ability:", mod.Name)
        local modClone = mod:Clone()
        modClone.Parent = ReplicatedStorage.Modules.ClientAbilities
        
        LoadClientModule:FireClient(player, mod.Name, modClone)
        print("[AbilityInitializer] Sent", mod.Name, "to client")
    end
    
    print("[AbilityInitializer] Finished loading abilities for player:", player.Name)
end)


print("[AbilityInitializer] Loading server abilities...")
for _, mod in ServerStorage.Abilities:GetChildren() do
    print("[AbilityInitializer Server] Loading ability:", mod.Name)
    local modClone = mod:Clone()
    modClone.Parent = ReplicatedStorage.Modules.ClientAbilities
    LoadServerModule:Fire(mod.Name, modClone)
    print("[AbilityInitializer Server] Loaded:", mod.Name)
end
print("[AbilityInitializer] Server abilities loaded")