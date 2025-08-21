local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
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

function Client.OnReplicate(ctx: Types.SharedAbilityContext, serverData: any?)
    -- Handle replication from other clients (latency compensated)
    local targetPosition = ctx.inputData.target
    task.spawn(executeAttack, ctx and ctx.timestamp, targetPosition)
end

function Client.OnCast(ctx: Types.SharedAbilityContext, serverData: any?)
    -- Local client: play animation, projectile will spawn precisely on "Fire" event/keyframe
    -- Store the target position from the context for use during animation
    local targetPosition = ctx.inputData.target
    
    -- Play cast sound effect
    playSoundEffect(Config.SOUND_CAST_ID, Config.SOUND_VOLUME)
    
    task.spawn(playCharacterAnimation,Config.ANIMATION_NAME, targetPosition)
end

function Client.OnCancel(ctx: Types.SharedAbilityContext, reason: string?)
    -- Implementation if needed
end

-- Required interface functions
function Client.GetSharedModule()
    return require(script.Parent.Shared)
end

-- Ability configuration interface functions for backward compatibility
function Client.getAbilityInputRequired()
    return Enum.UserInputType.MouseButton1
end

function Client.getAbilityClassId()
    return Config.ABILITY_CLASS
end

function Client.getAbilityCategory()
    return Config.ABILITY_CATEGORY
end

function Client.getAbilityRange()
    return Config.ATTACK_RANGE
end

function Client.getAbilityCooldown()
    return Config.COOLDOWN_TIME
end

function Client.getRequiresTarget()
    return Config.REQUIRES_TARGET
end

local function doCastEffect(castEffectRequest : {
    character: Model,
    targetPosition: Vector3?,
    startPos : Vector3,
    endPos : Vector3})
    if not castEffectRequest.character then
        warn("Invalid character for effect")
        return
    end

    -- Wait for Effects folder to replicate from server (with timeout)    
    if not effectsFolder then
        error("No Effects folder in ability!")
        return
    end

    local effect = effectsFolder.CastHeal
    if not effect then
        error("No CastHeal effect found in Effects folder")
        return
    end
    -- Create effect at target position if available, otherwise at character position
    local effectPosition = castEffectRequest.targetPosition or (castEffectRequest.character.PrimaryPart and castEffectRequest.character.PrimaryPart.Position)
    if not effectPosition then
        warn("No valid position for effect")
        return
    end

    local effectClone = effect:Clone()
    effectClone.CFrame = CFrame.lookAt(castEffectRequest.startPos, castEffectRequest.endPos)
    effectClone.Anchored = true
    effectClone.CanCollide = false
    effectClone.Parent = game.Workspace

    local emiters = effectClone:GetDescendants() 
    task.spawn(function()
        for _, emmiter : ParticleEmitter in emiters do 
            if emmiter:IsA("ParticleEmitter") then
                emmiter:Emit(3)
            end
        end
    end)

    -- Clean up both the effect and the anchor part
    Debris:AddItem(effectClone, Config.EFFECT_CLEANUP_TIME)
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

-- Helper function to find and play animations (updated to use "Fire" timing)
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
    local anim = animFolder and animFolder:FindFirstChild(animName) :: Animation?
    if not anim then return nil end
    
    -- Load and play animation
    local track = animator:LoadAnimation(anim)
    track.Priority = Config.ANIM_PRIORITY
    pcall(function() track.Looped = false end)

    -- Hook precise trigger with target position
    connectFireTrigger(track, targetPosition)
    
    track:Play(Config.ANIM_FADE_TIME, 1, 1)
    return track
end

local function createProjectileVisuals(projectile: BasePart)
    -- Add healing glow effect (more gentle than damage spells)
    local pointLight = Instance.new("PointLight")
    pointLight.Color = Config.PROJECTILE_COLOR
    pointLight.Brightness = Config.LIGHT_BRIGHTNESS
    pointLight.Range = Config.LIGHT_RANGE
    pointLight.Parent = projectile
    
    -- Add healing particle effect (more sparkly/gentle)
    local attachment = Instance.new("Attachment")
    attachment.Parent = projectile
    
    local particles = Instance.new("ParticleEmitter")
    particles.Parent = attachment
    particles.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Config.PROJECTILE_COLOR),
        ColorSequenceKeypoint.new(0.3, Color3.new(0.8, 1, 0.9)), -- Light cyan healing color
        ColorSequenceKeypoint.new(0.7, Color3.new(1, 1, 1)), -- White sparkle in middle
        ColorSequenceKeypoint.new(1, Config.PROJECTILE_COLOR)
    }
    particles.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.5, 0.8),
        NumberSequenceKeypoint.new(1, 0)
    }
    particles.Lifetime = NumberRange.new(0.3, 0.6) -- Longer lifetime for gentler effect
    particles.Rate = Config.PARTICLE_RATE
    particles.SpreadAngle = Vector2.new(45, 45) -- Wider spread for healing sparkles
    particles.Speed = NumberRange.new(2, 6) -- Slower, more gentle movement
    particles.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.8, 0.5),
        NumberSequenceKeypoint.new(1, 1)
    }
    
    -- Add secondary healing trail effect
    local healingTrail = Instance.new("Trail")
    healingTrail.Attachment0 = attachment
    
    local attachment2 = Instance.new("Attachment")
    attachment2.Parent = projectile
    attachment2.Position = Vector3.new(0, 0, -1)
    healingTrail.Attachment1 = attachment2
    
    healingTrail.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Config.PROJECTILE_COLOR),
        ColorSequenceKeypoint.new(1, Color3.new(0.8, 1, 0.9))
    }
    healingTrail.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 0.9)
    }
    healingTrail.Lifetime = 0.5
    healingTrail.MinLength = 0.1
    healingTrail.Parent = projectile
end

local function createSpiralProjectile(startPos: Vector3, endPos: Vector3): BasePart
    local projectile = effectsFolder.HealSpellTrail:Clone()
    projectile.CFrame = CFrame.lookAt(startPos, endPos)
    projectile.CanCollide = false
    projectile.Anchored = true
    projectile.Parent = workspace
    
    createProjectileVisuals(projectile)
    
    return projectile
end

local function calculateSpiralPosition(startPos: Vector3, direction: Vector3, progress: number, distance: number): Vector3
    -- Calculate base position along the path
    local basePos = startPos + direction * distance * progress
    
    -- Calculate spiral offset with smoother easing
    local spiralAngle = progress * math.pi * 2 * Config.SPIRAL_FREQUENCY
    local spiralRadius = Config.SPIRAL_RADIUS * (1 - progress * progress) -- Quadratic easing for smoother convergence

    -- Create perpendicular vectors for spiral
    local right = direction:Cross(Vector3.new(0, 1, 0))
    if right.Magnitude < 1e-6 then
        right = direction:Cross(Vector3.new(1, 0, 0))
    end
    right = right.Unit
    local up = direction:Cross(right).Unit
    
    -- Apply spiral offset with slight vertical bias for more natural movement
    local spiralOffset = right * math.cos(spiralAngle) * spiralRadius + up * math.sin(spiralAngle) * spiralRadius * 0.7
    return basePos + spiralOffset
end

local IMPACT_TRAIL_FADE = 0.15

local function setEmittersEnabled(root: Instance, enabled: boolean)
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("ParticleEmitter") then
            d.Enabled = enabled
        elseif d:IsA("Trail") then
            d.Enabled = enabled
        end
    end
end

local function animateSpiralProjectile(
    projectile: BasePart,
    startPos: Vector3,
    endPos: Vector3,
    onImpact: (() -> ())?,
    initialProgress: number?
): RBXScriptConnection
    local direction = (endPos - startPos).Unit
    local distance = (endPos - startPos).Magnitude
    local duration = distance / Config.PROJECTILE_SPEED

    local startProgress = math.clamp(initialProgress or 0, 0, 1)
    local startTime = time() - (startProgress * duration)

    local connection: RBXScriptConnection
    local impactFired = false

    connection = RunService.Heartbeat:Connect(function(dt)
        local elapsed = time() - startTime
        local progress = math.clamp(elapsed / duration, 0, 1)

        if progress >= 1 then
            if not impactFired then
                impactFired = true
                projectile.CFrame = CFrame.new(endPos)
                if onImpact then
                    task.spawn(onImpact)
                end
                -- Fade out trails/particles quickly, then cleanup
                setEmittersEnabled(projectile, false)
                Debris:AddItem(projectile, IMPACT_TRAIL_FADE)
            end
            connection:Disconnect()
            return
        end

        local finalPos = calculateSpiralPosition(startPos, direction, progress, distance)

        -- Look towards next position for smoother orientation
        local step = math.max(dt, 1/120) -- small forward step
        local nextProgress = math.min(progress + (step / duration), 1)
        local nextPos = calculateSpiralPosition(startPos, direction, nextProgress, distance)
        local delta = nextPos - finalPos
        local lookDirection = delta.Magnitude > 1e-6 and delta.Unit or direction

        projectile.CFrame = CFrame.lookAt(finalPos, finalPos + lookDirection)
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
    local startPos = (character["Wand.."].Part.CFrame * CFrame.new(0, 2, 0)).Position -- Slightly above player

    -- Create and animate the spiral projectile
    local projectile = createSpiralProjectile(startPos, endPos)
    doCastEffect({
        character = character,
        targetPosition = endPos,
        startPos = startPos,
        endPos = endPos
    })

    -- Latency compensation: start mid-flight on replicate
    local initialProgress: number? = nil
    if typeof(castTimestamp) == "number" then
        local distance = (endPos - startPos).Magnitude
        local duration = distance / Config.PROJECTILE_SPEED
        initialProgress = math.clamp((time() - castTimestamp) / duration, 0, 1)
    end

    animateSpiralProjectile(projectile, startPos, endPos, function()
        -- Trigger healing impact effect exactly on arrival with enhanced feedback
        local impactEffect = effectsFolder.HealHit:Clone()
        impactEffect.Position = endPos
        impactEffect.CanCollide = false
        impactEffect.Anchored = true
        impactEffect.Parent = workspace
        
        -- Enhanced healing particles
        for _, particle in ipairs(impactEffect:GetDescendants()) do
            if particle:IsA("ParticleEmitter") then
                particle:Emit(8) -- More particles for healing impact
            end
        end
        
        -- Play healing impact sound
        playSoundEffect(Config.SOUND_IMPACT_ID, Config.SOUND_VOLUME * 0.8)
        
        -- Create healing indicator (floating +HP text)
        local healingIndicator = Instance.new("BillboardGui")
        healingIndicator.Name = "HealingIndicator"
        healingIndicator.Size = UDim2.new(0, 100, 0, 50)
        healingIndicator.StudsOffset = Vector3.new(0, 3, 0)
        healingIndicator.Parent = workspace
        
        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, 0, 1, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.Text = `+{Config.HEAL_AMOUNT} HP`
        textLabel.TextColor3 = Color3.new(0, 1, 0.3)
        textLabel.TextScaled = true
        textLabel.Font = Enum.Font.SourceSansBold
        textLabel.Parent = healingIndicator
        
        -- Animate the healing indicator
        local tween = game:GetService("TweenService"):Create(healingIndicator, 
            TweenInfo.new(2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            {StudsOffset = Vector3.new(0, 6, 0)}
        )
        tween:Play()
        
        local fadeTween = game:GetService("TweenService"):Create(textLabel, 
            TweenInfo.new(2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            {TextTransparency = 1}
        )
        fadeTween:Play()
        
        -- Cleanup
        task.delay(2.5, function()
            healingIndicator:Destroy()
        end)
        
        -- Add gentle camera shake for healing feedback (much lighter than damage)
        CameraShakeManager.Bump(endPos, 15)
    end, initialProgress)
end


return Client