--!strict
-- M1RaycastTest: Server-side test script to verify M1 raycast functionality

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Configuration
local TEST_ENABLED = true -- Set to false to disable test output
local SHOW_RAYCAST_VISUALIZATION = true -- Shows visual ray in workspace

-- Create part for visualization
local function createRayVisualization(origin: Vector3, direction: Vector3, distance: number, hit: boolean)
    if not SHOW_RAYCAST_VISUALIZATION then
        return
    end
    
    local rayPart = Instance.new("Part")
    rayPart.Name = "RaycastVisualization"
    rayPart.Anchored = true
    rayPart.CanCollide = false
    rayPart.Material = Enum.Material.ForceField
    rayPart.Color = hit and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)
    rayPart.Size = Vector3.new(0.2, 0.2, distance)
    rayPart.CFrame = CFrame.lookAt(origin + direction * (distance/2), origin + direction * distance)
    rayPart.Parent = workspace
    
    -- Auto cleanup
    game:GetService("Debris"):AddItem(rayPart, 2)
    
    -- Create hit indicator
    if hit then
        local hitPart = Instance.new("Part")
        hitPart.Name = "RaycastHit"
        hitPart.Shape = Enum.PartType.Ball
        hitPart.Material = Enum.Material.Neon
        hitPart.Size = Vector3.new(1, 1, 1)
        hitPart.Color = Color3.new(1, 1, 0)
        hitPart.Anchored = true
        hitPart.CanCollide = false
        hitPart.Position = origin + direction * distance
        hitPart.Parent = workspace
        
        game:GetService("Debris"):AddItem(hitPart, 2)
    end
end

-- Monitor raycast events (hook into M1 ability logs)
local function monitorRaycasts()
    -- This monitors the console output for raycast logs
    -- In production, you'd want to create proper event hooks
    
    warn("[M1RaycastTest] Monitoring M1 raycasts - look for the following in console:")
    warn("  - [MouseTracker] messages show client sending mouse updates")
    warn("  - [MouseComponent] messages show server receiving mouse position")
    warn("  - [InputComponent] messages show M1 processing with mouse position")
    warn("  - [AbilityComponent] messages show ability system handling")
    warn("  - [M1 Server] messages show raycast execution and results")
end

-- Test command handler
local function onPlayerChatted(player: Player, message: string)
    if not TEST_ENABLED then
        return
    end
    
    local lowerMessage = string.lower(message)
    
    if lowerMessage == "/testraycast" then
        warn(`[M1RaycastTest] {player.Name} requested raycast test`)
        warn("Instructions:")
        warn("1. Move your mouse to different positions")
        warn("2. Click M1 (left mouse button)")
        warn("3. Watch console for debug messages")
        warn("4. Green rays = hit something, Red rays = missed")
    elseif lowerMessage == "/togglerayvis" then
        SHOW_RAYCAST_VISUALIZATION = not SHOW_RAYCAST_VISUALIZATION
        warn(`[M1RaycastTest] Ray visualization: {SHOW_RAYCAST_VISUALIZATION and "ENABLED" or "DISABLED"}`)
    elseif lowerMessage == "/debugmouse" then
        -- Check if player has mouse component
        local CharacterManager = require(game.ServerStorage.Modules.Entities.Character.CharacterManager)
        local characterData = CharacterManager:GetCharacter(player.UserId)
        
        if characterData and characterData.Components.Mouse then
            local mouseComp = characterData.Components.Mouse
            warn(`[M1RaycastTest] Mouse data for {player.Name}:`)
            warn(`  Position: {mouseComp.MouseHitPosition}`)
            warn(`  Valid: {mouseComp.IsValid}`)
            warn(`  Last Update: {tick() - mouseComp.LastUpdateTime}s ago`)
        else
            warn(`[M1RaycastTest] No mouse component found for {player.Name}`)
        end
    end
end

-- Initialize
local function initialize()
    if not TEST_ENABLED then
        return
    end
    
    warn("[M1RaycastTest] Test script initialized")
    warn("Commands:")
    warn("  /testraycast - Show test instructions")
    warn("  /togglerayvis - Toggle ray visualization")
    warn("  /debugmouse - Show current mouse data")
    
    -- Connect chat commands
    Players.PlayerAdded:Connect(function(player)
        player.Chatted:Connect(function(message)
            onPlayerChatted(player, message)
        end)
    end)
    
    -- Start monitoring
    monitorRaycasts()
end

-- Run initialization
initialize()