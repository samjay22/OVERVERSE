--!strict
-- MouseTracker: Sends mouse position updates to server for ability targeting

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Camera = workspace.CurrentCamera

-- Dependencies
local NetworkClient = require(ReplicatedStorage.Modules.Network.Client)

-- Constants
local LOCAL_PLAYER = Players.LocalPlayer
local MOUSE_UPDATE_RATE = 0.1 -- Update every 100ms to avoid network spam
local DEBUG_ENABLED = false -- Set to true for debugging

-- State
local lastUpdateTime = 0
local isEnabled = true
local mouse = LOCAL_PLAYER:GetMouse()

-- Debug logging
local function debugLog(message: string)
    if DEBUG_ENABLED then
        print(`[MouseTracker] {message}`)
    end
end

-- Get mouse ray data
local function getMouseRayData(): (Vector3, Vector3, Vector3)
    if not Camera then
        return nil
    end
    
    -- Get mouse position in 3D world
    local mouseHit = mouse.Hit
    local mouseOrigin = Camera.CFrame.Position
    
    -- Calculate unit direction from camera to mouse hit
    local direction = (mouseHit.Position - mouseOrigin)
    local mouseUnit = direction.Unit
    
    return mouseHit.Position, mouseUnit, mouseOrigin
end

-- Send mouse update to server
local function sendMouseUpdate()
    local currentTime = tick()
    
    -- Rate limit updates
    if currentTime - lastUpdateTime < MOUSE_UPDATE_RATE then
        return
    end
    
    -- Get mouse data
    local mouseHitPos, mouseUnitDir, origin = getMouseRayData()
    if not mouseHitPos then
        return
    end
    
    -- Get screen position
    local screenPos = Vector3.new(mouse.X, mouse.Y, 0)
    
    -- Send update via network
    local updateData = {
        MouseHit = mouseHitPos,
        MouseUnit = mouseUnitDir,
        Origin = origin,
        MouseScreenPosition = screenPos
    }
    
    NetworkClient.UpdateMouse.Fire(updateData)
    lastUpdateTime = currentTime
    
    if DEBUG_ENABLED and math.random() < 0.1 then -- Log 10% of updates to reduce spam
        debugLog(`Sent mouse update - Hit: {mouseHitPos}, Unit: {mouseUnitDir}`)
    end
end

-- Handle mouse movement
local function onMouseMove()
    if not isEnabled then
        return
    end
    
    -- Only send updates when character exists
    if not LOCAL_PLAYER.Character then
        return
    end
    
    sendMouseUpdate()
end

-- Handle input began (for immediate updates on clicks)
local function onInputBegan(input: InputObject, gameProcessed: boolean)
    if gameProcessed then
        return
    end
    
    -- Send immediate update on mouse clicks
    if input.UserInputType == Enum.UserInputType.MouseButton1 or 
       input.UserInputType == Enum.UserInputType.MouseButton2 then
        sendMouseUpdate()
        debugLog(`Mouse click detected - sending immediate update`)
    end
end

-- Initialize
local function initialize()
    debugLog(`Initializing mouse tracker`)
    
    -- Connect mouse movement (throttled via sendMouseUpdate)
    mouse.Move:Connect(onMouseMove)
    
    -- Connect input for immediate updates on clicks
    UserInputService.InputBegan:Connect(onInputBegan)
    
    isEnabled = true
    debugLog(`Mouse tracker initialized successfully`)
end

-- Start the tracker
initialize()