--!strict
--[[
    Enhanced Camera Shake Manager
    
    A centralized manager for camera shake effects using the professional CameraShaker module.
    Provides easy-to-use functions with distance-based intensity scaling while using the 
    proven EZ Camera Shake presets.
    
    USAGE EXAMPLES:
    
    -- Use original presets with distance scaling
    CameraShakeManager.Explosion(impactPosition, 50)  -- Explosion shake within 50 studs
    CameraShakeManager.Bump(hitPosition)              -- Quick bump shake
    CameraShakeManager.Vibration(nil, nil, 0.5)      -- Half-intensity vibration
    
    -- Custom shake with distance scaling
    CameraShakeManager.ShakeOnce(3, 8, 0.1, 1.0, position, 75)
    
    -- Direct access to CameraShaker for advanced usage
    local shaker = CameraShakeManager.CameraShaker
    local customShake = shaker.Presets.Earthquake
    customShake.Magnitude = customShake.Magnitude * 0.5  -- Half intensity
    shaker:Shake(customShake)
    
    @author: GitHub Copilot (using EZ Camera Shake by Road Turtle Games)
    @version: 2.0.0
]]

local Players = game:GetService("Players")

local CameraShaker = require(script.Parent.CameraShaker)

local CameraShakeManager = {}

-- Configuration
local DEFAULT_MAX_DISTANCE = 50 -- Maximum distance for shake effects
local MIN_INTENSITY_THRESHOLD = 0.1 -- Minimum intensity before shake is ignored

-- Singleton camera shaker instance
local cameraShaker: any = nil
local player = Players.LocalPlayer

-- Initialize the camera shaker
local function initializeCameraShaker()
    if cameraShaker then return end
    
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    cameraShaker = CameraShaker.new(Enum.RenderPriority.Camera.Value, function(shakeCFrame)
        -- Get the player's character for reference frame
        local character = player.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: Part?
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        
        if rootPart and humanoid and camera.CameraSubject == humanoid then
            -- Apply shake relative to current camera position
            camera.CFrame = camera.CFrame * shakeCFrame
        else
            -- Fallback: apply shake directly
            camera.CFrame = camera.CFrame * shakeCFrame
        end
    end)
    
    cameraShaker:Start()
end

--- Calculates distance-based intensity falloff
-- @param epicenter Vector3? The center point of the effect
-- @param maxDistance number? Maximum distance for the effect
-- @return number Intensity multiplier (0-1)
local function calculateDistanceFalloff(epicenter: Vector3?, maxDistance: number?): number
    if not epicenter then return 1.0 end
    
    local character = player.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: Part?
    if not rootPart then return 1.0 end
    
    local distance = (epicenter - rootPart.Position).Magnitude
    local maxDist = maxDistance or DEFAULT_MAX_DISTANCE
    
    return math.max(0, 1 - (distance / maxDist))
end

--- Shake the camera using a preset with optional distance-based falloff
-- @param preset string The name of the preset to use
-- @param epicenter Vector3? Optional epicenter for distance-based intensity
-- @param maxDistance number? Maximum distance for the effect
-- @param intensityMultiplier number? Additional intensity multiplier
-- @return table? The shake instance
function CameraShakeManager.ShakePreset(preset: string, epicenter: Vector3?, maxDistance: number?, intensityMultiplier: number?): any?
    initializeCameraShaker()
    if not cameraShaker then return nil end
    
    local falloff = calculateDistanceFalloff(epicenter, maxDistance)
    local finalIntensity = falloff * (intensityMultiplier or 1.0)
    
    if finalIntensity < MIN_INTENSITY_THRESHOLD then return nil end
    
    -- Get the preset shake instance directly from CameraShaker.Presets
    local shakeInstance = CameraShaker.Presets[preset]
    if not shakeInstance then
        warn(`Camera shake preset "{preset}" not found`)
        return nil
    end
    
    -- Scale the magnitude by distance
    shakeInstance.Magnitude = shakeInstance.Magnitude * finalIntensity
    
    return cameraShaker:Shake(shakeInstance)
end

--- Shake the camera once with custom parameters
-- @param magnitude number Intensity of the shake
-- @param roughness number Roughness/frequency of the shake
-- @param fadeInTime number? Time to fade in (default: 0)
-- @param fadeOutTime number? Time to fade out (default: magnitude/2)
-- @param epicenter Vector3? Optional epicenter for distance-based intensity
-- @param maxDistance number? Maximum distance for the effect
-- @return table? The shake instance
function CameraShakeManager.ShakeOnce(
    magnitude: number, 
    roughness: number, 
    fadeInTime: number?, 
    fadeOutTime: number?,
    epicenter: Vector3?, 
    maxDistance: number?
): any?
    initializeCameraShaker()
    if not cameraShaker then return nil end
    
    local falloff = calculateDistanceFalloff(epicenter, maxDistance)
    local finalMagnitude = magnitude * falloff
    
    if finalMagnitude < MIN_INTENSITY_THRESHOLD then return nil end
    
    return cameraShaker:ShakeOnce(
        finalMagnitude,
        roughness,
        fadeInTime or 0,
        fadeOutTime or (magnitude / 2)
    )
end

--- Start a sustained shake effect
-- @param magnitude number Intensity of the shake
-- @param roughness number Roughness/frequency of the shake
-- @param fadeInTime number? Time to fade in (default: 0.5)
-- @param epicenter Vector3? Optional epicenter for distance-based intensity
-- @param maxDistance number? Maximum distance for the effect
-- @return table? The shake instance
function CameraShakeManager.StartShake(
    magnitude: number,
    roughness: number,
    fadeInTime: number?,
    epicenter: Vector3?,
    maxDistance: number?
): any?
    initializeCameraShaker()
    if not cameraShaker then return nil end
    
    local falloff = calculateDistanceFalloff(epicenter, maxDistance)
    local finalMagnitude = magnitude * falloff
    
    if finalMagnitude < MIN_INTENSITY_THRESHOLD then return nil end
    
    return cameraShaker:StartShake(
        finalMagnitude,
        roughness,
        fadeInTime or 0.5
    )
end

--- Stop all sustained shake effects
-- @param fadeOutTime number? Time to fade out (default: 1.0)
function CameraShakeManager.StopSustained(fadeOutTime: number?)
    if not cameraShaker then return end
    cameraShaker:StopSustained(fadeOutTime or 1.0)
end

--- Cleanup the camera shaker
function CameraShakeManager.Cleanup()
    if cameraShaker then
        cameraShaker:Stop()
        cameraShaker = nil
    end
end

-- Convenience functions that use the original CameraShaker presets with distance scaling
CameraShakeManager.Bump = function(epicenter: Vector3?, maxDistance: number?, intensityMultiplier: number?)
    return CameraShakeManager.ShakePreset("Bump", epicenter, maxDistance, intensityMultiplier)
end

CameraShakeManager.Explosion = function(epicenter: Vector3?, maxDistance: number?, intensityMultiplier: number?)
    return CameraShakeManager.ShakePreset("Explosion", epicenter, maxDistance, intensityMultiplier)
end

CameraShakeManager.Earthquake = function(epicenter: Vector3?, maxDistance: number?, intensityMultiplier: number?)
    return CameraShakeManager.ShakePreset("Earthquake", epicenter, maxDistance, intensityMultiplier)
end

CameraShakeManager.Vibration = function(epicenter: Vector3?, maxDistance: number?, intensityMultiplier: number?)
    return CameraShakeManager.ShakePreset("Vibration", epicenter, maxDistance, intensityMultiplier)
end

CameraShakeManager.BadTrip = function(epicenter: Vector3?, maxDistance: number?, intensityMultiplier: number?)
    return CameraShakeManager.ShakePreset("BadTrip", epicenter, maxDistance, intensityMultiplier)
end

CameraShakeManager.HandheldCamera = function(epicenter: Vector3?, maxDistance: number?, intensityMultiplier: number?)
    return CameraShakeManager.ShakePreset("HandheldCamera", epicenter, maxDistance, intensityMultiplier)
end

CameraShakeManager.RoughDriving = function(epicenter: Vector3?, maxDistance: number?, intensityMultiplier: number?)
    return CameraShakeManager.ShakePreset("RoughDriving", epicenter, maxDistance, intensityMultiplier)
end

-- Direct access to the original CameraShaker and its presets for advanced usage
CameraShakeManager.CameraShaker = CameraShaker

-- Initialize when the module is required
task.spawn(initializeCameraShaker)

-- Cleanup on player leaving
player.AncestryChanged:Connect(function()
    if not player.Parent then
        CameraShakeManager.Cleanup()
    end
end)

return CameraShakeManager
