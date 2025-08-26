--!strict
-- M1 Ability using centralized AbilityStateMachine

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Types = require(game.ReplicatedStorage.Modules.Types.AbilityTypes)
local AbilityStateMachine = require(game.ReplicatedStorage.Modules.Utility.AbilityStateMachine)
local Targeting = require(game.ReplicatedStorage.Modules.CoreClient.Targeting)

-- Load effects
local EffectsFolder = game.ReplicatedStorage.Modules.Effects.Rem:WaitForChild("M1")
local Effects = {
    projectile = EffectsFolder:WaitForChild("projectile"),
    projectile1 = EffectsFolder:WaitForChild("projectile1"),
    projectile3 = EffectsFolder:WaitForChild("projectile3"),
    hit1 = EffectsFolder:WaitForChild("hit1"),
    hit2 = EffectsFolder:WaitForChild("hit2"),
    hit3 = EffectsFolder:WaitForChild("hit3"),
    Casthit = EffectsFolder:WaitForChild("Casthit"),
}

-- Configuration
local Config = {
    AnimationName = "M1",
    Range = 100,
    BurstAmount = 3,
    TimeBetweenBursts = 1,
    TimeBetweenShots = 0.65,
    Cooldown = 5,
    Ammo = 12,
    Enum = Enum.UserInputType.MouseButton1,
    AnimationList = {"1", "2", "3"},
}

-- State machine configuration
local STATE_MACHINE_CONFIG: AbilityStateMachine.AbilityConfig = {
    abilityName = "M1_State",
    syncRate = 0.05,
    syncOnChange = true, -- We'll manually control sync timing
    states = {
        -- Combat states
        {name = "Ammo", defaultValue = Config.Ammo, syncToClient = true},
        {name = "Burst", defaultValue = Config.BurstAmount, syncToClient = true},
        {name = "SequenceNumber", defaultValue = 0, syncToClient = true},
        
        -- Timing states
        {name = "LastShotTime", defaultValue = 0, syncToClient = true},
        {name = "BurstCooldownEnd", defaultValue = 0, syncToClient = true},
        {name = "ReloadCooldownEnd", defaultValue = 0, syncToClient = true},
        
        -- Client prediction states
        {name = "PendingShots", defaultValue = {}, syncToClient = true},
        {name = "ServerSequence", defaultValue = 0, syncToClient = true},
        {name = "LastSyncTime", defaultValue = 0, syncToClient = true},
    }
}

local Ability: Types.AbilityModule = {
    Name = "M1",
    Enum = Config.Enum,
    
    Client = {
        InternalState = {
            Animations = {},
            Effects = {}, -- Store active effect instances for cleanup
            Sounds = {},
            StateMachine = nil :: any, -- Will be set to AbilityStateMachine at runtime
            UpdateLoop = nil
        },
        AbilityEffects = game.ReplicatedStorage.Modules.Effects,
        AbilitySounds = Instance.new("Folder"),

        OnUse = function(self, player)
            
            -- Get or create state machine
            if not self.InternalState.StateMachine then
                self.InternalState.StateMachine = AbilityStateMachine.new(STATE_MACHINE_CONFIG, player.UserId)
                
                -- Set up state change listeners for client-side effects
                local sm = self.InternalState.StateMachine :: AbilityStateMachine.AbilityStateMachine
                sm:OnStateChange("Burst", function(newValue: any, oldValue: any)
                    local new = newValue :: number
                    local old = oldValue :: number
                    if new > old then
                        warn(`Burst recharged to {new}`)
                    end
                end)
                
                sm:OnStateChange("Ammo", function(newValue: any, oldValue: any)
                    local new = newValue :: number
                    local old = oldValue :: number
                    if old == 0 and new > 0 then
                        warn("Reload complete!")
                    end
                end)
            end
            
            local sm = self.InternalState.StateMachine :: AbilityStateMachine.AbilityStateMachine
            local currentTime = tick()
            
            -- Check cooldowns first
            if currentTime < sm:Get("BurstCooldownEnd") or currentTime < sm:Get("ReloadCooldownEnd") then
                return true
            end
            
            -- Check resources
            local ammo = sm:Get("Ammo") :: number
            local burst = sm:Get("Burst") :: number
            if ammo <= 0 or burst <= 0 then
                return true
            end
            
            -- Check timing - this is the main continuous fire check
            local lastShotTime = sm:Get("LastShotTime") :: number
            if currentTime - lastShotTime < Config.TimeBetweenShots then
                return true -- Still on cooldown, but keep ability active
            end
            
            -- Execute shot (client prediction)
            local sequence = sm:Get("SequenceNumber") + 1
            sm:SetMultiple({
                SequenceNumber = sequence,
                Ammo = ammo - 1,
                Burst = burst - 1,
                LastShotTime = currentTime,
            })
            
            -- Track pending shot
            local pending = sm:Get("PendingShots") :: {number}
            table.insert(pending, sequence)
            sm:Set("PendingShots", pending)
            
            warn(`Client M1 - Seq: {sequence}, Burst: {burst-1}/{Config.BurstAmount}, Ammo: {ammo-1}/{Config.Ammo}`)

            -- Play animation and get the track for timing
            local playAnim = (self :: any)._PlayAnimation
            local animationTrack = nil
            if playAnim then
                animationTrack = playAnim(self, player, burst - 1)
            end
            
            task.spawn(function()
                -- Spawn effects based on burst count
            if player.Character then
                local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if humanoidRootPart then
                    -- Choose effect based on which shot in the burst this is
                    local shotInBurst = Config.BurstAmount - (burst - 1)
                    
                    -- Get target direction using Targeting module
                    local targetingSystem = Targeting.new()
                    local target = targetingSystem:GetLocalTarget()
                    local direction = humanoidRootPart.CFrame.LookVector
                    
                    if target and target.PrimaryPart then
                        -- Calculate direction to target
                        direction = ((target.PrimaryPart :: BasePart).Position - humanoidRootPart.Position).Unit
                    elseif RunService:IsClient() then
                        -- Fall back to mouse position if no specific target
                        local mouse = player:GetMouse()
                        if mouse and mouse.Hit then
                            direction = (mouse.Hit.Position - humanoidRootPart.Position).Unit
                        end
                    end
                    
                    
                    -- Spawn projectile after animation timing (ensure animation plays fully)
                    if animationTrack then
                        -- Wait for animation to reach firing point (typically 30% through)
                        local fireDelay = math.max(animationTrack.Length * 0.3, 0.1)
                        task.delay(fireDelay, function()
                            if player.Character then
                                local hrp = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                                if hrp then
                                    -- Spawn cast effect immediately
                                    local spawnCast = (self :: any)._SpawnCastEffect
                                    local spawnProj = (self :: any)._SpawnProjectileEffect
                                    if spawnCast then
                                        spawnCast(self, hrp.Position, direction, shotInBurst)
                                    end
                                    if spawnProj then
                                        spawnProj(self, hrp.Position, direction, shotInBurst)
                                    end
                                end
                            end
                        end)
                    else
                        -- If no animation, spawn immediately
                        local spawnProj = (self :: any)._SpawnProjectileEffect
                        if spawnProj then
                            spawnProj(self, humanoidRootPart.Position, direction, shotInBurst)
                        end
                    end
                end
            end
            end)
            
            -- Handle cooldowns
            if ammo - 1 <= 0 then
                warn("Out of ammo - reloading")
                -- Out of ammo, need reload
                sm:Set("ReloadCooldownEnd", currentTime + Config.Cooldown)
                task.delay(Config.Cooldown, function()
                    if sm:Get("Ammo") <= 0 then
                        sm:SetMultiple({
                            Ammo = Config.Ammo,
                            Burst = Config.BurstAmount,
                        })
                        warn("Reload complete!")
                    end
                end)
            elseif burst - 1 <= 0 then
                warn("Burst depleted - cooling down")
                -- Burst depleted, need burst cooldown
                sm:Set("BurstCooldownEnd", currentTime + Config.TimeBetweenBursts)
                task.delay(Config.TimeBetweenBursts, function()
                    if sm:Get("Burst") <= 0 then
                        sm:Set("Burst", Config.BurstAmount)
                        warn("Burst recharged!")
                    end
                end)
            end
            -- No else needed - timing check handles shot cooldown
            
            return true
        end,
        
        _PlayAnimation = function(self, player, currentBurst: number): AnimationTrack?
            local animations = self:GetCharacterAnimations(player)
            if not animations then 
                warn("No animations folder found for player")
                return nil
            end
            
            local animIndex = Config.BurstAmount - currentBurst
            local animName = Config.AnimationList[animIndex] or Config.AnimationName
            warn(`Looking for animation: {animName} in animations folder`)
            local animation = animations:FindFirstChild(animName)
            
            if animation then
                warn(`Found animation: {animName}`)
                local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    local animator = humanoid:FindFirstChildOfClass("Animator")
                    if not animator then
                        animator = Instance.new("Animator")
                        animator.Parent = humanoid
                    end
                    -- Cast animator since we know it exists
                    local animationTrack: AnimationTrack = (animator :: Animator):LoadAnimation(animation :: Animation)
                    table.insert(self.InternalState.Animations, animationTrack)
                    animationTrack.Looped = false
                    animationTrack.Priority = Enum.AnimationPriority.Action -- Ensure animation has priority
                    animationTrack:Play()
                    
                    -- Don't let animation be interrupted
                    animationTrack.Stopped:Connect(function()
                        -- Remove from tracking when naturally stopped
                        local index = table.find(self.InternalState.Animations, animationTrack)
                        if index then
                            table.remove(self.InternalState.Animations, index)
                        end
                    end)
                    
                    return animationTrack
                end
            end
            
            warn(`Animation not found: {animName}`)
            return nil
        end,
        
        _SpawnCastEffect = function(self, position: Vector3, direction: Vector3, shotNumber: number)
            local castEffect = Effects.Casthit:Clone()
            castEffect.Anchored = true
            castEffect.CanCollide = false
            castEffect.Position = position + direction * 2
            castEffect.CFrame = CFrame.lookAt(castEffect.Position, castEffect.Position + direction)
            castEffect.Parent = workspace
            
            -- Emit particles once when spawned
            for _, descendant in castEffect:GetDescendants() do
                if descendant:IsA("ParticleEmitter") then
                    descendant:Emit(descendant.Rate * 0.5) -- Emit based on rate
                end
            end
            
            -- Store for cleanup
            table.insert(self.InternalState.Effects, castEffect)
            
            -- Auto cleanup after delay
            game:GetService("Debris"):AddItem(castEffect, 2)
        end,
        
        _SpawnProjectileEffect = function(self, position: Vector3, direction: Vector3, shotNumber: number?)
            -- Choose projectile based on shot number (1, 2, or 3)
            local projectileEffect
            if shotNumber == 1 then
                projectileEffect = Effects.projectile:Clone()
            elseif shotNumber == 2 then
                projectileEffect = Effects.projectile1:Clone()
            else
                projectileEffect = Effects.projectile3:Clone()
            end
            
            -- Projectile configuration
            local PROJECTILE_SPEED = 100 -- studs per second
            local MAX_DISTANCE = Config.Range or 100 -- max travel distance
            local TRAVEL_TIME = MAX_DISTANCE / PROJECTILE_SPEED
            
            projectileEffect.Anchored = true -- Anchor and move manually for better control
            projectileEffect.CanCollide = false
            projectileEffect.Position = position + direction * 3
            projectileEffect.CFrame = CFrame.lookAt(projectileEffect.Position, projectileEffect.Position + direction)
            projectileEffect.Parent = workspace
            
            -- Store for cleanup
            table.insert(self.InternalState.Effects, projectileEffect)
            
            local startTime = tick()
            local startPosition = projectileEffect.Position
            local hasHit = false
            
            -- Emit particles and move projectile
            local updateConnection
            updateConnection = RunService.Heartbeat:Connect(function()
                if not projectileEffect or not projectileEffect.Parent or hasHit then
                    if updateConnection then
                        updateConnection:Disconnect()
                    end
                    return
                end
                
                local elapsedTime = tick() - startTime
                local travelDistance = PROJECTILE_SPEED * elapsedTime
                
                -- Check if max distance reached
                if travelDistance >= MAX_DISTANCE then
                    hasHit = true
                    self:_SpawnHitEffect(projectileEffect.Position, shotNumber)
                    projectileEffect:Destroy()
                    updateConnection:Disconnect()
                    return
                end
                
                -- Update position
                local newPosition = startPosition + (direction * travelDistance)
                projectileEffect.Position = newPosition
                projectileEffect.CFrame = CFrame.lookAt(newPosition, newPosition + direction)
                
                -- Emit particles
                for _, descendant in projectileEffect:GetDescendants() do
                    if descendant:IsA("ParticleEmitter") then
                        descendant:Emit(1)
                    end
                end
                
                -- Check for hits using spatial query
                local params = OverlapParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = {projectileEffect, game.Players.LocalPlayer.Character}
                
                local hitParts = workspace:GetPartBoundsInBox(
                    CFrame.new(newPosition),
                    Vector3.new(4, 4, 4), -- Hit detection size
                    params
                )
                
                for _, hitPart in ipairs(hitParts) do
                    if hitPart.Parent and hitPart.Parent:FindFirstChild("Humanoid") then
                        -- Hit a character
                        hasHit = true
                        self:_SpawnHitEffect(newPosition, shotNumber)
                        projectileEffect:Destroy()
                        updateConnection:Disconnect()
                        return
                    elseif hitPart.CanCollide then
                        -- Hit terrain or solid object
                        hasHit = true
                        self:_SpawnHitEffect(newPosition, shotNumber)
                        projectileEffect:Destroy()
                        updateConnection:Disconnect()
                        return
                    end
                end
            end)
            
            -- Auto cleanup after travel time
            task.delay(TRAVEL_TIME, function()
                if updateConnection then
                    updateConnection:Disconnect()
                end
                if projectileEffect and projectileEffect.Parent and not hasHit then
                    self:_SpawnHitEffect(projectileEffect.Position, shotNumber)
                    projectileEffect:Destroy()
                end
            end)
        end,
        
        _SpawnHitEffect = function(self, position: Vector3, shotNumber: number?)
            -- Choose hit effect based on shot number
            local hitEffect
            if shotNumber == 1 then
                hitEffect = Effects.hit1:Clone()
            elseif shotNumber == 2 then
                hitEffect = Effects.hit2:Clone()
            else
                hitEffect = Effects.hit3:Clone()
            end
            
            hitEffect.Anchored = true
            hitEffect.CanCollide = false
            hitEffect.Position = position
            hitEffect.Parent = workspace
            
            -- Emit hit particles once
            for _, descendant in hitEffect:GetDescendants() do
                if descendant:IsA("ParticleEmitter") then
                    descendant:Emit(descendant.Rate) -- Full burst on hit
                end
            end
            
            -- Store for cleanup
            table.insert(self.InternalState.Effects, hitEffect)
            
            -- Auto cleanup after delay
            game:GetService("Debris"):AddItem(hitEffect, 1.5)
        end,
        
        OnStateSync = function(self, syncData: {[string]: any})
            if not self.InternalState.StateMachine then
                return false
            end
            
            local sm = self.InternalState.StateMachine
            local serverSeq = syncData.SequenceNumber or 0
            local localSeq = sm:Get("SequenceNumber") :: number
            
            -- Remove confirmed shots
            local pending = sm:Get("PendingShots") :: {number}
            local newPending = {}
            for _, seq in ipairs(pending) do
                if seq > serverSeq then
                    table.insert(newPending, seq)
                end
            end
            sm:Set("PendingShots", newPending)
            
            -- Check if we should apply server state
            if serverSeq >= localSeq - #newPending then
                local oldAmmo = sm:Get("Ammo")
                local oldBurst = sm:Get("Burst")
                
                -- Apply sync data (AbilityStateMachine handles the actual sync)
                -- This is called automatically by the state machine's sync listener
                
                if oldAmmo ~= syncData.Ammo or oldBurst ~= syncData.Burst then
                    warn(`Client reconciled - Ammo: {oldAmmo} -> {syncData.Ammo}, Burst: {oldBurst} -> {syncData.Burst}`)
                end
            end
            
            return true
        end,

        OnCancel = function(self, player)
            -- Only cancel if server state is significantly out of sync
            -- Don't cancel just because mouse was lifted
            
            -- Check if we need to force cancel due to state desync
            if self.InternalState.StateMachine then
                local sm = self.InternalState.StateMachine
                local serverSeq = sm:Get("ServerSequence") or 0
                local localSeq = sm:Get("SequenceNumber") or 0
                
                -- Only force cancel if significantly out of sync (>5 sequences behind)
                if math.abs(serverSeq - localSeq) > 5 then
                    -- Stop animations that haven't finished naturally
                    for _, animationTrack in ipairs(self.InternalState.Animations) do
                        if animationTrack.IsPlaying then
                            animationTrack:Stop()
                        end
                    end
                    table.clear(self.InternalState.Animations)
                    
                    -- Clean up effects
                    for _, effect in ipairs(self.InternalState.Effects) do
                        if effect and effect.Parent then
                            effect:Destroy()
                        end
                    end
                    table.clear(self.InternalState.Effects)
                    
                    -- Stop sounds
                    for _, sound in ipairs(self.InternalState.Sounds) do
                        sound:Stop()
                    end
                    table.clear(self.InternalState.Sounds)
                    
                    warn("M1 ability cancelled due to server desync")
                    return true
                end
            end
            
            -- Don't cancel for normal mouse release
            return false
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
            
            -- Play animation for the other player
            local animations = self:GetCharacterAnimations(player)
            if animations then
                -- Use a random animation from the list for variety
                local animIndex = math.random(1, #Config.AnimationList)
                local animName = Config.AnimationList[animIndex] or Config.AnimationName
                local animation = animations:FindFirstChild(animName)
                
                if animation then
                    local humanoid = character:FindFirstChildOfClass("Humanoid")
                    if humanoid then
                        local animationTrack: AnimationTrack = humanoid:LoadAnimation(animation)
                        animationTrack.Looped = false
                        animationTrack.Priority = Enum.AnimationPriority.Action -- Ensure animation has priority
                        animationTrack:Play()
                        
                        -- Get target direction for replicated shots
                        local direction = humanoidRootPart.CFrame.LookVector
                        
                        -- Spawn projectile effect after animation reaches firing point
                        local fireDelay = math.max(animationTrack.Length * 0.3, 0.1)
                        task.delay(fireDelay, function()
                            if character.Parent and humanoidRootPart.Parent then -- Ensure character still exists
                                (self :: any):_SpawnProjectileEffect(humanoidRootPart.Position, direction)
                            end
                        end)
                    end
                end
            end
            
            -- Play cast hit effect at character position
            local castHit = Effects.Casthit:Clone()
            castHit.Anchored = true
            castHit.CanCollide = false
            castHit.Position = humanoidRootPart.Position + humanoidRootPart.CFrame.LookVector * 2
            castHit.Parent = workspace
            
            -- Emit particles once when spawned
            for _, descendant in castHit:GetDescendants() do
                if descendant:IsA("ParticleEmitter") then
                    descendant:Emit(descendant.Rate * 0.5)
                end
            end
            
            -- Clean up effect after a delay
            game:GetService("Debris"):AddItem(castHit, 2)
            
            return true
        end,

        GetCharacterAnimations = function(self, player)
            local character = player.Character
            if not character then
                warn("No character found for player")
                return nil
            end
            
            local animations = character:FindFirstChild("Animations") :: Folder?
            if not animations then
                local childNames = {}
                for _, child in character:GetChildren() do
                    table.insert(childNames, child.Name)
                end
                warn(`No Animations folder in character. Children: {table.concat(childNames, ", ")}`)
                -- Try to find animations in humanoid
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    animations = humanoid:FindFirstChild("Animations") :: Folder?
                    if animations then
                        warn("Found Animations folder in Humanoid")
                    end
                end
            else
                warn(`Found Animations folder with {#animations:GetChildren()} children`)
            end
            
            return animations :: any
        end
    },

    Server = {
        InternalState = {
            PlayerStateMachines = {} :: {[number]: AbilityStateMachine.AbilityStateMachine},
        },
        
        Validate = function(self, player, ctxExtra)
            local playerId = player.UserId
            local currentTime = tick()
            
            -- Get or create state machine
            if not self.InternalState.PlayerStateMachines[playerId] then
                self.InternalState.PlayerStateMachines[playerId] = AbilityStateMachine.new(STATE_MACHINE_CONFIG, playerId)
            end
            
            local sm = self.InternalState.PlayerStateMachines[playerId]
            
            -- Validation checks
            if currentTime < sm:Get("BurstCooldownEnd") or currentTime < sm:Get("ReloadCooldownEnd") then
                sm:SyncToClient(player, true)
                return false
            end
            
            local ammo = sm:Get("Ammo") :: number
            local burst = sm:Get("Burst") :: number
            
            if ammo <= 0 or burst <= 0 then
                sm:SyncToClient(player, true)
                return false
            end
            
            local lastShotTime = sm:Get("LastShotTime") :: number
            if currentTime - lastShotTime < Config.TimeBetweenShots then
                sm:SyncToClient(player, true)
                return false
            end
            
            -- Process valid shot
            local sequence = sm:Get("SequenceNumber") + 1
            sm:SetMultiple({
                SequenceNumber = sequence,
                Ammo = ammo - 1,
                Burst = burst - 1,
                LastShotTime = currentTime,
            })
            
            warn(`Server M1 - Seq: {sequence}, Burst: {burst-1}/{Config.BurstAmount}, Ammo: {ammo-1}/{Config.Ammo}`)
            
            -- Handle cooldowns
            if ammo - 1 <= 0 then
                -- Out of ammo, need reload
                sm:Set("ReloadCooldownEnd", currentTime + Config.Cooldown)
                task.delay(Config.Cooldown, function()
                    if self.InternalState.PlayerStateMachines[playerId] then
                        local psm = self.InternalState.PlayerStateMachines[playerId]
                        psm:SetMultiple({
                            Ammo = Config.Ammo,
                            Burst = Config.BurstAmount,
                        })
                        psm:SyncToClient(player, true)
                    end
                end)
            elseif burst - 1 <= 0 then
                -- Burst depleted, need burst cooldown
                sm:Set("BurstCooldownEnd", currentTime + Config.TimeBetweenBursts)
                task.delay(Config.TimeBetweenBursts, function()
                    if self.InternalState.PlayerStateMachines[playerId] then
                        local psm = self.InternalState.PlayerStateMachines[playerId]
                        psm:Set("Burst", Config.BurstAmount)
                        psm:SyncToClient(player, true)
                    end
                end)
            end
            -- No else needed - timing check handles shot cooldown
            
            -- Sync state to client
            sm:SyncToClient(player)
            
            return true
        end,
        
        _SyncToClient = function(self, player: Player, sm: AbilityStateMachine.AbilityStateMachine)
            -- This is now handled by the state machine itself
            sm:SyncToClient(player)
            return true
        end,

        OnUpdate = function(self, dt)
            -- Clean up disconnected players
            for playerId, sm in pairs(self.InternalState.PlayerStateMachines) do
                local player = Players:GetPlayerByUserId(playerId)
                if not player then
                    sm:Destroy()
                    self.InternalState.PlayerStateMachines[playerId] = nil
                end
            end
            
            return true
        end,
    }
}

return Ability