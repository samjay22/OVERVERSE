local RS = game:GetService("RunService")

local CameraFollow = require(game.ReplicatedStorage.Modules.CoreClient.CameraFollow)
local ShiftLock = require(game.ReplicatedStorage.Modules.CoreClient.ShiftLock)

local charAddedCallback =  CameraFollow:Init()

local lastChar : Model?
local Player = game.Players.LocalPlayer

RS.RenderStepped:Connect(function(deltaTime)
    if Player.Character and Player.Character ~= lastChar then
        lastChar = Player.Character
        charAddedCallback(Player.Character)
        ShiftLock:Enable()
        ShiftLock:_refreshCharacterVariables()
    end
end)