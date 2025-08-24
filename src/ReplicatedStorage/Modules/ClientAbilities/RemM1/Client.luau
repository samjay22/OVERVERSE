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

local Assets = script.Parent.Assets

local Client = {}

-- Track pending server requests for rollback (if needed for server communication)
local pendingCasts = {} :: {[number]: boolean}

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
    print("[RemM1] executeAttack called with target:", targetPosition)
    if not targetPosition then 
        warn("[RemM1] No target position provided")
        return 
    end
    
    local character, humanoid = getCharacterData()
    if not character or not humanoid then return end

    local wand = character:FindFirstChild("Wand..") :: Tool?
    if not wand then return end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not humanoidRootPart then return end
    
    -- Use healing projectile from assets only
    local effectsFolder = Assets
    if not effectsFolder or not effectsFolder:FindFirstChild("HealSpellTrail") then
        warn("[RemM1] HealSpellTrail asset not found")
        return
    end

    local castEffect = effectsFolder.CastHeal:Clone()
    castEffect.CanCollide = false
    castEffect.Anchored = true
    castEffect.CFrame = CFrame.lookAt(wand:FindFirstChildOfClass("Part").Position, targetPosition)
    castEffect.Parent = workspace

    Debris:AddItem(castEffect, 1)
    print("[RemM1] Using HealSpellTrail from assets")
    local projectile = effectsFolder.HealSpellTrail:Clone()
    projectile.CanCollide = false
    projectile.Anchored = true
    
    -- Calculate trajectory with spiral motion
    local startPosition = humanoidRootPart.Position + humanoidRootPart.CFrame.LookVector * 3
    local endPosition = targetPosition
    local direction = (endPosition - startPosition).Unit
    local distance = (endPosition - startPosition).Magnitude
    
    -- Enhanced projectile animation with pulsing light and rotation
    local startTime = tick()
    -- Use a minimum travel time to ensure the projectile is always visible
    -- This gives a more consistent feel regardless of distance
    local baseTime = distance / Config.PROJECTILE_SPEED
    local minTime = 0.3 -- Minimum travel time for visual consistency
    local totalTime = math.max(baseTime, minTime)
    
    -- Add rotation animation to projectile for visual appeal
    local rotationSpeed = 360 -- degrees per second
    
    -- Don't animate lights - let the asset handle its own effects
    
    local connection
    connection = RunService.Heartbeat:Connect(function()
        local elapsed = tick() - startTime
        local progress = elapsed / totalTime
        
        if progress >= 1 then
            progress = 1
            connection:Disconnect()
            -- No light pulse to cancel
        end
        
        -- Linear movement with enhanced spiral rotation
        local currentPosition = startPosition:Lerp(endPosition, progress)
        
        -- Enhanced spiral motion with varying radius - scale based on distance
        local spiralAngle = (progress / 2) * Config.SPIRAL_FREQUENCY * math.pi * 2
        local spiralIntensity = math.sin((progress / 2) * math.pi) -- Peaks at midpoint
        
        -- Scale spiral radius based on distance
        -- Close range (0-15 studs): Reduced spiral
        -- Mid range (15-30 studs): Normal spiral
        -- Long range (30+ studs): Enhanced spiral
        local distanceScale
        if distance < 15 then
            distanceScale = 30  -- Reduced spiral for close range
            spiralAngle *= 0.5
            spiralIntensity *= 0.5
        elseif distance < 30 then
            distanceScale = 1  -- Normal spiral for mid range
        else
            distanceScale = 1 + (distance - 30) / 60  -- Enhanced spiral for long range (up to 1.5x at 60 studs)
        end
        
        local adjustedRadius = Config.SPIRAL_RADIUS * spiralIntensity * distanceScale
        
        local spiralOffset = Vector3.new(
            math.cos(spiralAngle) * adjustedRadius,
            math.sin(spiralAngle) * adjustedRadius,
            0
        )

        for _, emitter in pairs(projectile:GetDescendants()) do
            if emitter:IsA("ParticleEmitter") then
                emitter:Emit(5)
            end
        end
        
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
        projectile.Parent = workspace
                    
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
            
            -- Use impact effect from assets
            if effectsFolder and effectsFolder:FindFirstChild("HealHit") then
                local healEffect = effectsFolder.HealHit:Clone()
                healEffect.CanCollide = false
                healEffect.Anchored = true
                healEffect.Position = projectile.Position
                healEffect.Parent = workspace

                for _, emitter in pairs(healEffect:GetDescendants()) do
                    if emitter:IsA("ParticleEmitter") then
                        emitter:Emit(5)
                    end
                end

                -- Clean up after effect duration
                Debris:AddItem(healEffect, Config.EFFECT_CLEANUP_TIME)
            end

            -- Don't add any extra effects - the asset handles everything
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
        local fireTime = animationTrack.Length * 0.5 -- Fire at 35% through animation
        task.delay(fireTime, function()
            -- Just execute the attack - it will use assets
            executeAttack(tick(), targetPosition)
        end)

        -- Clean up animation track
        animationTrack.Ended:Connect(function()
            animationTrack:Destroy()
        end)
    end
end


-- Main execution function called by CategoryHandler
function Client.Execute(context: Types.SharedAbilityContext)
    -- Execute visual effects immediately
    -- Resource management is now handled by CategorySystem automatically
    Client.OnCast(context, nil)
    
    -- Return success (let server validate)
    return {
        success = true,
        message = "RemM1 executed"
    }
end

-- Validation function
function Client.Validate(context: Types.SharedAbilityContext) : {success: boolean, reason: string?}
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
        success = true,
    }
end

-- Primary ability execution - called by CategoryHandler for Primary abilities
function Client.OnCast(ctx: Types.SharedAbilityContext, serverData: any?)
    print("[RemM1] OnCast called with context:", ctx)
    -- Local client: execute immediately for now (animation system can be added later)
    local targetPosition = ctx.inputData.target
    print("[RemM1] Target position:", targetPosition)
    
    -- Don't execute attack here - let animation handle it
    
    -- Enhanced cast sound effect with pitch variation
    local castSound = Instance.new("Sound")
    castSound.SoundId = Config.SOUND_CAST_ID
    castSound.Volume = Config.SOUND_VOLUME
    castSound.Pitch = 0.95 + math.random() * 0.1 -- Slight pitch variation
    castSound.Parent = workspace
    castSound:Play()
    castSound.Ended:Connect(function() castSound:Destroy() end)
    
    -- Don't create casting circle - use only assets
    
    -- Execute animation which will handle the attack
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

-- Handle server confirmation of successful cast
function Client.OnServerConfirm(castId: number, serverData: any?)
    if pendingCasts[castId] then
        pendingCasts[castId] = nil
        -- Tracker reference removed, handle confirmation as needed
    end
end

-- Handle server rejection - rollback and cancel effects
function Client.OnServerReject(castId: number, reason: string?)
    if pendingCasts[castId] then
        pendingCasts[castId] = nil
        -- Tracker reference removed, handle rejection as needed
        
        -- Cancel any ongoing visual effects
        -- This could include stopping particles, sounds, etc.
        warn(`[RemM1] Server rejected cast: {reason or "Unknown reason"}`)
        
        -- TODO: Add visual feedback for rejection (e.g., red flash, error sound)
    end
end

-- Get current ability status for UI (now handled by CategorySystem)
function Client.GetAbilityStatus()
    -- Status is now managed by CategorySystem automatically
    -- UI should read directly from ClientCategoryHandler.GetResourceDisplay()
    return {
        text = "SEE_CATEGORY_SYSTEM",
        progress = 1,
        isReady = true,
        resourceType = "ammo"
    }
end

-- Manual reload function (for 'R' key press) - now handled by CategorySystem
function Client.RequestReload()
    -- Reload is now handled automatically by CategorySystem
    -- when ClientCategoryHandler.ForceReload() is called
    return true
end

return Client
