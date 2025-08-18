--!strict
-- Client Ability ability module implementing the static interface
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

local Player : Player = game.Players.LocalPlayer

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

local Ability: any = {}

function Ability.onRequest(ctx: SharedAbilityContext): AbilityResult
    return {
        success = true,
        cooldowns = { [tostring(ctx.abilityId)] = ctx.timestamp + 1.6 },
    }
end

function Ability.onCast(ctx: SharedAbilityContext, serverData: any?)
    -- Find the M1 animation
    local tagged = CollectionService:GetTagged(tostring(Player.UserId) .. "_Animations")
    local animFolder: Instance? = if #tagged > 0 then tagged[1] else nil
    local anim: Animation? = animFolder and animFolder:FindFirstChild("M1") :: Animation?

    -- Find the animator
    local character = Player.Character
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
    if not humanoid then return end

    local animator: Animator? = humanoid:FindFirstChildOfClass("Animator") :: Animator?
    if not (anim and animator) then return end

    -- Load and play as a one-shot, even if the asset is looped
    local track: AnimationTrack = animator:LoadAnimation(anim)
    track.Priority = Enum.AnimationPriority.Action

    -- If already playing due to a prior cast, restart cleanly
    if track.IsPlaying then
        track:Stop(0.05)
    end

    -- Force single run
    pcall(function()
        track.Looped = false
    end)

    -- Safety: if the asset still loops for any reason, stop after the first loop
    local didLoopConn: RBXScriptConnection? = nil
    didLoopConn = track.DidLoop:Connect(function()
        track:Stop(0.05)
        if didLoopConn then
            didLoopConn:Disconnect()
            didLoopConn = nil
        end
    end)

    -- Cleanup connections when the track stops
    local stoppedConn: RBXScriptConnection? = nil
    stoppedConn = track.Stopped:Connect(function()
        if didLoopConn then
            didLoopConn:Disconnect()
            didLoopConn = nil
        end
        if stoppedConn then
            stoppedConn:Disconnect()
            stoppedConn = nil
        end
    end)

    -- Smooth start
    track:Play(0.05, 1, 1)
end

function Ability.OnCancel(ctx: SharedAbilityContext, reason: string?)
end

function Ability.getAbilityInputRequired()
    return Enum.UserInputType.MouseButton1
end

function Ability.getAbilityClassId()
    return "Rem"
end

return Ability
