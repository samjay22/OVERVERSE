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
    
    -- Create healing projectile with spiral movement
    local projectile = Instance.new("Part")
    projectile.Name = "RemM1_HealProjectile"
    projectile.Size = Config.PROJECTILE_SIZE
    projectile.Shape = Enum.PartType.Ball
    projectile.Material = Enum.Material.ForceField
    projectile.Color = Config.PROJECTILE_COLOR
    projectile.CanCollide = false
    projectile.Anchored = true
    
    -- Add glowing effect
    local pointLight = Instance.new("PointLight")
    pointLight.Brightness = Config.LIGHT_BRIGHTNESS
    pointLight.Range = Config.LIGHT_RANGE
    pointLight.Color = Config.PROJECTILE_COLOR
    pointLight.Parent = projectile
    
    -- Add particle effect
    local attachment = Instance.new("Attachment")
    attachment.Parent = projectile
    
    -- Create healing particles effect if available in assets
    local healParticles = effectsFolder:FindFirstChild("HealParticles")
    if healParticles and healParticles:IsA("ParticleEmitter") then
        local particleClone = healParticles:Clone()
        particleClone.Parent = attachment
        particleClone.Rate = Config.PARTICLE_RATE
        particleClone:Emit(20)
    end
    
    projectile.Parent = workspace
    
    -- Calculate trajectory with spiral motion
    local startPosition = humanoidRootPart.Position + humanoidRootPart.CFrame.LookVector * 3
    local endPosition = targetPosition
    local direction = (endPosition - startPosition).Unit
    local distance = (endPosition - startPosition).Magnitude
    
    -- Animate projectile with spiral movement
    local startTime = tick()
    local totalTime = distance / Config.PROJECTILE_SPEED
    
    local connection
    connection = RunService.Heartbeat:Connect(function()
        local elapsed = tick() - startTime
        local progress = elapsed / totalTime
        
        if progress >= 1 then
            progress = 1
            connection:Disconnect()
        end
        
        -- Linear movement with spiral rotation
        local currentPosition = startPosition:Lerp(endPosition, progress)
        
        -- Add spiral motion
        local spiralAngle = progress * Config.SPIRAL_FREQUENCY * math.pi * 2
        local spiralOffset = Vector3.new(
            math.cos(spiralAngle) * Config.SPIRAL_RADIUS * (1 - progress),
            math.sin(spiralAngle) * Config.SPIRAL_RADIUS * (1 - progress),
            0
        )
        
        -- Apply spiral in world space
        local rightVector = direction:Cross(Vector3.new(0, 1, 0)).Unit
        local upVector = direction:Cross(rightVector).Unit
        local spiralWorldOffset = rightVector * spiralOffset.X + upVector * spiralOffset.Y
        
        projectile.Position = currentPosition + spiralWorldOffset
        
        -- On impact
        if progress >= 1 then
            -- Play impact sound
            playSoundEffect(Config.SOUND_IMPACT_ID, Config.SOUND_VOLUME * 0.8)
            
            -- Create impact effect
            local impactEffect = Instance.new("Explosion")
            impactEffect.Position = projectile.Position
            impactEffect.BlastRadius = 0
            impactEffect.BlastPressure = 0
            impactEffect.Visible = false
            impactEffect.Parent = workspace
            
            -- Enhanced healing visual effect
            local healEffect = Instance.new("Part")
            healEffect.Name = "HealEffect"
            healEffect.Size = Vector3.new(4, 4, 4)
            healEffect.Shape = Enum.PartType.Ball
            healEffect.Material = Enum.Material.ForceField
            healEffect.Color = Config.PROJECTILE_COLOR
            healEffect.CanCollide = false
            healEffect.Anchored = true
            healEffect.Position = projectile.Position
            healEffect.Parent = workspace
            
            -- Healing effect light
            local healLight = pointLight:Clone()
            healLight.Brightness = Config.LIGHT_BRIGHTNESS * 2
            healLight.Range = Config.LIGHT_RANGE * 1.5
            healLight.Parent = healEffect
            
            -- Animate healing effect
            local info = TweenInfo.new(Config.EFFECT_CLEANUP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            local tween = game:GetService("TweenService"):Create(healEffect, info, {
                Size = Vector3.new(8, 8, 8),
                Transparency = 1
            })
            tween:Play()
            
            -- Clean up
            Debris:AddItem(healEffect, Config.EFFECT_CLEANUP_TIME)
            Debris:AddItem(projectile, 0.1)
        end
    end)
    
    -- Safety cleanup
    Debris:AddItem(projectile, totalTime + 1)
end

-- Play character animation with improved timing
local function playCharacterAnimation(animationName: string, targetPosition: Vector3?)
    local character, humanoid = getCharacterData()
    if not character or not humanoid then return end
    
    -- Load animation
    local animationsFolder = effectsFolder:FindFirstChild("Animations")
    local animationObject = animationsFolder and animationsFolder:FindFirstChild(animationName)
    
    if animationObject and animationObject:IsA("Animation") then
        local animationTrack = humanoid:LoadAnimation(animationObject)
        animationTrack.Priority = Config.ANIM_PRIORITY
        
        -- Play animation
        animationTrack:Play(Config.ANIM_FADE_TIME)
        
        -- Fire projectile on animation event or midway through animation
        local fireTime = animationTrack.Length * 0.4 -- Fire at 40% through animation
        
        task.wait(fireTime)
        executeAttack(tick(), targetPosition)
        
        -- Clean up animation track
        animationTrack.Ended:Connect(function()
            animationTrack:Destroy()
        end)
    else
        -- No animation available, fire immediately
        executeAttack(tick(), targetPosition)
    end
end

-- Camera shake effect for better feedback
local function applyCameraShake()
    -- Camera shake implementation will be handled by the system
    -- Placeholder for now to avoid type errors
    if CameraShakeManager then
        -- CameraShakeManager:ShakeOnce(2, 10, 0.1, 0.2)
    end
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
    
    -- Play cast sound effect
    playSoundEffect(Config.SOUND_CAST_ID, Config.SOUND_VOLUME)
    
    -- Apply camera shake for feedback
    applyCameraShake()
    
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
