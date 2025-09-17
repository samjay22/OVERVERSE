--!strict
-- Shift Ability - Client-side implementation for movement dash ability

local Types = require(game.ReplicatedStorage.Modules.Types.AbilityTypes)
local AbilityStateMachine = require(game.ReplicatedStorage.Modules.Utility.AbilityStateMachine)
local CameraShaker = require(game.ReplicatedStorage.Modules.Utility.CameraShakeManager)

-- Configuration
local Config = {
    CooldownTime = 3.0,
    DashDistance = 25,
    DashSpeed = 200,
    Enum = Enum.KeyCode.Q, -- Q key for slot 1 in actives
}

-- State machine configuration
local STATE_MACHINE_CONFIG: AbilityStateMachine.AbilityConfig = {
    abilityName = "Rem_Shift",
    states = {
        {name = "CooldownEnd", defaultValue = 0, syncToClient = true},
        {name = "LastUseTime", defaultValue = 0, syncToClient = true},
        {name = "IsDashing", defaultValue = false, syncToClient = true},
        {name = "DashDirection", defaultValue = Vector3.new(0, 0, -1), syncToClient = false},
    }
}

-- Helper functions outside the main table to avoid type issues
local function playDashAnimation(self: any, player: Player)
    if not player.Character then return end
    
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return end
    
    -- Try to load dash animation (placeholder for now)
    local animationId = "rbxassetid://0" -- Replace with actual animation ID
    local animation = Instance.new("Animation")
    animation.AnimationId = animationId
    
    -- Play animation (this will fail with the placeholder ID, but shows the pattern)
    pcall(function()
        local animationTrack = animator:LoadAnimation(animation)
        if self.InternalState then
            self.InternalState.Animations = self.InternalState.Animations or {}
            self.InternalState.Animations.Dash = animationTrack
        end
        animationTrack:Play()
    end)
end

local function playDashSound(self: any, player: Player)
    if not player.Character then return end
    
    local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end
    
    -- Play dash sound effect (placeholder)
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://131961136" -- Placeholder sound
    sound.Volume = 0.5
    sound.Parent = humanoidRootPart
    sound:Play()
    
    -- Clean up sound after it finishes
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
    
    if self.InternalState then
        self.InternalState.Sounds = self.InternalState.Sounds or {}
        self.InternalState.Sounds.Dash = sound
    end
end

local function startDashEffects(self: any, player: Player)
    if not player.Character then return end
    
    local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not humanoidRootPart then return end
    
    -- Create dash trail effect (simple particle system)
    local attachment = Instance.new("Attachment")
    attachment.Name = "ShiftTrail"
    attachment.Parent = humanoidRootPart
    
    -- Add particle effect for dash trail
    local particles = Instance.new("ParticleEmitter")
    particles.Name = "DashParticles"
    particles.Parent = attachment
    
    -- Configure particles
    particles.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
    particles.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 1)
    }
    particles.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 0)
    }
    particles.Lifetime = NumberRange.new(0.3, 0.6)
    particles.Rate = 100
    particles.SpreadAngle = Vector2.new(45, 45)
    particles.Speed = NumberRange.new(5, 15)
    
    -- Store effect for cleanup
    if self.InternalState then
        self.InternalState.Effects = self.InternalState.Effects or {}
        self.InternalState.Effects.DashTrail = attachment
    end
end

local function endDashEffects(self: any, player: Player)
    -- Clean up dash effects
    if self.InternalState and self.InternalState.Effects and self.InternalState.Effects.DashTrail then
        local attachment = self.InternalState.Effects.DashTrail :: Attachment
        if attachment.Parent then
            -- Stop particle emission and clean up after particles fade
            local particles = attachment:FindFirstChild("DashParticles") :: ParticleEmitter?
            if particles then
                particles.Enabled = false
                task.delay(particles.Lifetime.Max, function()
                    attachment:Destroy()
                end)
            else
                attachment:Destroy()
            end
        end
        self.InternalState.Effects.DashTrail = nil
    end
end

local Ability: Types.AbilityModule = {
    Name = "Shift",
    Enum = Config.Enum,
    
    Client = {
        InternalState = {
            Animations = {},
            Effects = {},
            Sounds = {},
        },
        AbilityEffects = game.ReplicatedStorage.Modules.Effects,
        AbilitySounds = Instance.new("Folder"),

        OnUse = function(self, player)
            -- Get or create state machine
            local selfAny = self :: any
            if not selfAny.InternalState.StateMachine then
                selfAny.InternalState.StateMachine = AbilityStateMachine.new(STATE_MACHINE_CONFIG, player.UserId)
                
                -- Set up state change listeners for client-side effects
                local sm = selfAny.InternalState.StateMachine :: AbilityStateMachine.AbilityStateMachine
                sm:OnStateChange("IsDashing", function(newValue: any, oldValue: any)
                    local isDashing = newValue :: boolean
                    if isDashing then
                        startDashEffects(selfAny, player)
                    else
                        endDashEffects(selfAny, player)
                    end
                end)
            end
            
            local sm = selfAny.InternalState.StateMachine :: AbilityStateMachine.AbilityStateMachine
            local currentTime = tick()
            
            -- Check cooldown
            local cooldownEnd = sm:Get("CooldownEnd") :: number
            if currentTime < cooldownEnd then
                return true -- On cooldown
            end
            
            -- Check if already dashing
            local isDashing = sm:Get("IsDashing") :: boolean
            if isDashing then
                return true -- Already dashing
            end
            
            -- Get dash direction (player's facing direction)
            local dashDirection = Vector3.new(0, 0, -1) -- Default forward
            if player.Character then
                local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if humanoidRootPart then
                    dashDirection = humanoidRootPart.CFrame.LookVector
                end
            end
            
            -- Execute dash (client prediction)
            sm:SetMultiple({
                CooldownEnd = currentTime + Config.CooldownTime,
                LastUseTime = currentTime,
                IsDashing = true,
                DashDirection = dashDirection,
            })
            
            warn(`Client Shift - Starting dash in direction: {dashDirection}`)
            
            -- Play dash animation and effects
            playDashAnimation(selfAny, player)
            playDashSound(selfAny, player)
            
            -- Camera shake
            if player.Character then
                local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if humanoidRootPart then
                    CameraShaker.Bump(humanoidRootPart.Position, 5, 0.2)
                end
            end
            
            -- End dash after a short duration (for client prediction)
            task.delay(0.2, function()
                if sm then
                    sm:Set("IsDashing", false)
                end
            end)
            
            return true
        end,

        OnReplicate = function(self, player)
            -- Handle ability replication from other players
            if not player or not player.Character then
                return false
            end
            
            local character = player.Character
            local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
            if not humanoidRootPart then
                return false
            end
            
            local selfAny = self :: any
            
            -- Play visual effects for other players
            playDashAnimation(selfAny, player)
            startDashEffects(selfAny, player)
            
            -- Clean up effects after dash duration
            task.delay(0.2, function()
                endDashEffects(selfAny, player)
            end)
            
            return true
        end,

        OnCancel = function(self, player)
            -- Cancel dash if needed
            local selfAny = self :: any
            if selfAny.InternalState.StateMachine then
                local sm = selfAny.InternalState.StateMachine :: AbilityStateMachine.AbilityStateMachine
                sm:Set("IsDashing", false)
            end
            
            -- Clean up effects
            endDashEffects(selfAny, player)
            
            return true
        end,

        GetCharacterAnimations = function(self, player)
            local character = player.Character
            if not character then
                warn("No character found for player")
                return Instance.new("Folder") -- Return empty folder to satisfy interface
            end
            
            local animations = character:FindFirstChild("Animations") :: Folder?
            if not animations then
                warn("No Animations folder in character")
                return Instance.new("Folder") -- Return empty folder to satisfy interface
            end
            
            return animations
        end,

        OnStateSync = function(self, syncData: {[string]: any})
            -- Handle state synchronization from server
            local selfAny = self :: any
            if not selfAny.InternalState.StateMachine then
                return false
            end
            
            local sm = selfAny.InternalState.StateMachine :: AbilityStateMachine.AbilityStateMachine
            
            -- Sync relevant states
            for stateName, value in pairs(syncData) do
                if stateName == "IsDashing" or stateName == "CooldownEnd" or stateName == "LastUseTime" then
                    sm:Set(stateName, value)
                end
            end
            
            return true
        end,
    }
}

return Ability
