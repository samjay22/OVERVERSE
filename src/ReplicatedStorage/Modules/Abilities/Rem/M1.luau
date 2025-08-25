local Types = require(game.ReplicatedStorage.Modules.Types.AbilityTypes)

local Config = {
    AnimationName = "M1",
    Range = 100,
    BurstAmount = 3,
    TimeBetweenBursts = 2,
    TimeBetweenShots = .65,
    Cooldown = 5,
    Ammo = 11, -- 0 indexed
    Enum = Enum.UserInputType.MouseButton1,
    AnimationList = {"1", "2", "3"}
}

local Ability : Types.AbilityModule = {
    Name = "M1",
    Enum = Config.Enum,
    
    Client = {
        InternalState = {
            Animations = {},
            Effects = {},
            Sounds = {},

            CanAttack = true,
            Burst = Config.BurstAmount,
            Ammo = Config.Ammo,
        },
        AbilityEffects = game.ReplicatedStorage.Modules.Effects,
        AbilitySounds = Instance.new("Folder"),

        OnUse = function(self, player)
            -- Check if we can attack
            if not self.InternalState.CanAttack then
                -- Return true to keep the input active, just skip this frame
                return true
            end
            
            -- Prevent next shot until cooldown
            self.InternalState.CanAttack = false

            warn("Client M1 fired - Burst:", self.InternalState.Burst, "Ammo:", self.InternalState.Ammo)
            
            -- Get and play animation
            local animations = self:GetCharacterAnimations(player)
            if animations then
                -- Calculate which animation to play (1, 2, or 3 based on burst count)
                local animIndex = Config.BurstAmount - self.InternalState.Burst + 1
                local animName = Config.AnimationList[animIndex] or Config.AnimationName
                local animation = animations:FindFirstChild(animName)
                if animation then
                    local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
                    if humanoid then
                        local animationTrack : AnimationTrack = humanoid:LoadAnimation(animation)
                        table.insert(self.InternalState.Animations, animationTrack)
                        animationTrack.Looped = false
                        animationTrack:Play()
                    end
                end
            end

            -- Update ammo and burst
            self.InternalState.Ammo -= 1
            self.InternalState.Burst -= 1
            
            -- Handle burst cooldown
            if self.InternalState.Burst <= 0 then
                warn("Burst empty, cooldown for", Config.TimeBetweenBursts, "seconds")
                task.delay(Config.TimeBetweenBursts, function()
                    self.InternalState.Burst = Config.BurstAmount
                    self.InternalState.CanAttack = true
                    warn("Burst ready!")
                end)
            -- Handle reload cooldown
            elseif self.InternalState.Ammo <= 0 then
                warn("Ammo empty, reloading for", Config.Cooldown, "seconds")
                task.delay(Config.Cooldown, function()
                    self.InternalState.Ammo = Config.Ammo
                    self.InternalState.Burst = Config.BurstAmount
                    self.InternalState.CanAttack = true
                    warn("Reload complete!")
                end)
            -- Normal shot cooldown
            else
                task.delay(Config.TimeBetweenShots, function()
                    self.InternalState.CanAttack = true
                end)
            end

            -- Always return true to keep input active
            return true
        end,

        OnCancel = function(self, player)
            task.spawn(function()
                for _, animationTrack in ipairs(self.InternalState.Animations) do
                    animationTrack:Stop()
                end
            end)

            task.spawn(function()
                for _, effect in ipairs(self.InternalState.Effects) do
                    effect:Stop()
                end
            end)

            task.spawn(function()
                for _, sound in ipairs(self.InternalState.Sounds) do
                    sound:Stop()
                end
            end)

            return true
        end,

        OnReplicate = function(self, player)
            -- Handle ability replication
            return true
        end,

        GetCharacterAnimations = function(self, player)
            return player.Character and player.Character:FindFirstChild("Animations")
        end
    },

    Server = {
        InternalState = {
            AbilityCooldowns = {},
            BurstCooldowns = {},
            PlayerStates = {},
            UpdateLoop = {},
            Cooldowns = {},
        },
        
        Validate = function(self, player, ctxExtra)
            local playerId = player.UserId
            local currentTime = os.clock() + .105
            
            -- Initialize player state if needed
            if not self.InternalState.PlayerStates[playerId] then
                self.InternalState.PlayerStates[playerId] = {
                    Ammo = Config.Ammo,
                    BurstAmount = Config.BurstAmount,
                    LastShotTime = 0,
                }
                self.InternalState.BurstCooldowns[playerId] = 0
                self.InternalState.AbilityCooldowns[playerId] = 0
                self.InternalState.Cooldowns[playerId] = 0
                table.insert(self.InternalState.UpdateLoop, playerId)
            end
            
            local playerState = self.InternalState.PlayerStates[playerId]
            
            if self.InternalState.Cooldowns[playerId] > currentTime then
                return false
            end

            self.InternalState.Cooldowns[playerId] = currentTime + Config.TimeBetweenShots
            
            -- Check shot cooldown
            if currentTime - playerState.LastShotTime < Config.TimeBetweenShots then
                return false
            end
            
            -- Check burst cooldown
            if self.InternalState.BurstCooldowns[playerId] > currentTime then
                return false
            end
            
            -- Check reload cooldown
            if self.InternalState.AbilityCooldowns[playerId] > currentTime then
                return false
            end
            
            -- Check if burst is empty
            if playerState.BurstAmount <= 0 then
                self.InternalState.BurstCooldowns[playerId] = currentTime + Config.TimeBetweenBursts
                return false
            end
            
            -- Check if out of ammo
            if playerState.Ammo <= 0 then
                self.InternalState.AbilityCooldowns[playerId] = currentTime + Config.Cooldown
                return false
            end
            
            -- Fire the shot
            playerState.Ammo -= 1
            playerState.BurstAmount -= 1
            playerState.LastShotTime = currentTime
            
            warn(`Server M1: Burst {playerState.BurstAmount}/{Config.BurstAmount}, Ammo {playerState.Ammo}/{Config.Ammo}`)
            
            return true
        end,

        OnUpdate = function(self, dt)         
            for _, playerId in ipairs(self.InternalState.UpdateLoop) do
                local playerState = self.InternalState.PlayerStates[playerId]
                if playerState then
                    local currentTime = os.clock()
                    
                    -- Reset burst amount when burst cooldown is up
                    local burstCooldown = self.InternalState.BurstCooldowns[playerId]
                    if burstCooldown and burstCooldown > 0 and burstCooldown <= currentTime then
                        if playerState.BurstAmount <= 0 then
                            playerState.BurstAmount = Config.BurstAmount
                            self.InternalState.BurstCooldowns[playerId] = 0
                            warn(`Burst reset for player {playerId}`)
                        end
                    end
                    
                    -- Reset ammo when reload cooldown is up
                    local reloadCooldown = self.InternalState.AbilityCooldowns[playerId]
                    if reloadCooldown and reloadCooldown > 0 and reloadCooldown <= currentTime then
                        if playerState.Ammo <= 0 then
                            playerState.Ammo = Config.Ammo
                            playerState.BurstAmount = Config.BurstAmount -- Also reset burst on reload
                            self.InternalState.AbilityCooldowns[playerId] = 0
                            warn(`Ammo reloaded for player {playerId}`)
                        end
                    end
                end
            end
            return true
        end,
    }
}

return Ability
