--!strict
-- RemM2 Client Module - Primary Category Ability with 3-burst fire
-- Uses ammo system with 3 different animations per burst

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local Config = require(script.Parent.Config)

local Player = Players.LocalPlayer

type AbilityAssets = typeof(script.Parent.Assets)
type SharedAbilityContext = Types.SharedAbilityContext

-- Get assets safely
local function getEffectsFolder()
    local parent = script.Parent
    if parent and parent:FindFirstChild("Assets") then
        return parent.Assets
    end
    return nil
end

local Client = {}

-- Track burst state
local burstState = {
    isFiring = false,
    currentShot = 0,
}

-- Audio system
local function playSoundEffect(soundId: string, volume: number?, pitch: number?)
    local sound = Instance.new("Sound")
    sound.SoundId = soundId
    sound.Volume = volume or Config.SOUND_VOLUME
    if pitch then
        sound.PlaybackSpeed = pitch
    end
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

-- Play cast hit effect
local function playCastHitEffect(assets: Folder, origin: Vector3)
    local castHitFolder = assets:FindFirstChild("CastHit")
    if not castHitFolder then return end
    
    -- Play cast effects (particles, sounds, etc.)
    for _, effect in castHitFolder:GetChildren() do
        if effect:IsA("ParticleEmitter") then
            local clone = effect:Clone()
            clone.Parent = workspace.Terrain
            clone.Position = origin
            clone:Emit(10)
            Debris:AddItem(clone, 2)
        elseif effect:IsA("Sound") then
            local clone = effect:Clone()
            clone.Parent = workspace
            clone:Play()
            Debris:AddItem(clone, clone.TimeLength)
        end
    end
end

-- Create and fire a single projectile
local function createProjectile(assets: Folder, origin: Vector3, direction: Vector3, shotIndex: number): BasePart?
    local projectileFolder = assets:FindFirstChild("projectile")
    if not projectileFolder then 
        warn("[RemM2] No projectile folder found in assets")
        return nil 
    end
    
    -- Clone the same projectile for each shot in the burst
    local projectileModel = projectileFolder:FindFirstChild("projectile1") or projectileFolder:FindFirstChildWhichIsA("BasePart") or projectileFolder:FindFirstChildWhichIsA("Model")
    
    if not projectileModel then
        warn("[RemM2] No projectile model found")
        return nil
    end
    
    local projectile = projectileModel:Clone() :: BasePart
    projectile.Parent = workspace
    projectile.CFrame = CFrame.lookAt(origin, origin + direction)
    projectile.AssemblyLinearVelocity = direction * Config.PROJECTILE_SPEED
    projectile.CanCollide = false
    projectile.Anchored = false
    
    -- Set up hit detection
    local hitConnection: RBXScriptConnection
    hitConnection = projectile.Touched:Connect(function(hit)
        if hit:IsDescendantOf(Player.Character) then return end
        if not hit.CanCollide then return end
        
        -- Play hit effect
        local effectAssets = getEffectsFolder()
        if effectAssets and playHitEffect then
            playHitEffect(effectAssets, projectile.Position, hit)
        end
        
        -- Clean up
        hitConnection:Disconnect()
        projectile:Destroy()
    end)
    
    -- Clean up after lifetime
    Debris:AddItem(projectile, Config.PROJECTILE_LIFETIME)
    
    return projectile
end

-- Forward declare playHitEffect (will be defined later)
local playHitEffect: ((assets: Folder, position: Vector3, hitPart: BasePart) -> ())?

-- Play hit effect implementation
playHitEffect = function(assets: Folder, position: Vector3, hitPart: BasePart)
    local hitFolder = assets:FindFirstChild("hit")
    if not hitFolder then return end
    
    -- Try to find hit effects
    local hitEffect = hitFolder:FindFirstChild("hit" .. math.random(1, 3))
    if not hitEffect then
        hitEffect = hitFolder:FindFirstChild("hit1")
    end
    
    if hitEffect then
        for _, effect in hitEffect:GetChildren() do
            if effect:IsA("ParticleEmitter") then
                local clone = effect:Clone()
                -- Create attachment for particle emitter at hit position
                local attachment = Instance.new("Attachment")
                attachment.WorldPosition = position
                attachment.Parent = workspace.Terrain
                clone.Parent = attachment
                clone:Emit(20)
                Debris:AddItem(attachment, 2)
            elseif effect:IsA("Sound") then
                local clone = effect:Clone()
                -- Create part for 3D sound positioning
                local soundPart = Instance.new("Part")
                soundPart.Anchored = true
                soundPart.CanCollide = false
                soundPart.Transparency = 1
                soundPart.Size = Vector3.new(0.1, 0.1, 0.1)
                soundPart.Position = position
                soundPart.Parent = workspace
                clone.Parent = soundPart
                clone:Play()
                Debris:AddItem(soundPart, clone.TimeLength + 0.1)
            end
        end
    end
end

-- Play animation for specific burst shot
local function playBurstAnimation(shotIndex: number): any?
    local character, humanoid = getCharacterData()
    if not character or not humanoid then return nil end
    
    local effectsFolder = getEffectsFolder()
    local animationsFolder = effectsFolder and effectsFolder:FindFirstChild("Animations")
    if not animationsFolder then
        warn("[RemM2] No animations folder found")
        return nil
    end
    
    -- Look for burst-specific animation (M2_1, M2_2, M2_3) or fallback to M2
    local animationName = Config.ANIMATION_NAME
    local animationObject = animationsFolder:FindFirstChild(animationName)
    
    if not animationObject then
        -- Fallback to base animation
        animationObject = animationsFolder:FindFirstChild(Config.ANIMATION_NAME)
    end
    
    if animationObject and animationObject:IsA("Animation") then
        local animationTrack = humanoid:LoadAnimation(animationObject)
        animationTrack.Priority = Config.ANIM_PRIORITY
        animationTrack:Play(Config.ANIM_FADE_TIME)
        
        -- Clean up when done
        animationTrack.Ended:Connect(function()
            animationTrack:Destroy()
        end)
        
        return animationTrack
    end
    
    return nil
end

-- Fire a single shot in the burst
local function fireShot(targetPosition: Vector3, shotIndex: number)
    print("[RemM2] Firing shot", shotIndex, "of burst")
    
    local character, humanoid = getCharacterData()
    if not character or not humanoid then return end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not humanoidRootPart then return end
    
    local origin = humanoidRootPart.Position + humanoidRootPart.CFrame.LookVector * 2 + Vector3.new(0, 1.5, 0)
    local direction = (targetPosition - origin).Unit
    
    -- Add slight spread variation for each shot
    local spread = 0.02 * shotIndex -- Increase spread with each shot
    direction = direction + Vector3.new(
        (math.random() - 0.5) * spread,
        (math.random() - 0.5) * spread,
        (math.random() - 0.5) * spread
    )
    direction = direction.Unit
    
    -- Play animation for this shot
    playBurstAnimation(shotIndex)
    
    -- Play sound with pitch variation
    local pitch = 1 + (shotIndex - 1) * 0.1 -- Higher pitch for later shots
    playSoundEffect(Config.SOUND_CAST_ID, Config.SOUND_VOLUME, pitch)
    
    -- Create projectile
    local assets = getEffectsFolder()
    if assets then
        createProjectile(assets, origin, direction, shotIndex)
        
        -- Play cast effect only on first shot
        if shotIndex == 1 then
            playCastHitEffect(assets, origin)
        end
    end
end

-- Execute the 3-burst fire continuously while held
local function executeBurst(targetPosition: Vector3)
    if burstState.isFiring then
        print("[RemM2] Already firing burst")
        return
    end
    
    burstState.isFiring = true
    burstState.currentShot = 0
    
    print("[RemM2] Starting continuous burst fire")
    
    -- Fire shots continuously while held, up to BURST_COUNT
    while burstState.isFiring and burstState.currentShot < Config.BURST_COUNT do
        burstState.currentShot = burstState.currentShot + 1
        fireShot(targetPosition, burstState.currentShot)
        
        -- Continue firing if not at max shots
        if burstState.currentShot < Config.BURST_COUNT then
            task.wait(Config.BURST_DELAY)
        end
    end
    
    -- Apply cooldown after burst completes
    if burstState.currentShot >= Config.BURST_COUNT then
        print("[RemM2] Burst complete, applying cooldown")
        task.wait(Config.FIRE_RATE) -- Cooldown before next burst can start
    end
    
    burstState.isFiring = false
    burstState.currentShot = 0
    print("[RemM2] Burst sequence ended")
end

-- Main execution function called by CategoryHandler
function Client.Execute(context: SharedAbilityContext)
    -- Call the OnCast function for backward compatibility
    Client.OnCast(context, nil)
    
    return {
        success = true,
        message = "RemM2 burst executed"
    }
end

-- Validation function
function Client.Validate(context: SharedAbilityContext)
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
    
    -- Check if already firing burst
    if burstState.isFiring then
        return {
            success = false,
            reason = "Burst in progress"
        }
    end
    
    return {
        success = true,
        reason = ""
    }
end

-- Primary ability execution - called by CategoryHandler for Primary abilities
function Client.OnCast(ctx: SharedAbilityContext, serverData: any?)
    print("[RemM2] OnCast called with target:", ctx.inputData and ctx.inputData.target)
    
    -- Get target position from context or mouse
    local targetPosition = ctx.inputData and ctx.inputData.target
    if not targetPosition then
        local mouse = Player:GetMouse()
        targetPosition = mouse.Hit.Position
    end
    
    -- Execute the 3-burst fire (ammo is already consumed by CategoryHandler - 1 ammo per click/shot)
    -- Note: Each click consumes 1 ammo and fires a 3-shot burst
    if targetPosition then
        task.spawn(executeBurst, targetPosition)
    else
        warn("[RemM2] No target position available")
    end
end

-- Replication handler - called when other clients use this ability
function Client.OnReplicate(ctx: SharedAbilityContext, serverData: any?)
    -- Handle replication from other clients
    local targetPosition = ctx.inputData and ctx.inputData.target
    if targetPosition then
        -- For replication, we might want to show simplified effects
        task.spawn(executeBurst, targetPosition)
    end
end

-- Cancellation handler
function Client.OnCancel(ctx: SharedAbilityContext, reason: string?)
    -- Handle ability cancellation
    warn("RemM2 burst cancelled:", reason or "Unknown reason")
    burstState.isFiring = false
    burstState.currentShot = 0
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