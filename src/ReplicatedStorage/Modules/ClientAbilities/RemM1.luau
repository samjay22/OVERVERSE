--!strict
-- Client Ability: RemM1 - Ranged attack with spiral projectile
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

local Player: Player = game.Players.LocalPlayer

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
local SPIRAL_RADIUS = 2
local SPIRAL_FREQUENCY = 3
local PROJECTILE_SIZE = Vector3.new(0.3, 0.3, 0.3) -- Smaller projectile
local PROJECTILE_COLOR = Color3.new(0.2, 1, 0.3) -- More vibrant green

-- Effect Constants
local EFFECT_CLEANUP_TIME = 1
local LIGHT_BRIGHTNESS = 3
local LIGHT_RANGE = 8
local PARTICLE_RATE = 30

local Ability = {}

-- Forward declarations
local executeAttack: () -> ()
local playCharacterAnimation: (string) -> AnimationTrack?

-- Ability Interface Functions
function Ability.onRequest(ctx: SharedAbilityContext): AbilityResult
    return {
        success = true,
        cooldowns = { [tostring(ctx.abilityId)] = ctx.timestamp + COOLDOWN_TIME },
    }
end

function Ability.onReplicate(ctx: SharedAbilityContext, serverData: any?)
    -- Handle replication from other clients
    task.spawn(executeAttack)
end

function Ability.onCast(ctx: SharedAbilityContext, serverData: any?)
    task.spawn(playCharacterAnimation, ANIMATION_NAME)
end

function Ability.OnCancel(ctx: SharedAbilityContext, reason: string?)
    -- Implementation if needed
end

-- Helper Functions
local function doEffect(character: Model?, targetPart: BasePart?)
    if not character or not targetPart then
        warn("Invalid character or target part for effect")
        return
    end

    local effectsFolder = character:FindFirstChild("Effects")
    if not effectsFolder then
        warn("No Effects folder in character")
        return
    end

    local effect = effectsFolder:FindFirstChild("M1")
    if not effect then
        warn("No M1 effect found")
        return
    end

    local effectClone = effect:Clone()
    effectClone.Parent = targetPart
    Debris:AddItem(effectClone, EFFECT_CLEANUP_TIME)
end

-- Helper function to find and play animations
playCharacterAnimation = function(animName: string): AnimationTrack?
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
    
    -- Handle existing playback
    if track.IsPlaying then
        track:Stop(ANIM_FADE_TIME)
    end
    
    -- Ensure single play
    pcall(function() track.Looped = false end)
    
    -- Handle loop prevention and cleanup
    local connections = {}
    
    connections.loop = track.DidLoop:Connect(function()
        track:Stop(ANIM_FADE_TIME)
        for _, conn: any in connections do
            conn:Disconnect()
        end
        table.clear(connections)
    end)
    
    connections.stop = track.Stopped:Connect(function()
        for _, conn in connections do
            conn:Disconnect()
        end
        table.clear(connections)
    end)
    
    -- Add halfway trigger for attack
    local halfwayTriggered = false
    connections.heartbeat = RunService.Heartbeat:Connect(function()
        if not halfwayTriggered and track.IsPlaying and track.TimePosition >= track.Length * 0.5 then
            halfwayTriggered = true
            task.spawn(executeAttack)
        end
    end)
    
    -- Play animation
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
    local right = direction:Cross(Vector3.new(0, 1, 0)).Unit
    if right.Magnitude == 0 then
        right = direction:Cross(Vector3.new(1, 0, 0)).Unit
    end
    local up = direction:Cross(right).Unit
    
    -- Apply spiral offset with slight vertical bias for more natural movement
    local spiralOffset = right * math.cos(spiralAngle) * spiralRadius + up * math.sin(spiralAngle) * spiralRadius * 0.7
    return basePos + spiralOffset
end

local function animateSpiralProjectile(projectile: BasePart, startPos: Vector3, endPos: Vector3): RBXScriptSignal
    local direction = (endPos - startPos).Unit
    local distance = (endPos - startPos).Magnitude
    local duration = distance / PROJECTILE_SPEED -- Duration based on consistent speed
    
    local startTime = tick()
    local connection: RBXScriptConnection
    
    connection = RunService.Heartbeat:Connect(function()
        local elapsed = tick() - startTime
        local progress = math.min(elapsed / duration, 1) -- Clamp progress to 1
        
        if progress >= 1 then
            projectile.CFrame = CFrame.new(endPos)
            connection:Disconnect()
            return
        end
        
        local finalPos = calculateSpiralPosition(startPos, direction, progress, distance)
        
        -- Update projectile position and rotation to face movement direction
        local lookDirection = direction
        if progress > 0 then
            -- Calculate velocity direction for more accurate rotation
            local nextProgress = math.min((elapsed + 0.016) / duration, 1) -- Next frame
            local nextPos = calculateSpiralPosition(startPos, direction, nextProgress, distance)
            lookDirection = (nextPos - finalPos).Unit
        end
        
        projectile.CFrame = CFrame.lookAt(finalPos, finalPos + lookDirection)
    end)
    
    -- Clean up after duration plus a small buffer
    Debris:AddItem(projectile, duration + 0.5)
    return projectile.Destroying
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

executeAttack = function()
    local character, targetPart = getTargetInfo()
    if not character or not targetPart or not character.PrimaryPart then return end

    -- Get start and end positions
    local startPos = character.PrimaryPart.Position + Vector3.new(0, 2, 0) -- Slightly above player
    local endPos = targetPart.Position + Vector3.new(0, 1, 0) -- Slightly above target
    
    -- Create and animate the spiral projectile
    local projectile = createSpiralProjectile(startPos, endPos)
    animateSpiralProjectile(projectile, startPos, endPos):Once(function()
        doEffect(character, targetPart)
    end)
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
