local Types = require(game.ReplicatedStorage.Modules.Types.AbilityTypes)

local Config = {
    AnimationName = "E",
    Range = 100,
    BurstAmount = 3,
    TimeBetweenBursts = 0.5,
    Cooldown = 5,
    Ammo = 12,
    Enum = Enum.KeyCode.E
}

local Ability : Types.AbilityModule = {
    Name = "E",
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
            local animations = self:GetCharacterAnimations(player)
            if not animations then
                return false
            end

            local animation = animations:FindFirstChild(Config.AnimationName)
            if not animation then
                return false
            end

            local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            if not humanoid then
                return false
            end

            local animationTrack : AnimationTrack = humanoid:LoadAnimation(animation)
            table.insert(self.InternalState.Animations, animationTrack)

            animationTrack.KeyframeReached:Connect(function(keyframeName)
                print(keyframeName)
            end)
            
            animationTrack.Looped = false
            animationTrack:Play()
            animationTrack.Stopped:Wait()
            
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
            if not self.InternalState.AbilityCooldowns[player.UserId] then
                self.InternalState.AbilityCooldowns[player.UserId] = 0
            end

            if not self.InternalState.BurstCooldowns[player.UserId] then
                self.InternalState.BurstCooldowns[player.UserId] = 0
            end

            if not self.InternalState.PlayerStates[player.UserId] then
                self.InternalState.PlayerStates[player.UserId] = {
                    Ammo = Config.Ammo,
                    BurstAmount = Config.BurstAmount,
                    LastAttack = 0,
                }
                table.insert(self.InternalState.UpdateLoop, player.UserId)
            end

            --Overall ability cooldown
            if self.InternalState.AbilityCooldowns[player.UserId] > os.clock() then
                return false
            end

            --Burst cooldown
            if self.InternalState.BurstCooldowns[player.UserId] > os.clock() then
                return false
            end

            --Trigger cooldown on burst runout
            if self.InternalState.PlayerStates[player.UserId].BurstAmount <= 0 then
                self.InternalState.BurstCooldowns[player.UserId] = os.clock() + Config.TimeBetweenBursts
                return false
            end

            --When out of ammo, we need to reload
            if self.InternalState.PlayerStates[player.UserId].Ammo <= 0 then
                self.InternalState.AbilityCooldowns[player.UserId] = os.clock() + Config.Cooldown
                return false
            end
            

            self.InternalState.PlayerStates[player.UserId].Ammo -= 1
            self.InternalState.PlayerStates[player.UserId].BurstAmount -= 1

            return true
        end,

        OnUpdate = function(self, dt)         
            for _, playerId in ipairs(self.InternalState.UpdateLoop) do
                local playerState = self.InternalState.PlayerStates[playerId]
                if playerState then
                    -- Reset burst amount when burst cooldown is up
                    if self.InternalState.BurstCooldowns[playerId] and self.InternalState.BurstCooldowns[playerId] <= os.clock() then
                        playerState.BurstAmount = Config.BurstAmount
                        self.InternalState.BurstCooldowns[playerId] = 0
                    end
                    
                    -- Reset ammo when ability cooldown is up
                    if self.InternalState.AbilityCooldowns[playerId] and self.InternalState.AbilityCooldowns[playerId] <= os.clock() then
                        playerState.Ammo = Config.Ammo
                        self.InternalState.AbilityCooldowns[playerId] = 0
                    end
                end
            end
            return true
        end,
    }
}

return Ability
