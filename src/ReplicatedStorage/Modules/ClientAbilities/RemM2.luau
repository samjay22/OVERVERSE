--!strict
-- Client Ability: RemM2 - Orb projectile with bloom effect on impact

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Types = require(game.ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local CameraShakeManager = require(game.ReplicatedStorage.Modules.Utility.CameraShakeManager)

local Player: Player = Players.LocalPlayer

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

-- Ability Configuration
local ABILITY_CLASS = "Rem"
local ANIMATION_NAME = "M1"
local COOLDOWN_TIME = 1.0
local ATTACK_RANGE = 100
local REQUIRES_TARGET = true

-- Animation Constants
local ANIM_FADE_TIME = 0.05
local ANIM_PRIORITY = Enum.AnimationPriority.Action

-- Projectile Constants - Consistent travel time regardless of distance
local PROJECTILE_TRAVEL_TIME = 0.8 -- Fixed travel time in seconds
local PROJECTILE_SIZE = Vector3.new(1.2, 1.2, 1.2) -- Enhanced orb size
local PROJECTILE_COLOR = Color3.new(0.9, 0.15, 1) -- More vibrant purple

-- Visual Enhancement Constants
local MAIN_ORB = {
    PULSE_SPEED = 10,
    PULSE_INTENSITY = 0.3,
    SPIN_SPEED = 12,
    GLOW_BRIGHTNESS = 8,
    GLOW_RANGE = 30,
}

local SATELLITES = {
    COUNT = 8,
    SIZE_BASE = 0.35,
    RADIUS_BASE = 1.8,
    ORBIT_SPEED = 4,
    PULSE_SPEED = 7,
    BRIGHTNESS = 3,
}

local EFFECTS = {
    CLEANUP_TIME = 0.4,
    PARTICLE_RATE = 150,
    TRAIL_LIFETIME = 0.4,
    
    -- Enhanced AAA-quality visual effects
    BLOOM = {
        INTENSITY = 3.2,
        SIZE = 40,
        THRESHOLD = 1.2,
        TWEEN_IN = 0.12,
        TWEEN_OUT = 0.4
    },
    SCREEN_PULSE = {
        FOV_DELTA = 6,
        COLOR_INTENSITY = 0.28,
        FADE_DURATION = 0.5
    },
    CAMERA_SHAKE = {
        INTENSITY = 1.0,  -- Base trauma intensity (0-1 range)
        DURATION = 0.6,   -- Slightly longer for better feel
        FREQUENCY = 25,   -- Base frequency for main shake
        MAX_DISTANCE = 50, -- Maximum distance for shake effect
        ROTATION_SCALE = 2.0, -- Multiplier for rotational shake
        POSITION_SCALE = 0.8, -- Multiplier for positional shake
    },
    SHOCKWAVE = {
        RING_COUNT = 6,
        MAX_SIZE = 35,
        EXPANSION_TIME = 1.8,
        TRANSPARENCY_START = 0.15,
        RING_WIDTH = 2.5
    },
    PARTICLE_BURST = {
        COUNT = 85,
        LIFETIME = 2.8,
        SPREAD_ANGLE = 360,
        VELOCITY_RANGE = {Min = 8, Max = 24}
    },
    IMPACT_LIGHT = {
        BRIGHTNESS = 5.0,
        RANGE = 18,
        COLOR = Color3.new(0.4, 0.1, 0.8),
        FADE_TIME = 1.2
    }
}



local Ability = {}

-- Forward declarations
local executeAttack: (number?, Vector3?) -> ()
local playCharacterAnimation: (string, Vector3?) -> AnimationTrack?

-- Ability Interface Functions
function Ability.OnRequest(ctx: SharedAbilityContext): AbilityResult
    return {
        success = true,
        cooldowns = { [tostring(ctx.abilityId)] = ctx.timestamp + COOLDOWN_TIME },
    }
end

function Ability.OnReplicate(ctx: SharedAbilityContext, serverData: any?)
    -- Handle replication from other clients (latency compensated)
    local targetPosition = ctx.inputData.target
    task.spawn(executeAttack, ctx and ctx.timestamp, targetPosition)
end

function Ability.OnCast(ctx: SharedAbilityContext, serverData: any?)
    -- Local client: play animation, projectile will spawn precisely on "Fire" event/keyframe
    -- Store the target position from the context for use during animation
    local targetPosition = ctx.inputData.target
    task.spawn(playCharacterAnimation, ANIMATION_NAME, targetPosition)
end

function Ability.onCancel(ctx: SharedAbilityContext, reason: string?)
    -- Implementation if needed
end

-- Helper Functions
local function doEffect(character: Model?, targetPosition: Vector3?)
    if not character then
        warn("Invalid character for effect")
        return
    end

    -- Wait for Effects folder to replicate from server (with timeout)
    local effectsFolder = character:FindFirstChild("Effects")
    if not effectsFolder then
        effectsFolder = character:WaitForChild("Effects", 5) -- Wait up to 5 seconds
    end
    
    if not effectsFolder then
        warn("No Effects folder in character after waiting")
        return
    end

    local effect = effectsFolder:FindFirstChild("M2")
    if not effect then
        warn("No M2 effect found in Effects folder")
        return
    end

    -- Create effect at target position if available, otherwise at character position
    local effectPosition = targetPosition or (character.PrimaryPart and character.PrimaryPart.Position)
    if not effectPosition then
        warn("No valid position for effect")
        return
    end

    -- Create a temporary invisible part to attach the effect to
    local effectPart = Instance.new("Part")
    effectPart.Name = "EffectAnchor"
    effectPart.Size = Vector3.new(0.1, 0.1, 0.1)
    effectPart.Transparency = 1
    effectPart.CanCollide = false
    effectPart.Anchored = true
    effectPart.CFrame = CFrame.new(effectPosition)
    effectPart.Parent = workspace

    local effectClone = effect:Clone()
    effectClone.Parent = effectPart
    
    -- Clean up both the effect and the anchor part
    Debris:AddItem(effectPart, EFFECTS.CLEANUP_TIME)
end

local function pulsePostEffects()
    -- Bloom (ensure concrete type)
    local bloom = (Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")) :: BloomEffect
    if not bloom.Parent then
        bloom.Name = "RemM2Bloom"
        bloom.Parent = Lighting
    end
    local origBloom = {
        Intensity = bloom.Intensity,
        Size = bloom.Size,
        Threshold = bloom.Threshold,
    }
    local tweenInBloom = TweenService:Create(bloom, TweenInfo.new(EFFECTS.BLOOM.TWEEN_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Intensity = EFFECTS.BLOOM.INTENSITY,
        Size = EFFECTS.BLOOM.SIZE,
        Threshold = EFFECTS.BLOOM.THRESHOLD,
    })
    local tweenOutBloom = TweenService:Create(bloom, TweenInfo.new(EFFECTS.BLOOM.TWEEN_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), origBloom)

    -- Color correction punch (no blur)
    local cc = (Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")) :: ColorCorrectionEffect
    if not cc.Parent then cc.Name = "RemM2Color"; cc.Parent = Lighting end
    local origCC = { Brightness = cc.Brightness, Contrast = cc.Contrast, Saturation = cc.Saturation }
    local tweenInCC = TweenService:Create(cc, TweenInfo.new(EFFECTS.BLOOM.TWEEN_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { 
        Brightness = EFFECTS.SCREEN_PULSE.COLOR_INTENSITY, 
        Contrast = 0.25, 
        Saturation = -0.05 
    })
    local tweenOutCC = TweenService:Create(cc, TweenInfo.new(EFFECTS.BLOOM.TWEEN_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), origCC)

    -- FOV pulse
    local cam = workspace.CurrentCamera
    local fovOrig = cam and cam.FieldOfView or nil

    tweenInBloom:Play(); tweenInCC:Play()
    if cam and fovOrig then
        local fovIn = TweenService:Create(cam, TweenInfo.new(EFFECTS.BLOOM.TWEEN_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { 
            FieldOfView = fovOrig + EFFECTS.SCREEN_PULSE.FOV_DELTA 
        })
        local fovOut = TweenService:Create(cam, TweenInfo.new(EFFECTS.BLOOM.TWEEN_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { 
            FieldOfView = fovOrig 
        })
        fovIn:Play()
        fovIn.Completed:Connect(function()
            fovOut:Play()
        end)
    end

    tweenInBloom.Completed:Connect(function()
        tweenOutBloom:Play(); tweenOutCC:Play()
    end)
end

local function createImpactLight(position: Vector3)
    local anchor = Instance.new("Part")
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(0.1, 0.1, 0.1)
    anchor.CFrame = CFrame.new(position)
    anchor.Parent = workspace

    local light = Instance.new("PointLight")
    light.Color = EFFECTS.IMPACT_LIGHT.COLOR
    light.Range = EFFECTS.IMPACT_LIGHT.RANGE
    light.Brightness = EFFECTS.IMPACT_LIGHT.BRIGHTNESS
    light.Parent = anchor

    local tween = TweenService:Create(light, TweenInfo.new(EFFECTS.IMPACT_LIGHT.FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { 
        Brightness = 0, 
        Range = 0 
    })
    tween:Play()
    tween.Completed:Connect(function()
        anchor:Destroy()
    end)
end

local function createShockwave(position: Vector3)
    -- Create perfect circular shockwave with multiple rings
    for i = 1, EFFECTS.SHOCKWAVE.RING_COUNT do
        local ring = Instance.new("Part")
        ring.Name = "RemM2Shockwave"
        ring.Anchored = true
        ring.CanCollide = false
        ring.Material = Enum.Material.ForceField
        ring.Color = PROJECTILE_COLOR
        ring.Transparency = EFFECTS.SHOCKWAVE.TRANSPARENCY_START
        ring.Size = Vector3.new(0.1, EFFECTS.SHOCKWAVE.RING_WIDTH, 0.1)
        ring.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0)
        ring.Shape = Enum.PartType.Cylinder
        ring.Parent = workspace

        -- Add a circular mesh for perfect ring shape
        local mesh = Instance.new("SpecialMesh")
        mesh.MeshType = Enum.MeshType.Cylinder
        mesh.Scale = Vector3.new(1, 1, 1)
        mesh.Parent = ring

        -- Stagger rings for layered effect
        local delay = (i - 1) * 0.06
        local duration = EFFECTS.SHOCKWAVE.EXPANSION_TIME * (0.8 + i * 0.1)
        
        task.spawn(function()
            task.wait(delay)
            
            -- Perfect circular expansion
            local startSize = 0.1
            local endSize = EFFECTS.SHOCKWAVE.MAX_SIZE + (i * 2)
            local connection: RBXScriptConnection
            local startTime = time()
            
            connection = RunService.Heartbeat:Connect(function()
                local elapsed = time() - startTime
                local t = math.clamp(elapsed / duration, 0, 1)
                
                if t >= 1 then
                    ring:Destroy()
                    connection:Disconnect()
                    return
                end
                
                -- Smooth circular expansion with easing
                local ease = 1 - math.pow(1 - t, 3) -- Ease out cubic
                local currentSize = startSize + (endSize - startSize) * ease
                local height = EFFECTS.SHOCKWAVE.RING_WIDTH * (1 - t * 0.7)
                
                ring.Size = Vector3.new(currentSize, height, currentSize)
                ring.Transparency = EFFECTS.SHOCKWAVE.TRANSPARENCY_START + (1 - EFFECTS.SHOCKWAVE.TRANSPARENCY_START) * t
                
                -- Add subtle rotation for dynamic effect
                ring.CFrame = ring.CFrame * CFrame.Angles(0, math.rad(elapsed * 30), 0)
            end)
        end)
    end
end

local function createImplosion(position: Vector3, onComplete: (() -> ())?)
    -- Create dramatic implosion effect with inward particle streams
    local anchor = Instance.new("Part")
    anchor.Name = "RemM2ImplosionAnchor"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(0.1, 0.1, 0.1)
    anchor.CFrame = CFrame.new(position)
    anchor.Parent = workspace

    -- Create multiple implosion particle streams from different angles
    local implosionStreams = {}
    local streamCount = 12
    local implosionRadius = 15
    
    for i = 1, streamCount do
        local angle = (i / streamCount) * math.pi * 2
        local height = (i % 3 - 1) * 3 -- Vary heights for 3D effect
        
        -- Create stream anchor
        local streamAnchor = Instance.new("Part")
        streamAnchor.Anchored = true
        streamAnchor.CanCollide = false
        streamAnchor.Transparency = 1
        streamAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
        streamAnchor.CFrame = CFrame.new(
            position + Vector3.new(
                math.cos(angle) * implosionRadius,
                height,
                math.sin(angle) * implosionRadius
            )
        )
        streamAnchor.Parent = workspace
        
        local att = Instance.new("Attachment")
        att.Parent = streamAnchor
        
        -- Implosion particles
        local imploder = Instance.new("ParticleEmitter")
        imploder.Name = "ImplosionStream"
        imploder.Parent = att
        imploder.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(0.3, PROJECTILE_COLOR),
            ColorSequenceKeypoint.new(1, Color3.new(0.2, 0.05, 0.4)),
        })
        imploder.LightEmission = 1
        imploder.Texture = "rbxassetid://241594419"
        imploder.Lifetime = NumberRange.new(0.8, 1.2)
        imploder.Rate = 200
        imploder.Speed = NumberRange.new(12, 18)
        imploder.SpreadAngle = Vector2.new(15, 15)
        imploder.Drag = 8
        imploder.VelocityInheritance = 0
        imploder.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.6),
            NumberSequenceKeypoint.new(0.7, 0.2),
            NumberSequenceKeypoint.new(1, 0),
        })
        imploder.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.9, 0.3),
            NumberSequenceKeypoint.new(1, 1),
        })
        
        -- Point particles toward center
        local direction = (position - streamAnchor.Position).Unit
        att.CFrame = CFrame.lookAt(Vector3.new(), direction)
        
        table.insert(implosionStreams, {anchor = streamAnchor, emitter = imploder})
    end
    
    -- Create central vortex effect
    local vortexAtt = Instance.new("Attachment")
    vortexAtt.Parent = anchor
    
    local vortex = Instance.new("ParticleEmitter")
    vortex.Name = "ImplosionVortex"
    vortex.Parent = vortexAtt
    vortex.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, PROJECTILE_COLOR),
        ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
    })
    vortex.LightEmission = 0.9
    vortex.Texture = "rbxassetid://241594419"
    vortex.Lifetime = NumberRange.new(0.2, 0.4)
    vortex.Rate = 300
    vortex.Speed = NumberRange.new(0.5, 2)
    vortex.SpreadAngle = Vector2.new(360, 360)
    vortex.Drag = 15
    vortex.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 0),
    })
    vortex.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.1),
        NumberSequenceKeypoint.new(1, 1),
    })
    
    -- Implosion sequence timing with screen distortion
    local implosionDuration = 0.4
    
    -- Add dramatic screen distortion during implosion
    local cam = workspace.CurrentCamera
    if cam then
        local originalFOV = cam.FieldOfView
        local distortionTween = TweenService:Create(cam, 
            TweenInfo.new(implosionDuration * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), 
            {FieldOfView = originalFOV - 8}
        )
        local restoreTween = TweenService:Create(cam, 
            TweenInfo.new(implosionDuration * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), 
            {FieldOfView = originalFOV}
        )
        
        distortionTween:Play()
        distortionTween.Completed:Connect(function()
            restoreTween:Play()
        end)
    end
    
    -- Stop all implosion effects and trigger explosion
    task.delay(implosionDuration, function()
        for _, stream in ipairs(implosionStreams) do
            stream.emitter.Enabled = false
            Debris:AddItem(stream.anchor, 1)
        end
        vortex.Enabled = false
        Debris:AddItem(anchor, 1)
        
        if onComplete then
            onComplete()
        end
    end)
end

local function emitImpactBurst(position: Vector3)
    local anchor = Instance.new("Part")
    anchor.Name = "RemM2ImpactAnchor"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(0.1, 0.1, 0.1)
    anchor.CFrame = CFrame.new(position)
    anchor.Parent = workspace

    local att = Instance.new("Attachment")
    att.Parent = anchor

    local burst = Instance.new("ParticleEmitter")
    burst.Name = "ImpactBurst"
    burst.Parent = att
    burst.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, PROJECTILE_COLOR),
        ColorSequenceKeypoint.new(0.7, PROJECTILE_COLOR:Lerp(Color3.new(1, 1, 1), 0.6)),
        ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
    })
    burst.LightEmission = 0.8
    burst.Texture = "rbxassetid://241594419" -- sparkle
    burst.Lifetime = NumberRange.new(EFFECTS.PARTICLE_BURST.LIFETIME * 0.8, EFFECTS.PARTICLE_BURST.LIFETIME)
    burst.Rate = 0
    burst.Speed = NumberRange.new(EFFECTS.PARTICLE_BURST.VELOCITY_RANGE.Min, EFFECTS.PARTICLE_BURST.VELOCITY_RANGE.Max)
    burst.SpreadAngle = Vector2.new(EFFECTS.PARTICLE_BURST.SPREAD_ANGLE, EFFECTS.PARTICLE_BURST.SPREAD_ANGLE)
    burst.Drag = 3
    burst.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.8),
        NumberSequenceKeypoint.new(0.4, 0.3),
        NumberSequenceKeypoint.new(1, 0),
    })
    burst.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.8, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    burst:Emit(EFFECTS.PARTICLE_BURST.COUNT)

    Debris:AddItem(anchor, 1)
end

-- Precise Fire trigger helper
local function connectFireTrigger(track: AnimationTrack, targetPosition: Vector3?)
    local fired = false
    local disconnects: { RBXScriptConnection } = {}

    local function fireOnce()
        if fired then return end
        fired = true
        task.spawn(executeAttack, nil, targetPosition) -- local launch with stored target
    end

    -- Prefer Animation Events (Markers)
    local ok, markerSignal = pcall(function()
        return track:GetMarkerReachedSignal("Fire")
    end)
    if ok and markerSignal then
        table.insert(disconnects, markerSignal:Connect(fireOnce))
    end

    -- Also support named keyframe "Fire"
    table.insert(disconnects, track.KeyframeReached:Connect(function(name)
        if name == "Fire" then fireOnce() end
    end))

    -- Fallback: halfway if neither fires in time
    task.delay(math.max(0, track.Length * 0.5), function()
        fireOnce()
    end)

    -- Cleanup
    table.insert(disconnects, track.Stopped:Connect(function()
        for _, conn in ipairs(disconnects) do
            conn:Disconnect()
        end
        table.clear(disconnects)
    end))
end

-- Helper function to find and play animations
playCharacterAnimation = function(animName: string, targetPosition: Vector3?): AnimationTrack?
    local character = Player.Character
    if not character then return nil end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end
    
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return nil end
    
    -- Find animation
    local animTag = tostring(Player.UserId) .. "_Animations"
    local animFolder = CollectionService:GetTagged(animTag)[1]
    if not animFolder then return nil end
    
    local anim = animFolder and animFolder:FindFirstChild(animName) :: Animation?
    if not anim then return nil end
    -- Load and play animation
    local track = animator:LoadAnimation(anim)
    track.Priority = ANIM_PRIORITY
    pcall(function() track.Looped = false end)

    -- Hook precise trigger with target position
    connectFireTrigger(track, targetPosition)
    
    track:Play(ANIM_FADE_TIME, 1, 1)
    return track
end

local function createOrbVisuals(orb: BasePart)
    -- Add glowing effect
    local pointLight = Instance.new("PointLight")
    pointLight.Color = PROJECTILE_COLOR
    pointLight.Brightness = MAIN_ORB.GLOW_BRIGHTNESS
    pointLight.Range = MAIN_ORB.GLOW_RANGE
    pointLight.Parent = orb
    
    -- Add sleek trail
    local trailAtt0 = Instance.new("Attachment"); trailAtt0.Name = "Trail0"; trailAtt0.Parent = orb
    local trailAtt1 = Instance.new("Attachment"); trailAtt1.Name = "Trail1"; trailAtt1.Parent = orb
    trailAtt0.Position = Vector3.new(0, 0, -0.35)
    trailAtt1.Position = Vector3.new(0, 0, 0.35)
    local trail = Instance.new("Trail")
    trail.Name = "OrbTrail"
    trail.Attachment0 = trailAtt0
    trail.Attachment1 = trailAtt1
    trail.MinLength = 0
    trail.LightInfluence = 0
    trail.Lifetime = 0.25
    trail.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, PROJECTILE_COLOR),
        ColorSequenceKeypoint.new(0.6, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, PROJECTILE_COLOR),
    })
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.25),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.7, 0.7),
        NumberSequenceKeypoint.new(1, 0),
    })
    trail.Parent = orb

    -- Add particle effect
    local attachment = Instance.new("Attachment")
    attachment.Parent = orb
    
    local particles = Instance.new("ParticleEmitter")
    particles.Parent = attachment
    particles.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, PROJECTILE_COLOR),
        ColorSequenceKeypoint.new(0.5, Color3.new(1, 0.8, 1)), -- Light purple in middle
        ColorSequenceKeypoint.new(1, PROJECTILE_COLOR)
    }
    particles.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(0.5, 0.8),
        NumberSequenceKeypoint.new(1, 0)
    }
    particles.Lifetime = NumberRange.new(0.3, 0.6)
    particles.Rate = EFFECTS.PARTICLE_RATE
    particles.SpreadAngle = Vector2.new(35, 35)
    particles.Speed = NumberRange.new(2, 6)
    particles.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1)
    }
    
    -- Add aura
    local aura = Instance.new("ParticleEmitter")
    aura.Name = "Aura"
    aura.Parent = attachment
    aura.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, PROJECTILE_COLOR),
        ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
    })
    aura.Lifetime = NumberRange.new(0.2, 0.4)
    aura.Rate = 12
    aura.Speed = NumberRange.new(1, 2)
    aura.SpreadAngle = Vector2.new(360, 360)
    aura.EmissionDirection = Enum.NormalId.Front
    aura.Rotation = NumberRange.new(0, 360)
    aura.RotSpeed = NumberRange.new(-80, 80)
    aura.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.25),
        NumberSequenceKeypoint.new(1, 0),
    })
    aura.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })

    -- Orbiting ribbons
    local ribbon0 = Instance.new("Attachment"); ribbon0.Name = "Ribbon0"; ribbon0.Parent = orb
    local ribbon1 = Instance.new("Attachment"); ribbon1.Name = "Ribbon1"; ribbon1.Parent = orb
    local ribbonTrail = Instance.new("Trail")
    ribbonTrail.Name = "RibbonTrail"
    ribbonTrail.Attachment0 = ribbon0
    ribbonTrail.Attachment1 = ribbon1
    ribbonTrail.Lifetime = 0.2
    ribbonTrail.MinLength = 0
    ribbonTrail.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, PROJECTILE_COLOR),
    })
    ribbonTrail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.35),
        NumberSequenceKeypoint.new(1, 1),
    })
    ribbonTrail.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 0),
    })
    ribbonTrail.Parent = orb

    -- Add pulsing effect to the orb
    local pulseConnection: RBXScriptConnection
    local ribbonConnection: RBXScriptConnection
    
    -- Small pulsing satellite orbs circling the main orb
    local satellites: { BasePart } = {}
    local SAT_COUNT = SATELLITES.COUNT
    local SAT_SIZE_BASE = SATELLITES.SIZE_BASE
    local SAT_RADIUS_BASE = SATELLITES.RADIUS_BASE
    for i = 1, SAT_COUNT do
        local sat = Instance.new("Part")
        sat.Name = "OrbSatellite"
        sat.Shape = Enum.PartType.Ball
        sat.Material = Enum.Material.Neon
        sat.Color = PROJECTILE_COLOR
        sat.Size = Vector3.new(SAT_SIZE_BASE, SAT_SIZE_BASE, SAT_SIZE_BASE)
        sat.CanCollide = false
        sat.Anchored = true
        sat.Transparency = 0
        sat.Parent = orb

        local sl = Instance.new("PointLight")
        sl.Color = PROJECTILE_COLOR
        sl.Brightness = SATELLITES.BRIGHTNESS
        sl.Range = 6
        sl.Parent = sat

        table.insert(satellites, sat)
    end
    local startTime = time()
    
    pulseConnection = RunService.Heartbeat:Connect(function()
        local elapsed = time() - startTime
        local pulse = 0.8 + MAIN_ORB.PULSE_INTENSITY * math.sin(elapsed * MAIN_ORB.PULSE_SPEED)
        orb.Size = PROJECTILE_SIZE * pulse
        
        -- Clean up connection when orb is destroyed
        if not orb.Parent then
            pulseConnection:Disconnect()
        end
    end)

    local radius = 0.6
    ribbonConnection = RunService.Heartbeat:Connect(function()
        if not orb.Parent then
            ribbonConnection:Disconnect()
            return
        end
        local t = (time() * SATELLITES.ORBIT_SPEED) % (math.pi * 2)
        ribbon0.Position = Vector3.new(math.cos(t) * radius, math.sin(t * 2) * radius * 0.5, 0)
        ribbon1.Position = Vector3.new(math.cos(t + math.pi) * radius, math.sin((t + math.pi) * 2) * radius * 0.5, 0)

        -- Update satellite orbs to orbit and pulse
        local baseCF = orb.CFrame
        for i, sat in ipairs(satellites) do
            if not sat.Parent then continue end
            local angle = t + ((i - 1) / SAT_COUNT) * math.pi * 2
            local radialPulse = 0.3 * math.sin(t * 2 + i)
            local vertical = 0.4 * math.sin(t * 3 + i * 0.7)
            local r = SAT_RADIUS_BASE + radialPulse
            local offset = Vector3.new(math.cos(angle) * r, vertical, math.sin(angle) * r)
            sat.CFrame = baseCF * CFrame.new(offset)

            local sz = SAT_SIZE_BASE + 0.15 * math.sin(t * SATELLITES.PULSE_SPEED + i)
            sat.Size = Vector3.new(sz, sz, sz)
            local light = sat:FindFirstChildOfClass("PointLight")
            if light then
                light.Brightness = SATELLITES.BRIGHTNESS + 0.8 * math.abs(math.sin(t * 6 + i))
            end
        end
    end)
end

local function createOrb(startPos: Vector3, endPos: Vector3): BasePart
    -- Create the projectile orb
    local orb = Instance.new("Part")
    orb.Name = "OrbProjectile"
    orb.Shape = Enum.PartType.Ball
    orb.Material = Enum.Material.Neon
    orb.Size = PROJECTILE_SIZE
    orb.Color = PROJECTILE_COLOR
    orb.CanCollide = false
    orb.Anchored = true
    orb.CFrame = CFrame.new(startPos)
    orb.Parent = workspace
    
    -- Add transparency for a more ethereal look
    orb.Transparency = 0.1
    
    createOrbVisuals(orb)
    
    return orb
end

local IMPACT_TRAIL_FADE = 0.2

local function setEmittersEnabled(root: Instance, enabled: boolean)
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("ParticleEmitter") then
            d.Enabled = enabled
        elseif d:IsA("Trail") then
            d.Enabled = enabled
        end
    end
end

local function animateOrb(
    orb: BasePart,
    startPos: Vector3,
    endPos: Vector3,
    onImpact: (() -> ())?,
    initialProgress: number?
): RBXScriptConnection
    -- Fixed travel time regardless of distance for consistent feel
    local duration = PROJECTILE_TRAVEL_TIME

    -- Precompute curved path control point for elegant arc
    local delta = endPos - startPos
    local distance = delta.Magnitude
    local dir = if distance > 1e-6 then delta.Unit else Vector3.new(0, 0, -1)
    local up = Vector3.new(0, 1, 0)
    local right = dir:Cross(up)
    if right.Magnitude < 1e-6 then right = dir:Cross(Vector3.new(1, 0, 0)) end
    right = if right.Magnitude > 0 then right.Unit else Vector3.new(1, 0, 0)

    -- Enhanced arc calculation for more dramatic curves
    local arcHeight = math.clamp(distance * 0.4, 1.2, 4)
    local sideOffset = math.clamp(distance * 0.25, 0.3, 1.8)
    local control = (startPos + endPos) * 0.5 + up * arcHeight + right * sideOffset

    local startProgress = math.clamp(initialProgress or 0, 0, 1)
    local startTime = time() - (startProgress * duration)

    local connection: RBXScriptConnection
    local impactFired = false
    local spin = 0

    connection = RunService.Heartbeat:Connect(function(dt)
        local elapsed = time() - startTime
        local t = math.clamp(elapsed / duration, 0, 1)
        
        -- Smoother easing with more dramatic acceleration/deceleration
        local ease = if t < 0.3 then 
                3.33 * t * t 
            elseif t > 0.7 then 
                1 - math.pow(-2 * (t - 1), 3) / 2
            else
                0.3 + (t - 0.3) * 1.25

        if t >= 1 then
            if not impactFired then
                impactFired = true
                orb.CFrame = CFrame.new(endPos)
                if onImpact then
                    task.spawn(onImpact)
                end
                -- Fade out particles quickly, then cleanup
                setEmittersEnabled(orb, false)
                Debris:AddItem(orb, IMPACT_TRAIL_FADE)
            end
            connection:Disconnect()
            return
        end

        -- Enhanced Bezier curve with subtle wobble for organic movement
        local a = (1 - ease)
        local currentPos = startPos * (a * a) + control * (2 * a * ease) + endPos * (ease * ease)
        
        -- Add subtle wobble for more organic feel
        local wobble = Vector3.new(
            0.1 * math.sin(elapsed * 12),
            0.05 * math.sin(elapsed * 8),
            0.08 * math.cos(elapsed * 10)
        ) * (1 - t) -- Wobble decreases as orb approaches target

        currentPos = currentPos + wobble

        -- Enhanced spin with variable speed based on progress
        spin += dt * MAIN_ORB.SPIN_SPEED * (1 + t)
        local lookDirection = (endPos - currentPos).Unit
        orb.CFrame = CFrame.lookAt(currentPos, currentPos + lookDirection) * CFrame.Angles(0, 0, spin)
    end)

    return connection
end

local function getTargetInfo(): (Model?, BasePart?)
    local player = Players.LocalPlayer
    local targetKey = player:GetAttribute("targetKey") :: string
    local target = CollectionService:GetTagged(targetKey)[1]
    
    if not target then 
        warn("No target found")
        return nil, nil
    end

    local character = player.Character
    if not character or not character.PrimaryPart then
        warn("No character or PrimaryPart")
        return nil, nil
    end

    local targetPart = (target :: Model & {PrimaryPart: BasePart}).PrimaryPart
    return character, targetPart
end

executeAttack = function(castTimestamp: number?, targetPosition: Vector3?)
    local character = Player.Character
    if not character or not character.PrimaryPart then 
        warn("No character or PrimaryPart")
        return 
    end

    local endPos: Vector3
    
    -- Use passed target position (from context) if available, otherwise fallback to current target
    if targetPosition then
        endPos = targetPosition + Vector3.new(0, 1, 0) -- Slightly above target
    else
        -- Fallback: query current target (for backwards compatibility)
        local _, targetPart = getTargetInfo()
        if not targetPart then 
            warn("No target found")
            return 
        end
        endPos = targetPart.Position + Vector3.new(0, 1, 0)
    end

    -- Get start position
    local startPos = character.PrimaryPart.Position + Vector3.new(0, 2, 0) -- Slightly above player
    
    -- Create and animate the orb projectile
    local orb = createOrb(startPos, endPos)

    -- Latency compensation: start mid-flight on replicate
    local initialProgress: number? = nil
    if typeof(castTimestamp) == "number" then
        initialProgress = math.clamp((time() - castTimestamp) / PROJECTILE_TRAVEL_TIME, 0, 1)
    end

    animateOrb(orb, startPos, endPos, function()
        -- Epic impact sequence: Brief pause -> Implosion -> Massive explosion
        
        -- Brief pause to build anticipation
        local pauseEffect = Instance.new("Part")
        pauseEffect.Name = "PauseCharge"
        pauseEffect.Anchored = true
        pauseEffect.CanCollide = false
        pauseEffect.Material = Enum.Material.Neon
        pauseEffect.Shape = Enum.PartType.Ball
        pauseEffect.Size = Vector3.new(0.5, 0.5, 0.5)
        pauseEffect.Color = PROJECTILE_COLOR
        pauseEffect.Transparency = 0.3
        pauseEffect.CFrame = CFrame.new(endPos)
        pauseEffect.Parent = workspace
        
        -- Charge-up effect
        local chargeLight = Instance.new("PointLight")
        chargeLight.Color = PROJECTILE_COLOR
        chargeLight.Brightness = 15
        chargeLight.Range = 12
        chargeLight.Parent = pauseEffect
        
        -- Pulse the pause effect
        local chargeTween = TweenService:Create(pauseEffect, 
            TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true), 
            {Size = Vector3.new(1.5, 1.5, 1.5), Transparency = 0.8}
        )
        chargeTween:Play()
        
        task.wait(0.15) -- Brief dramatic pause
        pauseEffect:Destroy()
        
        createImplosion(endPos, function()
            -- After implosion, trigger the massive explosion
            doEffect(character, endPos)
            pulsePostEffects()
            createImpactLight(endPos)
            createShockwave(endPos)
            emitImpactBurst(endPos)
            CameraShakeManager.Explosion(endPos, EFFECTS.CAMERA_SHAKE.MAX_DISTANCE)
        end)
    end, initialProgress)
end

-- Ability Configuration Interface Functions
function Ability.getAbilityInputRequired()
    return Enum.UserInputType.MouseButton2
end

function Ability.getAbilityClassId()
    return ABILITY_CLASS
end

function Ability.getAbilityCategory()
    return "Primary" -- This is a primary attack ability
end

function Ability.getAbilityRange()
    return ATTACK_RANGE
end

function Ability.getAbilityCooldown()
    return COOLDOWN_TIME
end

function Ability.getRequiresTarget()
    return REQUIRES_TARGET
end

return Ability
