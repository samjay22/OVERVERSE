local RunService : RunService  = game:GetService("RunService")
local UIS : UserInputService = game:GetService("UserInputService")
local CollectionService : CollectionService = game:GetService("CollectionService")

local Player : Player = game.Players.LocalPlayer
local Camera : Camera = workspace.CurrentCamera

local CharacterStates = {
    [Enum.KeyCode.W] = "Walk",
    [Enum.KeyCode.A] = "Walk",
    [Enum.KeyCode.S] = "Walk",
    [Enum.KeyCode.D] = "Walk",
}

local NextAnimation : AnimationTrack?
local CurrentAnimation : AnimationTrack?
local CurrentKeyState : string?

-- Optimization/state caches
local ANIM_TAG = tostring(Player.UserId) .. "_Animations"

local pressed: {[Enum.KeyCode]: true} = {}
local trackCache: {[string]: AnimationTrack} = {}

local currentCharacter: Model?
local currentHumanoid: Humanoid?
local currentAnimator: Animator?
local currentAnimFolder: Instance?
local lastDesired: string?

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
    track.Looped = true
    track.Priority = Enum.AnimationPriority.Movement
    trackCache[name] = track
    return track
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

    -- Decide desired state
    local hasInput = next(pressed) ~= nil
    local isMoving = humanoid.MoveDirection.Magnitude > 0.05
    local desired = (hasInput or isMoving) and "Walk" or "Idle"
    if desired == lastDesired and CurrentAnimation and CurrentAnimation.IsPlaying then
        return
    end
    lastDesired = desired

    local nextTrack = getTrack(desired)
    if not nextTrack then return end
    NextAnimation = nextTrack

    if CurrentAnimation and CurrentAnimation ~= NextAnimation then
        pcall(function() CurrentAnimation:Stop(0.15) end)
    end

    CurrentAnimation = NextAnimation
    if not CurrentAnimation.IsPlaying then
        pcall(function() CurrentAnimation:Play(0.15, 1.0, 1.0) end)
    end
end)

UIS.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
    if gameProcessedEvent then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local state = CharacterStates[input.KeyCode]
        if state then
            pressed[input.KeyCode] = true
            CurrentKeyState = state
        end
    end
end)

UIS.InputEnded:Connect(function(input: InputObject, gameProcessedEvent: boolean)
    if gameProcessedEvent then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if CharacterStates[input.KeyCode] then
            pressed[input.KeyCode] = nil
            if next(pressed) == nil then
                CurrentKeyState = nil
            end
        end
    end
end)