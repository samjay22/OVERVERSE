--!strict
-- RemM1 Client Module - Primary Category Ability
-- Rewritten to work with category-based execution system

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local CameraShakeManager = require(ReplicatedStorage.Modules.Utility.CameraShakeManager)
local Types: {  } = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local Config = require(script.Parent.Config)

local Player = Players.LocalPlayer

type AbilityAssets = typeof(script.Parent.Assets)
local effectsFolder : AbilityAssets = script.Parent.Assets

local Client = {}

-- Audio system
local function playSoundEffect(soundId: string, volume: number?)
    local sound = Instance.new("Sound")
    sound.SoundId = soundId
    sound.Volume = volume or Config.SOUND_VOLUME
    sound.Parent = SoundService
    sound:Play()
    
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
end

-- Helper function to get character and humanoid
local function getCharacterData()
    local character = Player.Character
    if not character then return nil, nil end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return character, nil end
    
    return character, humanoid
end

-- Execute the healing projectile attack
local function executeAttack(timestamp: number?, targetPosition: Vector3?)
    if not targetPosition then return end
    
    local character, humanoid = getCharacterData()
    if not character or not humanoid then return end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not humanoidRootPart then return end
    
    -- Create healing projectile with enhanced visuals
    local projectile = effectsFolder.HealSpellTrail:Clone()
    projectile.CanCollide = false
    projectile.Anchored = true
    projectile.Size = Config.PROJECTILE_SIZE
    projectile.Color = Config.PROJECTILE_COLOR
    projectile.Material = Enum.Material.ForceField
    
    -- Enhanced glowing effect with color animation
    local pointLight = Instance.new("PointLight")
    pointLight.Brightness = Config.LIGHT_BRIGHTNESS
    pointLight.Range = Config.LIGHT_RANGE
    pointLight.Color = Config.PROJECTILE_COLOR
    pointLight.Parent = projectile
    
    -- Add bloom effect with SelectionBox
    local selectionBox = Instance.new("SelectionBox")
    selectionBox.Adornee = projectile
    selectionBox.Color3 = Config.PROJECTILE_COLOR
    selectionBox.LineThickness = 0.2
    selectionBox.Transparency = 0.3
    selectionBox.Parent = projectile
    
    -- Add particle effect attachment
    local attachment = Instance.new("Attachment")
    attachment.Parent = projectile
    
    -- Enhanced particle effects
    local healParticles = effectsFolder:FindFirstChild("HealParticles")
    if healParticles and healParticles:IsA("ParticleEmitter") then
        local particleClone = healParticles:Clone()
        particleClone.Parent = attachment
        particleClone.Rate = Config.PARTICLE_RATE
        particleClone.Color = ColorSequence.new(Config.PROJECTILE_COLOR)
        particleClone:Emit(30)
    else
        -- Create default healing particles if not found
        local defaultParticles = Instance.new("ParticleEmitter")
        defaultParticles.Parent = attachment
        defaultParticles.Color = ColorSequence.new(Config.PROJECTILE_COLOR)
        defaultParticles.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(0.5, 0.8),
            NumberSequenceKeypoint.new(1, 0.1)
        }
        defaultParticles.Lifetime = NumberRange.new(0.3, 0.8)
        defaultParticles.Rate = Config.PARTICLE_RATE
        defaultParticles.Speed = NumberRange.new(2, 8)
        defaultParticles.SpreadAngle = Vector2.new(45, 45)
        defaultParticles.VelocityInheritance = 0.2
        defaultParticles:Emit(25)
    end
    
    -- Add trail effect for better visual tracking
    local trailAttachment1 = Instance.new("Attachment")
    trailAttachment1.Position = Vector3.new(0, 0, -1)
    trailAttachment1.Parent = projectile
    
    local trailAttachment2 = Instance.new("Attachment")
    trailAttachment2.Position = Vector3.new(0, 0, 1)
    trailAttachment2.Parent = projectile
    
    local trail = Instance.new("Trail")
    trail.Attachment0 = trailAttachment1
    trail.Attachment1 = trailAttachment2
    trail.Color = ColorSequence.new(Config.PROJECTILE_COLOR)
    trail.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1)
    }
    trail.Lifetime = 0.8
    trail.MinLength = 0.1
    trail.MaxLength = 20
    trail.WidthScale = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.5, 0.8),
        NumberSequenceKeypoint.new(1, 0)
    }
    trail.Parent = projectile
    
    projectile.Parent = workspace
    
    -- Calculate trajectory with spiral motion
    local startPosition = humanoidRootPart.Position + humanoidRootPart.CFrame.LookVector * 3
    local endPosition = targetPosition
    local direction = (endPosition - startPosition).Unit
    local distance = (endPosition - startPosition).Magnitude
    
    -- Enhanced projectile animation with pulsing light and rotation
    local startTime = tick()
    local totalTime = distance / Config.PROJECTILE_SPEED
    
    -- Add rotation animation to projectile for visual appeal
    local rotationSpeed = 360 -- degrees per second
    
    -- Animate light pulsing during flight
    local lightPulse = game:GetService("TweenService"):Create(
        pointLight,
        TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Brightness = Config.LIGHT_BRIGHTNESS * 1.5}
    )
    lightPulse:Play()
    
    local connection
    connection = RunService.Heartbeat:Connect(function()
        local elapsed = tick() - startTime
        local progress = elapsed / totalTime
        
        if progress >= 1 then
            progress = 1
            connection:Disconnect()
            lightPulse:Cancel()
        end
        
        -- Linear movement with enhanced spiral rotation
        local currentPosition = startPosition:Lerp(endPosition, progress)
        
        -- Enhanced spiral motion with varying radius
        local spiralAngle = progress * Config.SPIRAL_FREQUENCY * math.pi * 2
        local spiralIntensity = math.sin(progress * math.pi) -- Peaks at midpoint
        local spiralOffset = Vector3.new(
            math.cos(spiralAngle) * Config.SPIRAL_RADIUS * spiralIntensity,
            math.sin(spiralAngle) * Config.SPIRAL_RADIUS * spiralIntensity,
            0
        )
        
        -- Apply spiral in world space
        local rightVector = direction:Cross(Vector3.new(0, 1, 0)).Unit
        local upVector = direction:Cross(rightVector).Unit
        local spiralWorldOffset = rightVector * spiralOffset.X + upVector * spiralOffset.Y
        
        -- Set position and rotation
        projectile.Position = currentPosition + spiralWorldOffset
        projectile.Rotation = Vector3.new(
            elapsed * rotationSpeed * 0.5,
            elapsed * rotationSpeed,
            elapsed * rotationSpeed * 0.3
        )
        
        -- Scale projectile slightly during flight for better visual
        local scale = 1 + math.sin(progress * math.pi) * 0.3
        projectile.Size = Config.PROJECTILE_SIZE * scale
        
         for _, emitter in projectile:GetDescendants() do
                if emitter:IsA("ParticleEmitter") then
                    emitter.Color = ColorSequence.new(Config.PROJECTILE_COLOR)
                    emitter:Emit(5)
                end
            end
            
        -- On impact
        if progress >= 1 then
            -- Play impact sound with slight pitch variation
            local impactSound = Instance.new("Sound")
            impactSound.SoundId = Config.SOUND_IMPACT_ID
            impactSound.Volume = Config.SOUND_VOLUME * 0.9
            impactSound.Pitch = 0.9 + math.random() * 0.2 -- Slight pitch variation
            impactSound.Parent = workspace
            impactSound:Play()
            impactSound.Ended:Connect(function() impactSound:Destroy() end)
            
            -- Create enhanced healing impact effect
            local healEffect = effectsFolder.HealHit:Clone()
            healEffect.CanCollide = false
            healEffect.Anchored = true
            healEffect.Position = projectile.Position
            healEffect.Size = Vector3.new(0.1, 0.1, 0.1)
            healEffect.Color = Config.PROJECTILE_COLOR
            healEffect.Material = Enum.Material.Neon
            healEffect.Parent = workspace

            for _, emitter in healEffect:GetDescendants() do
                if emitter:IsA("ParticleEmitter") then
                    emitter.Color = ColorSequence.new(Config.PROJECTILE_COLOR)
                    emitter:Emit(5)
                end
            end

            -- Multiple layers of impact particles
            local impactAttachment = Instance.new("Attachment")
            impactAttachment.Parent = healEffect
            
            -- Create burst particles
            local burstParticles = Instance.new("ParticleEmitter")
            burstParticles.Parent = impactAttachment
            burstParticles.Color = ColorSequence.new(Config.PROJECTILE_COLOR)
            burstParticles.Size = NumberSequence.new{
                NumberSequenceKeypoint.new(0, 0.5),
                NumberSequenceKeypoint.new(0.2, 1.2),
                NumberSequenceKeypoint.new(1, 0)
            }
            burstParticles.Lifetime = NumberRange.new(0.8, 1.5)
            burstParticles.Speed = NumberRange.new(8, 15)
            burstParticles.SpreadAngle = Vector2.new(60, 60)
            burstParticles.Drag = 3
            burstParticles.EmissionDirection = Enum.NormalId.Top
            burstParticles:Emit(50)
            
            -- Create sparkle particles
            local sparkleParticles = Instance.new("ParticleEmitter")
            sparkleParticles.Parent = impactAttachment
            sparkleParticles.Color = ColorSequence.new(Config.PROJECTILE_COLOR)
            sparkleParticles.Size = NumberSequence.new{
                NumberSequenceKeypoint.new(0, 0.1),
                NumberSequenceKeypoint.new(0.5, 0.3),
                NumberSequenceKeypoint.new(1, 0.1)
            }
            sparkleParticles.Lifetime = NumberRange.new(1.0, 2.0)
            sparkleParticles.Speed = NumberRange.new(2, 6)
            sparkleParticles.SpreadAngle = Vector2.new(180, 180)
            sparkleParticles.Acceleration = Vector3.new(0, -10, 0)
            sparkleParticles:Emit(30)

            -- Enhanced healing light with animated intensity
            local healLight = Instance.new("PointLight")
            healLight.Brightness = Config.LIGHT_BRIGHTNESS * 3
            healLight.Range = Config.LIGHT_RANGE * 2
            healLight.Color = Config.PROJECTILE_COLOR
            healLight.Parent = healEffect
            
            -- Create expanding shockwave effect
            local shockwave = Instance.new("Part")
            shockwave.Name = "HealShockwave"
            shockwave.Size = Vector3.new(0.1, 0.1, 0.1)
            shockwave.Position = projectile.Position
            shockwave.Anchored = true
            shockwave.CanCollide = false
            shockwave.Shape = Enum.PartType.Ball
            shockwave.Material = Enum.Material.ForceField
            shockwave.Color = Config.PROJECTILE_COLOR
            shockwave.Transparency = 0.7
            shockwave.Parent = workspace
            
            -- Animate impact effects with staggered timing
            local TweenService = game:GetService("TweenService")
            
            -- Main heal effect expansion
            local healTween = TweenService:Create(
                healEffect,
                TweenInfo.new(Config.EFFECT_CLEANUP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {
                    Size = Vector3.new(6, 6, 6),
                    Transparency = 1
                }
            )
            
            -- Shockwave expansion
            local shockwaveTween = TweenService:Create(
                shockwave,
                TweenInfo.new(Config.EFFECT_CLEANUP_TIME * 1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {
                    Size = Vector3.new(12, 12, 12),
                    Transparency = 1
                }
            )
            
            -- Light fade animation
            local lightTween = TweenService:Create(
                healLight,
                TweenInfo.new(Config.EFFECT_CLEANUP_TIME * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {
                    Brightness = 0,
                    Range = 0
                }
            )
            
            -- Play all animations
            healTween:Play()
            shockwaveTween:Play()
            lightTween:Play()
            
            -- Clean up with proper timing
            Debris:AddItem(healEffect, Config.EFFECT_CLEANUP_TIME)
            Debris:AddItem(shockwave, Config.EFFECT_CLEANUP_TIME * 1.2)
            Debris:AddItem(projectile, 0.1)
        end
    end)
    
    -- Safety cleanup
    Debris:AddItem(projectile, totalTime + .5)
end

-- Play character animation with improved timing
local function playCharacterAnimation(animationName: string, targetPosition: Vector3?)
    local character, humanoid = getCharacterData()
    if not character or not humanoid then return end
    
    -- Load animation
    local animationsFolder = character:FindFirstChild("Animations")
    local animationObject = animationsFolder and animationsFolder:FindFirstChild(animationName)
    
    if animationObject and animationObject:IsA("Animation") then
        local animationTrack = humanoid:LoadAnimation(animationObject)
        animationTrack.Priority = Config.ANIM_PRIORITY
        animationTrack.Looped = false

        -- Play animation
        animationTrack:Play(Config.ANIM_FADE_TIME)
        
        -- Fire projectile on animation event or midway through animation
        local fireTime = animationTrack.Length * 0.35 -- Fire at40% through animation
        task.delay(fireTime, function()
            local wand = character:FindFirstChild("Wand..")
            if not wand or not wand:FindFirstChild("Part") then 
                warn("Wand not found for player:", Players.LocalPlayer.Name)
                return 
            end

            local startPos = wand.Part.Position
            
            -- Create the projectile
            local projectile = effectsFolder.CastHeal:Clone()
            projectile.CanCollide = false
            projectile.Anchored = true
            projectile.CFrame = CFrame.lookAt(startPos, targetPosition :: Vector3)
            projectile:SetAttribute("CasterId", Players.LocalPlayer.UserId)
            projectile.Parent = workspace
            task.spawn(function()
                for _, emitter in projectile:GetDescendants() do
                    if emitter:IsA("ParticleEmitter") then
                        emitter:Emit(5)
                    end
                end
            end)

            CameraShakeManager.Explosion(startPos, 15, 1)

            Debris:AddItem(projectile, .25)
            executeAttack(tick(), targetPosition)
        end)

        -- Clean up animation track
        animationTrack.Ended:Connect(function()
            animationTrack:Destroy()
        end)
    end
end

-- Enhanced camera shake effect for better feedback
local function applyCameraShake(intensity: number?)
    local shakeIntensity = intensity or 0.8
    local character = Player.Character
    if not character then return end
    
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    -- Simple camera shake implementation
    task.spawn(function()
        local originalCFrame = camera.CFrame
        local shakeTime = 0.3
        local startTime = tick()
        
        while tick() - startTime < shakeTime do
            local elapsed = tick() - startTime
            local progress = elapsed / shakeTime
            local fade = 1 - progress
            
            -- Generate random shake values
            local shakeX = (math.random() - 0.5) * shakeIntensity * fade
            local shakeY = (math.random() - 0.5) * shakeIntensity * fade
            local shakeZ = (math.random() - 0.5) * shakeIntensity * fade
            
            -- Apply shake to camera
            local shakeOffset = Vector3.new(shakeX, shakeY, shakeZ)
            camera.CFrame = camera.CFrame + shakeOffset
            
            game:GetService("RunService").Heartbeat:Wait()
        end
    end)
end

-- Main execution function called by CategoryHandler
function Client.Execute(context: Types.SharedAbilityContext)
    -- Call the OnCast function for backward compatibility
    Client.OnCast(context, nil)
    
    return {
        success = true,
        message = "RemM1 executed"
    }
end

-- Validation function
function Client.Validate(context: Types.SharedAbilityContext): Types.ValidationResult
    local character = Player.Character
    if not character then
        return {
            success = false,
            reason = "No character"
        }
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return {
            success = false,
            reason = "Character is dead"
        }
    end
    
    return {
        success = true
    }
end

-- Primary ability execution - called by CategoryHandler for Primary abilities
function Client.OnCast(ctx: Types.SharedAbilityContext, serverData: any?)
    -- Local client: play animation, projectile will spawn precisely during animation
    local targetPosition = ctx.inputData.target
    
    -- Enhanced cast sound effect with pitch variation
    local castSound = Instance.new("Sound")
    castSound.SoundId = Config.SOUND_CAST_ID
    castSound.Volume = Config.SOUND_VOLUME
    castSound.Pitch = 0.95 + math.random() * 0.1 -- Slight pitch variation
    castSound.Parent = workspace
    castSound:Play()
    castSound.Ended:Connect(function() castSound:Destroy() end)
    
    -- Create casting circle effect at player position
    local character = Player.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        local humanoidRootPart = character.HumanoidRootPart
        
        -- Create casting circle
        local castingCircle = Instance.new("Part")
        castingCircle.Name = "CastingCircle"
        castingCircle.Size = Vector3.new(0.1, 0.1, 6)
        castingCircle.Shape = Enum.PartType.Cylinder
        castingCircle.Material = Enum.Material.Neon
        castingCircle.Color = Config.PROJECTILE_COLOR
        castingCircle.Anchored = true
        castingCircle.CanCollide = false
        castingCircle.Transparency = 0.3
        castingCircle.CFrame = CFrame.new(humanoidRootPart.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
        castingCircle.Parent = workspace
        
        -- Add glow to casting circle
        local circleLight = Instance.new("PointLight")
        circleLight.Brightness = Config.LIGHT_BRIGHTNESS * 0.5
        circleLight.Range = Config.LIGHT_RANGE
        circleLight.Color = Config.PROJECTILE_COLOR
        circleLight.Parent = castingCircle
        
        -- Animate casting circle
        local TweenService = game:GetService("TweenService")
        local expandTween = TweenService:Create(
            castingCircle,
            TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
            {
                Size = Vector3.new(0.1, 0.1, 8),
                Transparency = 0.8
            }
        )
        
        local fadeOutTween = TweenService:Create(
            castingCircle,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Transparency = 1}
        )
        
        expandTween:Play()
        expandTween.Completed:Connect(function()
            fadeOutTween:Play()
            fadeOutTween.Completed:Connect(function()
                castingCircle:Destroy()
            end)
        end)
    end
    
    -- Execute the ability
    task.spawn(playCharacterAnimation, Config.ANIMATION_NAME, targetPosition)
end

-- Replication handler - called when other clients use this ability
function Client.OnReplicate(ctx: Types.SharedAbilityContext, serverData: any?)
    -- Handle replication from other clients (latency compensated)
    local targetPosition = ctx.inputData.target
    if targetPosition then
        task.spawn(executeAttack, ctx and ctx.timestamp, targetPosition)
    end
end

-- Cancellation handler - called when ability is cancelled
function Client.OnCancel(ctx: Types.SharedAbilityContext, reason: string?)
    -- Stop any ongoing effects if needed
    -- For RemM1, typically no cancellation needed as it's instant
    warn("RemM1 cancelled:", reason or "Unknown reason")
end

-- Shared module accessor - required by CategoryHandler
function Client.GetSharedModule()
    local sharedMod = require(script.Parent.Shared)
    
    sharedMod.GetAssets = function()
        return script.Parent.Assets
    end
    
    sharedMod.GetConfig = function()
        return Config
    end
    
    return sharedMod
end

-- Category getter - used by CategoryHandler to route to appropriate method
function Client.getAbilityCategory()
    return Config.ABILITY_CATEGORY
end

return Client
