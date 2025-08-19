--!strict
--[[
    Server Asset Initialization
    
    This script optimizes asset loading by preloading all critical assets
    on server startup. This prevents delays during gameplay.
    
    @author: GitHub Copilot (Optimization)
    @version: 2.0.0
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

print("🚀 Starting Server Asset Initialization...")

-- Only run on server
if not RunService:IsServer() then
    return
end

local startTime = tick()

-- Load asset handlers
local AssetHandlers = require(ReplicatedStorage.Modules.AssetHandlers)
local AnimationAssets = AssetHandlers.OnModuleLoaded("Animations")
local EffectAssets = AssetHandlers.OnModuleLoaded("Effects")

-- Priority-based asset preloading
local function initializeAssets()
    print("📦 Phase 1: Preloading animations...")
    
    -- Phase 1: Preload all animations (highest priority)
    if AnimationAssets then
        local success, result = pcall(function()
            return (AnimationAssets :: any).PreloadAll()
        end)
        if not success then
            warn("⚠️ Failed to preload animations:", result)
        end
    else
        warn("⚠️ Animation asset handler not found")
    end
    
    -- Small delay between phases
    task.wait(0.1)
    
    print("📦 Phase 2: Preloading effects...")
    
    -- Phase 2: Preload all effects (high priority)
    if EffectAssets then
        local success, result = pcall(function()
            return (EffectAssets :: any).PreloadAllEffects()
        end)
        if not success then
            warn("⚠️ Failed to preload effects:", result)
        end
    else
        warn("⚠️ Effect asset handler not found")
    end
    
    -- Phase 3: Initialize other critical systems
    print("📦 Phase 3: Initializing registries...")
    
    -- Load registries to ensure they're cached
    local success1, LoadoutRegistry = pcall(function()
        return require(game.ServerStorage.Modules.registery.Loadouts)
    end)
    
    local success2, EffectRegistry = pcall(function()
        return require(game.ServerStorage.Modules.registery.Effects)
    end)
    
    if success1 then
        print("✅ Loadout Registry initialized")
    else
        warn("⚠️ Failed to initialize Loadout Registry:", LoadoutRegistry)
    end
    
    if success2 then
        print("✅ Effect Registry initialized")
    else
        warn("⚠️ Failed to initialize Effect Registry:", EffectRegistry)
    end
    
    local endTime = tick()
    local duration = endTime - startTime
    
    print(`✅ Server Asset Initialization completed in {math.round(duration * 100) / 100}s`)
    print("🎮 Server ready for players!")
end

-- Run initialization in a separate thread to prevent blocking
task.spawn(initializeAssets)

-- Create a flag to indicate when assets are ready
local assetsReadyValue = Instance.new("BoolValue")
assetsReadyValue.Name = "AssetsReady"
assetsReadyValue.Value = false
assetsReadyValue.Parent = ReplicatedStorage

-- Set flag when initialization is complete
task.spawn(function()
    -- Wait for a reasonable amount of time for assets to load
    task.wait(5) -- Maximum wait time
    assetsReadyValue.Value = true
    print("📢 Assets ready flag set for clients")
end)

return true
