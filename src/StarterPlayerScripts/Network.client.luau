--!nonstrict
local CoreRemote : RemoteEvent = game.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CoreEvent")
local Camera : Camera = workspace.CurrentCamera
local Player : Player = game.Players.LocalPlayer

CoreRemote.OnClientEvent:Connect(function(eventName, ...)
    if eventName == "CharacterSpawned" then
        local spawnTime, character = ...
        if character then
            Camera.CameraSubject = character:WaitForChild("Humanoid")
            
            -- Reparent animator script to character if needed
            local animatorScript = game.ReplicatedStorage:WaitForChild("Animate")
            if animatorScript then
                animatorScript.Parent = game.Workspace
                task.wait()
                animatorScript.Parent = character
            end
            
        else
            warn("Invalid character provided", spawnTime)
        end
    elseif eventName == "StartBaseAnimations" then
        local animateScript = ...
        if animateScript and animateScript:IsA("LocalScript") then
            local playerCharacter = Player.Character or Player.CharacterAdded:Wait()
            animateScript.Parent = playerCharacter
            animateScript.Enabled = true
        end
    else
        warn("Unknown event received from server: " .. eventName)
    end
end)