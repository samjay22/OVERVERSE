--!strict
-- Client Ability: RemM1 - Ranged attack with spiral projectile (improved timing)

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

local Player: Player = Players.LocalPlayer

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

-- Ability Configuration
local ABILITY_CLASS = "Rem"
local ANIMATION_NAME = "M1"
local COOLDOWN_TIME = 1.6
local ATTACK_RANGE = 50
local REQUIRES_TARGET = true

-- Animation Constants
local ANIM_FADE_TIME = 0.05
local ANIM_PRIORITY = Enum.AnimationPriority.Action

-- Projectile Constants
local PROJECTILE_SPEED = 80 -- Speed in studs per second (consistent regardless of distance)
local SPIRAL_RADIUS = 4
local SPIRAL_FREQUENCY = 6
local PROJECTILE_SIZE = Vector3.new(0.3, 0.3, 0.3) -- Smaller projectile
local PROJECTILE_COLOR = Color3.new(0.2, 1, 0.3) -- More vibrant green

-- Effect Constants
local EFFECT_CLEANUP_TIME = 1
local LIGHT_BRIGHTNESS = 3
local LIGHT_RANGE = 8
local PARTICLE_RATE = 30

local Ability = {}

-- Forward declarations
local executeAttack: (number?, Vector3?) -> ()
local playCharacterAnimation: (string, Vector3?) -> AnimationTrack?

-- Ability Interface Functions
function Ability.onRequest(ctx: SharedAbilityContext): AbilityResult
    return {
        success = true,
        cooldowns = { [tostring(ctx.abilityId)] = ctx.timestamp + COOLDOWN_TIME },
    }
end

function Ability.onReplicate(ctx: SharedAbilityContext, serverData: any?)
    -- Handle replication from other clients (latency compensated)
    local targetPosition = ctx.inputData.target
    task.spawn(executeAttack, ctx and ctx.timestamp, targetPosition)
end

function Ability.onCast(ctx: SharedAbilityContext, serverData: any?)
    -- Local client: play animation, projectile will spawn precisely on "Fire" event/keyframe
    -- Store the target position from the context for use during animation
    local targetPosition = ctx.inputData.target
    task.spawn(playCharacterAnimation, ANIMATION_NAME, targetPosition)
end

function Ability.OnCancel(ctx: SharedAbilityContext, reason: string?)
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

    local effect = effectsFolder:FindFirstChild("M1")
    if not effect then
        warn("No M1 effect found in Effects folder")
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
    Debris:AddItem(effectPart, EFFECT_CLEANUP_TIME)
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
    track.Priority = ANIM_PRIORITY
    pcall(function() track.Looped = false end)

    -- Hook precise trigger with target position
    connectFireTrigger(track, targetPosition)
    
    track:Play(ANIM_FADE_TIME, 1, 1)
    return track
end

local function createProjectileVisuals(projectile: BasePart)
    -- Add glowing effect
    local pointLight = Instance.new("PointLight")
    pointLight.Color = PROJECTILE_COLOR
    pointLight.Brightness = LIGHT_BRIGHTNESS
    pointLight.Range = LIGHT_RANGE
    pointLight.Parent = projectile
    
    -- Add particle effect
    local attachment = Instance.new("Attachment")
    attachment.Parent = projectile
    
    local particles = Instance.new("ParticleEmitter")
    particles.Parent = attachment
    particles.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, PROJECTILE_COLOR),
        ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), -- White in middle
        ColorSequenceKeypoint.new(1, PROJECTILE_COLOR)
    }
    particles.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.5, 0.6),
        NumberSequenceKeypoint.new(1, 0)
    }
    particles.Lifetime = NumberRange.new(0.2, 0.4)
    particles.Rate = PARTICLE_RATE
    particles.SpreadAngle = Vector2.new(30, 30)
    particles.Speed = NumberRange.new(3, 8)
    particles.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 1)
    }
    
    -- Add trail effect
    local trailAttachment0 = Instance.new("Attachment")
    trailAttachment0.Name = "TrailAttachment0"
    trailAttachment0.Position = Vector3.new(0, 0, -0.2)
    trailAttachment0.Parent = projectile
    
    local trailAttachment1 = Instance.new("Attachment")
    trailAttachment1.Name = "TrailAttachment1"
    trailAttachment1.Position = Vector3.new(0, 0, 0.2)
    trailAttachment1.Parent = projectile
    
    local trail = Instance.new("Trail")
    trail.Attachment0 = trailAttachment0
    trail.Attachment1 = trailAttachment1
    trail.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, PROJECTILE_COLOR),
        ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, PROJECTILE_COLOR)
    }
    trail.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.5, 0.4),
        NumberSequenceKeypoint.new(1, 1)
    }
    trail.Lifetime = 0.5
    trail.MinLength = 0
    trail.FaceCamera = true
    trail.WidthScale = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.5, 0.8),
        NumberSequenceKeypoint.new(1, 0)
    }
    trail.Parent = projectile
end

local function createSpiralProjectile(startPos: Vector3, endPos: Vector3): BasePart
    -- Create the projectile ball
    local projectile = Instance.new("Part")
    projectile.Name = "SpiralProjectile"
    projectile.Shape = Enum.PartType.Ball
    projectile.Material = Enum.Material.ForceField
    projectile.Size = PROJECTILE_SIZE
    projectile.Color = PROJECTILE_COLOR
    projectile.CanCollide = false
    projectile.Anchored = true
    projectile.CFrame = CFrame.new(startPos)
    projectile.Parent = workspace
    
    -- Add transparency for a more ethereal look
    projectile.Transparency = 0.3
    
    -- Add a mesh for smoother appearance
    local specialMesh = Instance.new("SpecialMesh")
    specialMesh.MeshType = Enum.MeshType.Sphere
    specialMesh.Scale = Vector3.new(1.2, 1.2, 1.2)
    specialMesh.Parent = projectile
    
    createProjectileVisuals(projectile)
    
    return projectile
end

local function calculateSpiralPosition(startPos: Vector3, direction: Vector3, progress: number, distance: number): Vector3
    -- Calculate base position along the path
    local basePos = startPos + direction * distance * progress
    
    -- Calculate spiral offset with smoother easing
    local spiralAngle = progress * math.pi * 2 * SPIRAL_FREQUENCY
    local spiralRadius = SPIRAL_RADIUS * (1 - progress * progress) -- Quadratic easing for smoother convergence
    
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
    local duration = distance / PROJECTILE_SPEED

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
    local startPos = character.PrimaryPart.Position + Vector3.new(0, 2, 0) -- Slightly above player
    
    -- Create and animate the spiral projectile
    local projectile = createSpiralProjectile(startPos, endPos)

    -- Latency compensation: start mid-flight on replicate
    local initialProgress: number? = nil
    if typeof(castTimestamp) == "number" then
        local distance = (endPos - startPos).Magnitude
        local duration = distance / PROJECTILE_SPEED
        initialProgress = math.clamp((time() - castTimestamp) / duration, 0, 1)
    end

    animateSpiralProjectile(projectile, startPos, endPos, function()
        -- Trigger impact effect exactly on arrival
        doEffect(character, endPos)
    end, initialProgress)
end

-- Ability Configuration Interface Functions
function Ability.getAbilityInputRequired()
    return Enum.UserInputType.MouseButton1
end

function Ability.getAbilityClassId()
    return ABILITY_CLASS
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
