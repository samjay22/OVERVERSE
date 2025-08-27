--!strict
-- Display network ping information for debugging

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LOCAL_PLAYER = Players.LocalPlayer

-- Create GUI to display ping
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NetworkPingDisplay"
screenGui.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 200, 0, 100)
frame.Position = UDim2.new(0, 10, 0, 10)
frame.BackgroundColor3 = Color3.new(0, 0, 0)
frame.BackgroundTransparency = 0.3
frame.BorderSizePixel = 0
frame.Parent = screenGui

local pingLabel = Instance.new("TextLabel")
pingLabel.Size = UDim2.new(1, 0, 0.5, 0)
pingLabel.Position = UDim2.new(0, 0, 0, 0)
pingLabel.BackgroundTransparency = 1
pingLabel.Text = "Ping: -- ms"
pingLabel.TextColor3 = Color3.new(1, 1, 1)
pingLabel.TextScaled = true
pingLabel.Font = Enum.Font.SourceSansBold
pingLabel.Parent = frame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0.5, 0)
statusLabel.Position = UDim2.new(0, 0, 0.5, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Network Compensation: ON"
statusLabel.TextColor3 = Color3.new(0, 1, 0)
statusLabel.TextScaled = true
statusLabel.Font = Enum.Font.SourceSans
statusLabel.Parent = frame

-- Update ping display
local function updatePingDisplay()
    local ping = LOCAL_PLAYER:GetNetworkPing()
    local pingMs = math.floor(ping * 1000)
    
    pingLabel.Text = `Ping: {pingMs} ms`
    
    -- Color code based on ping quality
    if pingMs < 50 then
        pingLabel.TextColor3 = Color3.new(0, 1, 0) -- Green
    elseif pingMs < 100 then
        pingLabel.TextColor3 = Color3.new(1, 1, 0) -- Yellow
    else
        pingLabel.TextColor3 = Color3.new(1, 0, 0) -- Red
    end
end

-- Update every second
RunService.Heartbeat:Connect(function()
    if tick() % 1 < 0.016 then -- Roughly once per second
        updatePingDisplay()
    end
end)

print("[NetworkPingDisplay] Initialized - Showing network ping information")
