local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Camera = workspace.CurrentCamera

local player = Players.LocalPlayer
local time = 0
local currentTilt = 0
local targetTilt = 0
local TILT_AMPLITUDE = 0.2
local TILT_FREQUENCY = 1
local TILT_LERP_SPEED = 0.08

RunService.RenderStepped:Connect(function(dt)
    local character = player.Character
    if not character then return end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    if humanoid.MoveDirection.Magnitude > 0 then
        time = time + dt
        targetTilt = math.sin(time * TILT_FREQUENCY * math.pi * 2) * TILT_AMPLITUDE
    else
        targetTilt = 0
    end
    
    currentTilt = currentTilt + (targetTilt - currentTilt) * TILT_LERP_SPEED
    Camera.CFrame = Camera.CFrame * CFrame.Angles(0, 0, currentTilt - (Camera.CFrame:ToEulerAnglesXYZ()))
end)