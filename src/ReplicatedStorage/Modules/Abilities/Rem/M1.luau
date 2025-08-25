local Types = require(game.ReplicatedStorage.Modules.Types.AbilityTypes)

local Config = {
    AnimationName = "M1",
    Range = 100,
    Enum = Enum.UserInputType.MouseButton1
}

local Ability : Types.AbilityModule = {
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
        Validate = function(self, player)
            
            return true
        end
    }
}

return Ability
