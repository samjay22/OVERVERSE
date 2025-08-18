--[[
    MovementAnimationHandler.client.luau
    
    A comprehensive animation system that handles:
    - Character locomotion animations (idle, walk, jump, etc.)
    - Animation overlays and exclusive animations
    - Input handling for movement detection
    - External animation control via bindable events
    
    Author: Rewritten for improved performance and maintainability
    Date: August 17, 2025
--]]

-- Services
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

-- Dependencies
local BindableEventHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utility"):WaitForChild("BindableEventHelper"))

-- Check for shift lock state
local ShiftLockState = ReplicatedStorage:WaitForChild("ShiftLockState")

-- Constants
local Player = Players.LocalPlayer
local ANIM_TAG = tostring(Player.UserId) .. "_Animations"
local DEFAULT_FADE_TIME = 0.15
local MOVEMENT_THRESHOLD = 0.1
local JUMP_HEIGHT_THRESHOLD = 0.5

-- Movement key mappings
local MOVEMENT_KEYS = {
    [Enum.KeyCode.W] = "Walk",
    [Enum.KeyCode.A] = "Walk", 
    [Enum.KeyCode.S] = "BackWalk",
    [Enum.KeyCode.D] = "Walk",
    [Enum.KeyCode.Space] = "Jump",
}

-- Default locomotion animation mappings
local LOCOMOTION_ANIMATIONS = {
    Idle = "Idle",
    Walk = "Walk", 
    BackWalk = "BackWalk",
    Jump = "Jump",
    Fall = "Fall",
}

-- Type definitions
type ChannelConfig = {
    priority: Enum.AnimationPriority?,
    defaultFade: number?,
    defaultWeight: number?,
}

type PlayRequest = {
    animationName: string,
    priority: Enum.AnimationPriority?,
    fade: number?,
    looped: boolean?,
    speed: number?,
    weight: number?,
    overlay: boolean?,
    mode: string?,
    channel: string?,
}

type AnimationState = {
    current: AnimationTrack?,
    override: AnimationTrack?,
    overlays: { [string]: AnimationTrack },
    lastDesired: string?,
    lastMoveVector: Vector3?,
    lastStateChange: number?,
}

-- Animation system class
local MovementAnimationHandler = {}
MovementAnimationHandler.__index = MovementAnimationHandler

function MovementAnimationHandler.new()
    local self = setmetatable({}, MovementAnimationHandler)
    
    -- State
    self.character = nil
    self.humanoid = nil
    self.animator = nil
    self.humanoidRootPart = nil
    self.animationFolder = nil
    self.isReady = false
    
    -- Animation state
    self.state = {
        current = nil,
        override = nil,
        overlays = {},
        lastDesired = nil,
        lastMoveVector = Vector3.new(),
        lastStateChange = 0, -- Track when state last changed for stability
    } :: AnimationState
    
    -- Input tracking
    self.pressedKeys = {}
    
    -- Animation caching
    self.trackCache = {}
    self.connections = {}
    self.overlayConnections = {}
    self.characterConnections = {}
    
    -- Movement tracking
    self.lastPosition = nil
    self.velocity = Vector3.new()
    
    -- Configuration
    self.channelConfigs = {
        default = {
            priority = Enum.AnimationPriority.Action,
            defaultFade = DEFAULT_FADE_TIME,
            defaultWeight = 1.0,
        },
    }
    
    -- Initialize
    self:_initialize()
    
    return self
end

function MovementAnimationHandler:_initialize()
    -- Setup character tracking
    if Player.Character then
        self:_onCharacterAdded(Player.Character)
    end
    
    Player.CharacterAdded:Connect(function(character)
        self:_onCharacterAdded(character)
    end)
    
    Player.CharacterRemoving:Connect(function()
        self:_onCharacterAdded(nil)
    end)
    
    -- Setup input handling
    self:_setupInputHandling()
    
    -- Setup bindable events
    self:_setupBindableEvents()
    
    -- Start animation loop
    self:_startAnimationLoop()
    
    -- Setup animation folder monitoring
    self:_setupAnimationFolderMonitoring()
    
    print("MovementAnimationHandler: Initialized")
end

function MovementAnimationHandler:_onCharacterAdded(character: Model?)
    if character == self.character then return end
    
    -- Clean up previous character
    self:_cleanup()
    
    -- Setup new character
    self.character = character
    if not character then 
        self.isReady = false
        return 
    end
    
    -- Wait for required components
    task.spawn(function()
        local humanoid = character:WaitForChild("Humanoid", 10)
        local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 10)
        
        if not humanoid or not humanoidRootPart then
            warn("MovementAnimationHandler: Failed to find required character components")
            return
        end
        
        self.humanoid = humanoid
        self.humanoidRootPart = humanoidRootPart
        self.lastPosition = humanoidRootPart.Position
        
        self:_setupAnimator(humanoid)
        self:_setupCharacterConnections()
        self:_checkAnimationFolder()
        
        -- Handle character removal
        self.characterConnections[#self.characterConnections + 1] = character.AncestryChanged:Connect(function()
            if not character.Parent then
                self:_onCharacterAdded(nil)
            end
        end)
        
        -- Replace default animations
        self:_replaceDefaultAnimations()
    end)
end

function MovementAnimationHandler:_setupAnimator(humanoid: Humanoid)
    -- Wait for or create animator
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Name = "Animator"
        animator.Parent = humanoid
        task.wait() -- Let the animator initialize
    end
    self.animator = animator
end

function MovementAnimationHandler:_setupCharacterConnections()
    if not self.humanoid then return end
    
    -- Clear existing connections
    for _, connection in ipairs(self.characterConnections) do
        if connection.Connected then
            connection:Disconnect()
        end
    end
    self.characterConnections = {}
    
    -- Track movement changes with aggressive debouncing to prevent rotation interference
    local lastMoveUpdate = 0
    local lastMoveDirection = Vector3.new()
    self.characterConnections[#self.characterConnections + 1] = self.humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
        local now = tick()
        local currentMoveDirection = self.humanoid.MoveDirection
        
        -- Check if this is a significant movement change, not just rotation-induced fluctuation
        local magnitudeChange = math.abs(currentMoveDirection.Magnitude - lastMoveDirection.Magnitude)
        local isSignificantChange = magnitudeChange > 0.1
        
        -- Only update if enough time has passed AND it's a significant change
        if (now - lastMoveUpdate > 0.1) and (isSignificantChange or currentMoveDirection.Magnitude < 0.05) then
            lastMoveUpdate = now
            lastMoveDirection = currentMoveDirection
            
            -- Small delay to let movement settle after rotation
            task.wait(0.05)
            self:_updateLocomotion()
        end
    end)
    
    -- Track jump state - more immediate response needed
    self.characterConnections[#self.characterConnections + 1] = self.humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
        -- Immediate update for jump responsiveness
        self:_updateLocomotion()
    end)
    
    -- Track state changes - this is crucial for jump/fall detection
    self.characterConnections[#self.characterConnections + 1] = self.humanoid.StateChanged:Connect(function(oldState, newState)
        -- Immediate update for state changes, especially jumping/falling
        self:_updateLocomotion()
        
        -- Additional update after a brief delay to catch velocity changes
        task.wait(0.05)
        self:_updateLocomotion()
    end)
    
    -- Track humanoid died state
    self.characterConnections[#self.characterConnections + 1] = self.humanoid.Died:Connect(function()
        self:_cleanup()
    end)
end

function MovementAnimationHandler:_replaceDefaultAnimations()
    if not self.humanoid then return end
    
    -- Remove default Roblox animations
    local function removeDefaultAnimations()
        local animate = self.character:FindFirstChild("Animate")
        if animate then
            animate:Destroy()
        end
        
        -- Stop any existing animations
        for _, track in pairs(self.humanoid:GetPlayingAnimationTracks()) do
            track:Stop(0)
        end
    end
    
    removeDefaultAnimations()
end

function MovementAnimationHandler:_setupAnimationFolderMonitoring()
    -- Monitor for animation folder changes
    local function onTagged(instance)
        self.animationFolder = instance
        self:_checkAnimationFolder()
    end
    
    local function onUntagged(instance)
        if instance == self.animationFolder then
            self.animationFolder = nil
            self.isReady = false
        end
    end

    -- Prefer tag-specific signals for correctness
    CollectionService:GetInstanceAddedSignal(ANIM_TAG):Connect(onTagged)
    CollectionService:GetInstanceRemovedSignal(ANIM_TAG):Connect(onUntagged)
    
    -- Check existing tagged instances
    for _, instance in ipairs(CollectionService:GetTagged(ANIM_TAG)) do
        onTagged(instance)
    end
end

function MovementAnimationHandler:_checkAnimationFolder()
    self.animationFolder = CollectionService:GetTagged(ANIM_TAG)[1]
    if self.animationFolder and #self.animationFolder:GetChildren() > 0 then
        self.isReady = true
        print("MovementAnimationHandler: Animation folder ready with", #self.animationFolder:GetChildren(), "animations")
    else
        self.isReady = false
        if not self.animationFolder then
            warn("MovementAnimationHandler: No animation folder found with tag:", ANIM_TAG)
        else
            warn("MovementAnimationHandler: Animation folder is empty")
        end
    end
end

function MovementAnimationHandler:_cleanup()
    -- Stop all animations
    for _, track in pairs(self.trackCache) do
        if track and track.IsPlaying then
            track:Stop(0)
        end
        if track then
            track:Destroy()
        end
    end
    
    -- Clear connections
    for _, connection in pairs(self.connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    for _, connection in pairs(self.overlayConnections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    for _, connection in ipairs(self.characterConnections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    -- Reset state
    self.trackCache = {}
    self.connections = {}
    self.overlayConnections = {}
    self.characterConnections = {}
    self.state = {
        current = nil,
        override = nil,
        overlays = {},
        lastDesired = nil,
        lastMoveVector = Vector3.new(),
        lastStateChange = 0,
    }
    self.isReady = false
    self.lastPosition = nil
    self.velocity = Vector3.new()
end

function MovementAnimationHandler:_getAnimationTrack(animationName: string): AnimationTrack?
    -- Check cache first
    if self.trackCache[animationName] then
        local track = self.trackCache[animationName]
        if track and track.Parent then
            return track
        else
            -- Clean up invalid cache entry
            self.trackCache[animationName] = nil
        end
    end
    
    -- Validate requirements
    if not self.animator or not self.animationFolder then
        return nil
    end
    
    -- Find animation
    local animationObject = self.animationFolder:FindFirstChild(animationName)
    if not animationObject or not animationObject:IsA("Animation") then
        warn("MovementAnimationHandler: Animation not found:", animationName)
        return nil
    end
    
    -- Load and cache track
    local success, track = pcall(function()
        return self.animator:LoadAnimation(animationObject)
    end)
    
    if not success or not track then
        warn("MovementAnimationHandler: Failed to load animation:", animationName)
        return nil
    end
    
    self.trackCache[animationName] = track
    return track
end

function MovementAnimationHandler:_applyTrackProperties(track: AnimationTrack, request: PlayRequest)
    if request.priority then
        track.Priority = request.priority
    end
    
    if request.looped ~= nil then
        track.Looped = request.looped
    end
    
    -- Apply speed and weight after starting if needed
    if request.speed and track.IsPlaying then
        track:AdjustSpeed(request.speed)
    end
    
    if request.weight and track.IsPlaying then
        track:AdjustWeight(request.weight, request.fade or DEFAULT_FADE_TIME)
    end
end

function MovementAnimationHandler:_playExclusiveAnimation(request: PlayRequest)
    local track = self:_getAnimationTrack(request.animationName)
    if not track then return end
    
    -- Set default priority for exclusive animations
    if not request.priority then
        track.Priority = Enum.AnimationPriority.Action
    end
    
    local fadeTime = request.fade or DEFAULT_FADE_TIME
    
    -- Stop current animations
    if self.state.current and self.state.current ~= track and self.state.current.IsPlaying then
        self.state.current:Stop(fadeTime)
    end
    
    if self.state.override and self.state.override ~= track and self.state.override.IsPlaying then
        self.state.override:Stop(fadeTime)
    end
    
    -- Apply properties before playing
    self:_applyTrackProperties(track, request)
    
    -- Play new animation
    self.state.override = track
    self.state.current = track
    
    if not track.IsPlaying then
        local weight = request.weight or 1.0
        local speed = request.speed or 1.0
        track:Play(fadeTime, weight, speed)
    end
    
    -- Setup stopped connection
    if not self.connections[track] then
        self.connections[track] = track.Stopped:Connect(function()
            if self.state.override == track then
                self.state.override = nil
            end
            
            -- Clean up connection
            local connection = self.connections[track]
            if connection and connection.Connected then
                connection:Disconnect()
            end
            self.connections[track] = nil
        end)
    end
end

function MovementAnimationHandler:_playOverlayAnimation(request: PlayRequest)
    local track = self:_getAnimationTrack(request.animationName)
    if not track then return end
    
    local channel = request.channel or "default"
    local config = self.channelConfigs[channel] or self.channelConfigs.default
    
    -- Set channel-specific priority
    if not request.priority then
        track.Priority = config.priority or Enum.AnimationPriority.Action
    end
    
    local fadeTime = request.fade or config.defaultFade or DEFAULT_FADE_TIME
    
    -- Stop previous overlay in this channel
    local previousTrack = self.state.overlays[channel]
    if previousTrack and previousTrack ~= track and previousTrack.IsPlaying then
        previousTrack:Stop(fadeTime)
    end
    
    -- Apply properties before playing
    self:_applyTrackProperties(track, request)
    
    -- Play new overlay
    self.state.overlays[channel] = track
    
    if not track.IsPlaying then
        local weight = request.weight or config.defaultWeight or 1.0
        local speed = request.speed or 1.0
        track:Play(fadeTime, weight, speed)
    end
    
    -- Setup stopped connection
    if not self.overlayConnections[track] then
        self.overlayConnections[track] = track.Stopped:Connect(function()
            -- Remove from overlays
            for ch, tr in pairs(self.state.overlays) do
                if tr == track then
                    self.state.overlays[ch] = nil
                    break
                end
            end
            
            -- Clean up connection
            local connection = self.overlayConnections[track]
            if connection and connection.Connected then
                connection:Disconnect()
            end
            self.overlayConnections[track] = nil
        end)
    end
end

function MovementAnimationHandler:_updateVelocity()
    if not self.humanoidRootPart then return end
    
    -- Use actual velocity from the part instead of calculating from position
    self.velocity = self.humanoidRootPart.AssemblyLinearVelocity or self.humanoidRootPart.Velocity
end

function MovementAnimationHandler:_determineDesiredState(): string
    if not self.humanoid then
        return "Idle"
    end
    
    -- Update velocity tracking
    self:_updateVelocity()
    
    local hasInput = next(self.pressedKeys) ~= nil
    local moveDirection = self.humanoid.MoveDirection
    local humanoidState = self.humanoid:GetState()
    local yVelocity = self.velocity.Y
    
    -- Check if shift lock is active to adjust movement detection
    local isShiftLocked = ShiftLockState.Value ~= false
    
    -- When shift locked, use a more stable movement threshold and rely more on input
    local movementThreshold = MOVEMENT_THRESHOLD
    if isShiftLocked then
        -- During rotation (mouse movement), MoveDirection can fluctuate even when not actually moving
        -- So we use a slightly higher threshold and prioritize input detection
        movementThreshold = MOVEMENT_THRESHOLD * 1.2
    end
    
    local isActuallyMoving = moveDirection.Magnitude > movementThreshold
    
    -- Prioritize jump/fall states based on humanoid state first, then velocity
    if humanoidState == Enum.HumanoidStateType.Jumping then
        return "Jump"
    elseif humanoidState == Enum.HumanoidStateType.Freefall then
        -- Use velocity to distinguish between upward momentum and falling
        if yVelocity > JUMP_HEIGHT_THRESHOLD then
            return "Jump" -- Still going up from a jump
        else
            return "Fall" -- Actually falling down
        end
    elseif humanoidState == Enum.HumanoidStateType.Flying or humanoidState == Enum.HumanoidStateType.FallingDown then
        return "Fall"
    end
    
    -- Only check for ground-based movement if we're in a grounded state
    if humanoidState == Enum.HumanoidStateType.Running or 
       humanoidState == Enum.HumanoidStateType.RunningNoPhysics or
       humanoidState == Enum.HumanoidStateType.None or
       (humanoidState == Enum.HumanoidStateType.Landed and yVelocity < JUMP_HEIGHT_THRESHOLD) then
        
        -- When shift locked, prioritize input over movement direction to avoid rotation interference
        if isShiftLocked and hasInput then
            -- Use input-based detection when shift locked to avoid rotation interference
            local isBackWalking = self.pressedKeys[Enum.KeyCode.S] and not self.pressedKeys[Enum.KeyCode.W]
            return isBackWalking and "BackWalk" or "Walk"
        elseif isActuallyMoving then
            -- Normal movement detection when not shift locked or when no input but moving
            local isBackWalking = self.pressedKeys[Enum.KeyCode.S] and not self.pressedKeys[Enum.KeyCode.W]
            return isBackWalking and "BackWalk" or "Walk"
        elseif hasInput and not isShiftLocked then
            -- If we have input but no movement (like turning in place) when not shift locked
            local isBackWalking = self.pressedKeys[Enum.KeyCode.S] and not self.pressedKeys[Enum.KeyCode.W]
            return isBackWalking and "BackWalk" or "Walk"
        else
            return "Idle"
        end
    end
    
    -- Default fallback
    return "Idle"
end

function MovementAnimationHandler:_updateLocomotion()
    -- Don't run if not ready
    if not self.isReady or not self.humanoid or not self.animator then
        return
    end
    
    -- Check if override is still playing
    if self.state.override and self.state.override.IsPlaying then
        self.state.current = self.state.override
        return
    end
    
    -- Clear finished override
    if self.state.override and not self.state.override.IsPlaying then
        self.state.override = nil
    end
    
    -- Determine desired state
    local desiredState = self:_determineDesiredState()
    
    -- Store current move vector for comparison
    local currentMoveVector = self.humanoid.MoveDirection
    self.state.lastMoveVector = self.state.lastMoveVector or Vector3.new()
    
    -- More sensitive change detection for jump/fall states
    local isJumpFallState = desiredState == "Jump" or desiredState == "Fall"
    local wasJumpFallState = self.state.lastDesired == "Jump" or self.state.lastDesired == "Fall"
    
    -- Add extra stability for walk animations to prevent rotation interference
    local isWalkState = desiredState == "Walk" or desiredState == "BackWalk"
    local wasWalkState = self.state.lastDesired == "Walk" or self.state.lastDesired == "BackWalk"
    
    -- For walk states, require a more significant change to prevent rotation interference
    local significantMoveChange = (currentMoveVector - self.state.lastMoveVector).Magnitude > 0.3
    local stateChanged = desiredState ~= self.state.lastDesired
    
    -- Special handling for walk animations - be more conservative about changes
    local shouldChange = false
    local now = tick()
    local timeSinceLastChange = now - (self.state.lastStateChange or 0)
    
    if isJumpFallState or wasJumpFallState then
        -- Always update for jump/fall transitions
        shouldChange = true
    elseif not self.state.current or not self.state.current.IsPlaying then
        -- Always update if no current animation
        shouldChange = true
    elseif stateChanged then
        -- State changed - add minimum time between walk state changes for stability
        if isWalkState and wasWalkState and timeSinceLastChange < 0.15 then
            -- Recent walk state change - ignore to prevent rotation interference
            shouldChange = false
        elseif isWalkState and wasWalkState then
            -- Walk to walk transition (like Walk to BackWalk) after enough time
            shouldChange = true
        elseif not isWalkState or not wasWalkState then
            -- Non-walk transitions - normal handling
            shouldChange = true
        else
            -- Walk state changes - require more stability
            shouldChange = significantMoveChange
        end
    elseif significantMoveChange and not isWalkState then
        -- Significant movement change for non-walk states
        shouldChange = true
    end
    
    if not shouldChange then
        return
    end
    
    -- Update state change time
    if stateChanged then
        self.state.lastStateChange = now
    end
    
    self.state.lastDesired = desiredState
    self.state.lastMoveVector = currentMoveVector
    
    -- Get animation name
    local animationName = LOCOMOTION_ANIMATIONS[desiredState] or desiredState
    local track = self:_getAnimationTrack(animationName)
    if not track then 
        return 
    end
    
    -- Configure track based on state
    if desiredState == "Jump" then
        track.Looped = false
        track.Priority = Enum.AnimationPriority.Action
    elseif desiredState == "Fall" then
        track.Looped = true
        track.Priority = Enum.AnimationPriority.Action
    else
        track.Looped = true
        track.Priority = Enum.AnimationPriority.Movement
    end
    
    -- Stop current and play new with appropriate fade times
    local fadeTime = DEFAULT_FADE_TIME
    if isJumpFallState then
        fadeTime = 0.05 -- Faster transitions for jump/fall
    elseif desiredState == "Walk" or desiredState == "BackWalk" then
        fadeTime = 0.08 -- Slightly faster transitions for walking to improve responsiveness
    end
    
    if self.state.current and self.state.current ~= track and self.state.current.IsPlaying then
        self.state.current:Stop(fadeTime)
    end
    
    self.state.current = track
    
    if not track.IsPlaying then
        track:Play(fadeTime, 1.0, 1.0)
    end
end

function MovementAnimationHandler:_setupInputHandling()
    local function isTyping(): boolean
        return UserInputService:GetFocusedTextBox() ~= nil
    end
    
    UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if gameProcessed or isTyping() then return end
        
        local keyCode = input.KeyCode
        if MOVEMENT_KEYS[keyCode] then
            self.pressedKeys[keyCode] = true
            -- Immediate update for better responsiveness
            self:_updateLocomotion()
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input: InputObject, gameProcessed: boolean)
        if gameProcessed then return end
        
        local keyCode = input.KeyCode
        if MOVEMENT_KEYS[keyCode] then
            self.pressedKeys[keyCode] = nil
            -- Immediate update for better responsiveness
            self:_updateLocomotion()
        end
    end)
    
    UserInputService.WindowFocusReleased:Connect(function()
        -- Clear all pressed keys when window loses focus
        self.pressedKeys = {}
        self:_updateLocomotion()
    end)
end

function MovementAnimationHandler:_startAnimationLoop()
    -- Use RenderStepped for better responsiveness
    RunService.RenderStepped:Connect(function()
        -- Check animation folder readiness
        if not self.isReady then
            self:_checkAnimationFolder()
            return
        end
        
        -- Update locomotion
        self:_updateLocomotion()
    end)
end

function MovementAnimationHandler:_setupBindableEvents()
    -- Main play event
    BindableEventHelper.CreateBindableEvent("MovementAnimation:Play").Event:Connect(function(request)
        self:playAnimation(request)
    end)
    
    -- Control event
    BindableEventHelper.CreateBindableEvent("MovementAnimation:Control").Event:Connect(function(request)
        self:controlAnimation(request)
    end)
    
    -- Configuration event
    BindableEventHelper.CreateBindableEvent("MovementAnimation:Configure").Event:Connect(function(config)
        self:configure(config)
    end)
    
    -- Backward compatibility events
    BindableEventHelper.CreateBindableEvent("PlayAnimation").Event:Connect(function(request)
        self:playAnimation(request)
    end)
    
    BindableEventHelper.CreateBindableEvent("ControlAnimation").Event:Connect(function(request)
        self:controlAnimation(request)
    end)
    
    BindableEventHelper.CreateBindableEvent("ConfigureAnimation").Event:Connect(function(config)
        self:configure(config)
    end)
end

-- Public API
function MovementAnimationHandler:playAnimation(request: PlayRequest)
    if not request or not request.animationName then
        warn("MovementAnimationHandler: Invalid play request")
        return
    end
    
    local isOverlay = request.overlay == true or request.mode == "overlay"
    
    if isOverlay then
        self:_playOverlayAnimation(request)
    else
        self:_playExclusiveAnimation(request)
    end
end

function MovementAnimationHandler:controlAnimation(request: { action: string, channel: string?, fade: number? })
    local action = string.lower(request.action or "")
    local fadeTime = request.fade or DEFAULT_FADE_TIME
    
    if action == "stop" then
        if request.channel then
            self:stopOverlay(request.channel, fadeTime)
        else
            self:stopExclusive(fadeTime)
        end
    elseif action == "stopoverlay" then
        self:stopOverlay(request.channel, fadeTime)
    elseif action == "stopexclusive" then
        self:stopExclusive(fadeTime)
    elseif action == "stopall" then
        self:stopAll(fadeTime)
    end
end

function MovementAnimationHandler:stopExclusive(fadeTime: number?)
    local fade = fadeTime or DEFAULT_FADE_TIME
    
    if self.state.override and self.state.override.IsPlaying then
        self.state.override:Stop(fade)
    end
    
    self.state.override = nil
end

function MovementAnimationHandler:stopOverlay(channel: string?, fadeTime: number?)
    local fade = fadeTime or DEFAULT_FADE_TIME
    
    if channel then
        local track = self.state.overlays[channel]
        if track and track.IsPlaying then
            track:Stop(fade)
        end
        self.state.overlays[channel] = nil
    else
        -- Stop all overlays
        for ch, track in pairs(self.state.overlays) do
            if track and track.IsPlaying then
                track:Stop(fade)
            end
            self.state.overlays[ch] = nil
        end
    end
end

function MovementAnimationHandler:stopAll(fadeTime: number?)
    local fade = fadeTime or DEFAULT_FADE_TIME
    
    self:stopExclusive(fade)
    self:stopOverlay(nil, fade)
end

function MovementAnimationHandler:configure(config: {
    locomotion: { [string]: string }?,
    channels: { [string]: ChannelConfig }?
})
    if config.locomotion then
        for state, animationName in pairs(config.locomotion) do
            if type(state) == "string" and type(animationName) == "string" then
                LOCOMOTION_ANIMATIONS[state] = animationName
            end
        end
    end
    
    if config.channels then
        for name, channelConfig in pairs(config.channels) do
            if type(name) == "string" and type(channelConfig) == "table" then
                self.channelConfigs[name] = {
                    priority = channelConfig.priority or (self.channelConfigs[name] and self.channelConfigs[name].priority) or self.channelConfigs.default.priority,
                    defaultFade = channelConfig.defaultFade or (self.channelConfigs[name] and self.channelConfigs[name].defaultFade) or self.channelConfigs.default.defaultFade,
                    defaultWeight = channelConfig.defaultWeight or (self.channelConfigs[name] and self.channelConfigs[name].defaultWeight) or self.channelConfigs.default.defaultWeight,
                }
            end
        end
    end
end

-- Debug function
function MovementAnimationHandler:getDebugInfo()
    return {
        isReady = self.isReady,
        hasCharacter = self.character ~= nil,
        hasHumanoid = self.humanoid ~= nil,
        hasAnimator = self.animator ~= nil,
        hasAnimationFolder = self.animationFolder ~= nil,
        currentAnimation = self.state.current and self.state.current.Animation.Name or "None",
        overrideAnimation = self.state.override and self.state.override.Animation.Name or "None",
        lastDesired = self.state.lastDesired or "None",
        pressedKeys = self.pressedKeys,
        animationCount = self.animationFolder and #self.animationFolder:GetChildren() or 0,
    }
end

-- Initialize the system
local animationHandler = MovementAnimationHandler.new()

-- Export for debugging/external access
_G.MovementAnimationHandler = animationHandler

return animationHandler
