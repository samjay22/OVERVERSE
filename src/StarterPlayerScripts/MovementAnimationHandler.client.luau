-- MovementAnimationHandler: combines locomotion animation driving and input handling
-- Replaces AnimationHelper.client.luau and UserInputHelper.luau

local RunService: RunService = game:GetService("RunService")
local CollectionService: CollectionService = game:GetService("CollectionService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService: UserInputService = game:GetService("UserInputService")

local BindableEventHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utility"):WaitForChild("BindableEventHelper"))

local Player: Player = game.Players.LocalPlayer

-- Keys that count as locomotion intent
local CharacterStates = {
    [Enum.KeyCode.W] = "Walk",
    [Enum.KeyCode.A] = "Walk",
    [Enum.KeyCode.S] = "BackWalk",
    [Enum.KeyCode.D] = "Walk",
    [Enum.KeyCode.Space] = "Jump",
}

-- Animation state
local NextAnimation: AnimationTrack?
local CurrentAnimation: AnimationTrack?

-- Optimization/state caches
local ANIM_TAG = tostring(Player.UserId) .. "_Animations"

local pressed: { [Enum.KeyCode]: true } = {}
local trackCache: { [string]: AnimationTrack } = {}

local currentCharacter: Model?
local currentHumanoid: Humanoid?
local currentAnimator: Animator?
local currentAnimFolder: Instance?
local lastDesired: string?

-- Central override state: when set, base movement/idle won’t take over
local OverrideTrack: AnimationTrack?
local trackStoppedConns: { [AnimationTrack]: RBXScriptConnection } = {}

-- Overlay ability layers (run on top of locomotion)
local overlayTracks: { [string]: AnimationTrack } = {}
local overlayStoppedConns: { [AnimationTrack]: RBXScriptConnection } = {}

-- Configurable locomotion animation names and overlay channel defaults
local LocomotionMap: { [string]: string } = {
    Idle = "Idle",
    Walk = "Walk",
}

type ChannelCfg = {
    priority: Enum.AnimationPriority?,
    defaultFade: number?,
    defaultWeight: number?,
}

local ChannelConfig: { [string]: ChannelCfg } = {
    default = { priority = Enum.AnimationPriority.Action, defaultFade = 0.15, defaultWeight = 1.0 },
}

type PlayRequest = {
    animationName: string,
    priority: Enum.AnimationPriority?,
    fade: number?,
    looped: boolean?,
    speed: number?,
    weight: number?,
    overlay: boolean?, -- true to play on top of locomotion
    mode: string?, -- "overlay" | "exclusive"
    channel: string?, -- overlays channel key (e.g. "UpperBody"); defaults to "default"
}

local function getAnimFolder(): Instance?
    if currentAnimFolder and currentAnimFolder.Parent ~= nil then
        return currentAnimFolder
    end
    local tagged = CollectionService:GetTagged(ANIM_TAG)
    currentAnimFolder = tagged and tagged[1] or nil
    return currentAnimFolder
end

local function ensureAnimator(humanoid: Humanoid): Animator?
    if currentAnimator and currentAnimator.Parent == humanoid then
        return currentAnimator
    end
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Name = "Animator"
        animator.Parent = humanoid
    end
    currentAnimator = animator
    return currentAnimator
end

local function clearTracks()
    for _, t in pairs(trackCache) do
        pcall(function()
            if t.IsPlaying then t:Stop(0) end
            t:Destroy()
        end)
    end
    trackCache = {}
    CurrentAnimation = nil
    NextAnimation = nil
    lastDesired = nil
    if OverrideTrack and OverrideTrack.IsPlaying then
        pcall(function() OverrideTrack:Stop(0) end)
    end
    OverrideTrack = nil
    for track, conn in pairs(trackStoppedConns) do
        if conn.Connected then conn:Disconnect() end
        trackStoppedConns[track] = nil
    end
    -- stop/clear overlays
    for ch, tr in pairs(overlayTracks) do
        pcall(function()
            if tr.IsPlaying then tr:Stop(0) end
        end)
        overlayTracks[ch] = nil
    end
    for track, conn in pairs(overlayStoppedConns) do
        if conn.Connected then conn:Disconnect() end
        overlayStoppedConns[track] = nil
    end
end

local function onCharacterChanged(newChar: Model?)
    if newChar == currentCharacter then return end
    currentCharacter = newChar
    currentHumanoid = nil
    currentAnimator = nil
    clearTracks()
end

local function resolveHumanoid(): Humanoid?
    local char = Player.Character
    if not char or not char:IsA("Model") then
        onCharacterChanged(nil)
        return nil
    end
    if char ~= currentCharacter then
        onCharacterChanged(char)
    end
    local h = char:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then
        currentHumanoid = nil
        currentAnimator = nil
        return nil
    end
    if h ~= currentHumanoid then
        currentHumanoid = h
        currentAnimator = nil
        clearTracks()
    end
    return currentHumanoid
end

local function getTrack(name: string): AnimationTrack?
    if trackCache[name] then
        return trackCache[name]
    end
    local humanoid = resolveHumanoid()
    if not humanoid then return nil end

    local animator = ensureAnimator(humanoid)
    if not animator then return nil end

    local folder = getAnimFolder()
    if not folder then return nil end

    local anim = folder:FindFirstChild(name)
    if not anim or not anim:IsA("Animation") then return nil end

    local track = animator:LoadAnimation(anim)
    -- Defaults; can be overridden per-play via event
    track.Looped = true
    track.Priority = Enum.AnimationPriority.Movement
    trackCache[name] = track
    return track
end

local function applyTrackProps(track: AnimationTrack, req: PlayRequest?)
    if not req then return end
    if req.priority then
        track.Priority = req.priority
    end
    if req.looped ~= nil then
        track.Looped = req.looped
    end
    if req.speed then
        pcall(function() track:AdjustSpeed(req.speed :: number) end)
    end
    if req.weight then
        pcall(function() track:AdjustWeight(req.weight :: number, req.fade or 0.0) end)
    end
end

local function ensureStoppedConn(track: AnimationTrack)
    if trackStoppedConns[track] then return end
    trackStoppedConns[track] = track.Stopped:Connect(function()
        if OverrideTrack == track then
            OverrideTrack = nil
        end
        local conn = trackStoppedConns[track]
        if conn and conn.Connected then conn:Disconnect() end
        trackStoppedConns[track] = nil
    end)
end

local function playOverride(req: PlayRequest)
    local name = req.animationName
    if not name or type(name) ~= "string" then return end
    local track = getTrack(name)
    if not track then return end

    applyTrackProps(track, req)
    local fade = req.fade or 0.15

    -- ensure exclusive actions override base by default
    if not req.priority then
        track.Priority = Enum.AnimationPriority.Action
    end

    if CurrentAnimation and CurrentAnimation ~= track and CurrentAnimation.IsPlaying then
        pcall(function() CurrentAnimation:Stop(fade) end)
    end
    if OverrideTrack and OverrideTrack ~= track and OverrideTrack.IsPlaying then
        pcall(function() OverrideTrack:Stop(fade) end)
    end

    OverrideTrack = track
    CurrentAnimation = track

    if not track.IsPlaying then
        -- Play(transitionTime, weight, speed)
        local weight = req.weight or 1.0
        local speed = req.speed or 1.0
        pcall(function() track:Play(fade, weight, speed) end)
    end

    ensureStoppedConn(track)
end

local function ensureOverlayStoppedConn(track: AnimationTrack, channel: string)
    if overlayStoppedConns[track] then return end
    overlayStoppedConns[track] = track.Stopped:Connect(function()
        -- remove from channel map when it ends
        for ch, tr in pairs(overlayTracks) do
            if tr == track then
                overlayTracks[ch] = nil
                break
            end
        end
        local conn = overlayStoppedConns[track]
        if conn and conn.Connected then conn:Disconnect() end
        overlayStoppedConns[track] = nil
    end)
end

local function playOverlay(req: PlayRequest)
    local name = req.animationName
    if not name or type(name) ~= "string" then return end
    local track = getTrack(name)
    if not track then return end

    -- overlays use channel-configured priority by default
    local channel = req.channel or "default"
    local cfg = ChannelConfig[channel] or ChannelConfig.default
    if req.priority then
        track.Priority = req.priority
    else
        track.Priority = cfg.priority or Enum.AnimationPriority.Action
    end
    applyTrackProps(track, req)

    local fade = req.fade or cfg.defaultFade or 0.15

    local prev = overlayTracks[channel]
    if prev and prev ~= track and prev.IsPlaying then
        pcall(function() prev:Stop(fade) end)
    end

    overlayTracks[channel] = track

    if not track.IsPlaying then
        local weight = req.weight or cfg.defaultWeight or 1.0
        local speed = req.speed or 1.0
        pcall(function() track:Play(fade, weight, speed) end)
    end

    ensureOverlayStoppedConn(track, channel)
end

-- Choose PreAnimation if present, else fall back to RenderStepped
local driveSignal = (RunService :: any).PreAnimation or RunService.RenderStepped

driveSignal:Connect(function()
    -- Custom character systems: always check Player.Character/Humanoid on tick
    local humanoid = resolveHumanoid()
    if not humanoid then
        if CurrentAnimation and CurrentAnimation.IsPlaying then
            CurrentAnimation:Stop(0.12)
        end
        return
    end

    -- If an override is active and still playing, keep it (exclusive actions)
    if OverrideTrack and OverrideTrack.IsPlaying then
        CurrentAnimation = OverrideTrack
        return
    end
    if OverrideTrack and not OverrideTrack.IsPlaying then
        OverrideTrack = nil
    end

    -- Decide desired base state
    local hasInput = next(pressed) ~= nil
    local isMoving = humanoid.MoveDirection.Magnitude > 0.05
    local desired = (hasInput or isMoving) and "Walk" or "Idle"
    if desired == lastDesired and CurrentAnimation and CurrentAnimation.IsPlaying then
        return
    end
    lastDesired = desired

    local animName = LocomotionMap[desired] or desired
    local nextTrack = getTrack(animName)
    if not nextTrack then return end
    -- Ensure base locomotion defaults
    nextTrack.Looped = true
    nextTrack.Priority = Enum.AnimationPriority.Movement

    NextAnimation = nextTrack

    if CurrentAnimation and CurrentAnimation ~= NextAnimation then
        pcall(function() CurrentAnimation:Stop(0.15) end)
    end

    CurrentAnimation = NextAnimation
    local cur = CurrentAnimation
    if cur and not cur.IsPlaying then
        pcall(function() cur:Play(0.15, 1.0, 1.0) end)
    end
end)

-- Movement-focused input handling; updates the pressed state used in locomotion
local function isTyping()
    return UserInputService:GetFocusedTextBox() ~= nil
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
    if gameProcessedEvent or isTyping() then return end
    local key = input.KeyCode
    if CharacterStates[key] then
        pressed[key] = true
    end
end)

UserInputService.InputEnded:Connect(function(input: InputObject, gameProcessedEvent: boolean)
    if gameProcessedEvent then return end
    local key = input.KeyCode
    if CharacterStates[key] then
        pressed[key] = nil
    end
end)

UserInputService.WindowFocusReleased:Connect(function()
    -- clear all pressed keys when focus is lost to avoid stuck movement state
    for k in pairs(pressed) do
        pressed[k] = nil
    end
end)

-- Movement-specific bindable API (non-generic names) with backward compatibility
local function handlePlay(reqTbl: { animationName: string, priority: Enum.AnimationPriority?, fade: number?, looped: boolean?, speed: number?, weight: number?, overlay: boolean?, mode: string?, channel: string? })
    local req: PlayRequest = {
        animationName = reqTbl.animationName,
        priority = reqTbl.priority,
        fade = reqTbl.fade,
        looped = reqTbl.looped,
        speed = reqTbl.speed,
        weight = reqTbl.weight,
        overlay = reqTbl.overlay,
        mode = reqTbl.mode,
        channel = reqTbl.channel,
    }
    local isOverlay = (req.overlay == true) or (req.mode == "overlay")
    if isOverlay then
        playOverlay(req)
    else
        playOverride(req)
    end
end

local function stopExclusive(fade: number?)
    local tr = OverrideTrack
    if tr and tr.IsPlaying then
        pcall(function() tr:Stop(fade or 0.15) end)
    end
    OverrideTrack = nil
end

local function stopOverlay(channel: string?, fade: number?)
    if channel then
        local tr = overlayTracks[channel]
        if tr and tr.IsPlaying then
            local chanCfg = ChannelConfig[channel] or ChannelConfig.default
            local resolvedFade = fade or (chanCfg and chanCfg.defaultFade) or 0.15
            pcall(function() tr:Stop(resolvedFade) end)
        end
        overlayTracks[channel] = nil
    else
        for ch, tr in pairs(overlayTracks) do
            if tr.IsPlaying then
                local cfg = ChannelConfig[ch] or ChannelConfig.default
                pcall(function() tr:Stop(fade or (cfg and cfg.defaultFade) or 0.15) end)
            end
            overlayTracks[ch] = nil
        end
    end
end

local function stopAll(fade: number?)
    stopExclusive(fade)
    stopOverlay(nil, fade)
end

-- Movement-specific events
BindableEventHelper.CreateBindableEvent("MovementAnimation:Play").Event:Connect(handlePlay)
BindableEventHelper.CreateBindableEvent("MovementAnimation:Control").Event:Connect(function(req: { action: string, channel: string?, fade: number? })
    local action = string.lower(req.action or "")
    if action == "stop" then
        if req.channel then
            stopOverlay(req.channel, req.fade)
        else
            stopExclusive(req.fade)
        end
    elseif action == "stopoverlay" then
        stopOverlay(req.channel, req.fade)
    elseif action == "stopexclusive" then
        stopExclusive(req.fade)
    elseif action == "stopall" then
        stopAll(req.fade)
    end
end)

BindableEventHelper.CreateBindableEvent("MovementAnimation:Configure").Event:Connect(function(cfg: { locomotion: { [string]: string }?, channels: { [string]: ChannelCfg }? })
    if cfg.locomotion then
        for k, v in pairs(cfg.locomotion) do
            if type(k) == "string" and type(v) == "string" then
                LocomotionMap[k] = v
            end
        end
    end
    if cfg.channels then
        for name, c in pairs(cfg.channels) do
            if type(name) == "string" and type(c) == "table" then
                ChannelConfig[name] = {
                    priority = c.priority or ChannelConfig[name] and ChannelConfig[name].priority or ChannelConfig.default.priority,
                    defaultFade = c.defaultFade or ChannelConfig[name] and ChannelConfig[name].defaultFade or ChannelConfig.default.defaultFade,
                    defaultWeight = c.defaultWeight or ChannelConfig[name] and ChannelConfig[name].defaultWeight or ChannelConfig.default.defaultWeight,
                }
            end
        end
    end
end)

-- Backward compatibility: still respond to old generic event names if used anywhere else
BindableEventHelper.CreateBindableEvent("PlayAnimation").Event:Connect(handlePlay)
BindableEventHelper.CreateBindableEvent("ControlAnimation").Event:Connect(function(req: { action: string, channel: string?, fade: number? })
    -- delegate to movement control (ensure event exists)
    BindableEventHelper.CreateBindableEvent("MovementAnimation:Control"):Fire(req)
end)
BindableEventHelper.CreateBindableEvent("ConfigureAnimation").Event:Connect(function(cfg)
    BindableEventHelper.CreateBindableEvent("MovementAnimation:Configure"):Fire(cfg)
end)
