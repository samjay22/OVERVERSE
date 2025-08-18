--!strict
-- Client Ability ability module implementing the static interface
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

local Player : Player = game.Players.LocalPlayer

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

-- Configuration constants
local ABILITY_CLASS = "Rem"
local ANIMATION_NAME = "M1"
local COOLDOWN_TIME = 1.6
local ANIM_FADE_TIME = 0.05
local ANIM_PRIORITY = Enum.AnimationPriority.Action

local Ability = {}

function Ability.onRequest(ctx: SharedAbilityContext): AbilityResult
    return {
        success = true,
        cooldowns = { [tostring(ctx.abilityId)] = ctx.timestamp + COOLDOWN_TIME },
    }
end

-- Helper function to find and play animations
local function playCharacterAnimation(animName: string): AnimationTrack?
    -- Find animation
    local animTag = tostring(Player.UserId) .. "_Animations"
    local animFolder = CollectionService:GetTagged(animTag)[1]
    local anim = animFolder and animFolder:FindFirstChild(animName)
    
    -- Find animator
    local character = Player.Character
    if not character then return nil end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end
    
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not (anim and animator) then return nil end
    
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
        for _, conn in connections do
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
    
    -- Play animation
    track:Play(ANIM_FADE_TIME, 1, 1)
    
    return track
end

local function attackTarget()
    local player = Players.LocalPlayer
    local targetKey = player:GetAttribute("targetKey")
    local target = CollectionService:GetTagged(targetKey)[1]
    if not target then 
        warn("No target")
        return
    end

    local effectsFolder = player.Character and player.Character:FindFirstChild("Effects")
    if not effectsFolder then
        warn("No Effects folder in character")
        return
    end

    local effect = effectsFolder:FindFirstChild("M1")
    if not effect then
        warn("No M1 effect found")
        return
    end

    local effectclone = effect:Clone()
    Debris:AddItem(effectclone, 1) -- Clean up effect after 2 seconds

    effectclone.Parent = target.PrimaryPart
end

function Ability.onCast(ctx: SharedAbilityContext, serverData: any?)
    task.spawn(attackTarget)
    task.spawn(playCharacterAnimation, ANIMATION_NAME)
end

function Ability.OnCancel(ctx: SharedAbilityContext, reason: string?)
    -- Implementation if needed
end

function Ability.getAbilityInputRequired()
    return Enum.UserInputType.MouseButton1
end

function Ability.getAbilityClassId()
    return ABILITY_CLASS
end

return Ability
