local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local RemoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ClientInputEvent")

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end

    RemoteEvent:FireServer(input.KeyCode, true)
end)


UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end

    RemoteEvent:FireServer(input.KeyCode, false)
end)
