--[[
    Enhanced Shift Lock Camera System
    Provides smooth shift lock functionality with target locking capabilities
    
    @author: Zach (Enhanced)
    @version: 2.0.0
]]

--// Services \\--
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--// Dependencies \\--
local SharedUtils = game.ReplicatedStorage.Modules.Utility
local Cleaner = require(SharedUtils.Cleaner)
local Spring = require(SharedUtils.Spring)
local Constants = require(SharedUtils.Constants)

--// Constants \\--
local LocalPlayer = Players.LocalPlayer
local PlayerMouse = LocalPlayer:GetMouse()
local Camera = Workspace.CurrentCamera

--// Optimized Constants \\--
local VECTOR3_ZERO = Vector3.zero
local CFrame_new = CFrame.new
local CFrame_Angles = CFrame.Angles
local math_rad = math.rad
local math_deg = math.deg
local math_acos = math.acos
local math_min = math.min
local math_max = math.max
local tick = tick

--// Enums \\--
local ShiftLockMode = {
    OFF = 0,
    SHIFT_LOCK = 1,
    TARGET_LOCK = 2
}

--// Types \\--
type ShiftLockConfig = {
    -- Core Settings
    MOBILE_SUPPORT: boolean,
    SMOOTH_CHARACTER_ROTATION: boolean,
    CHARACTER_ROTATION_SPEED: number,
    
    -- Transition Settings
    TRANSITION_SPRING_DAMPER: number,
    CAMERA_TRANSITION_IN_SPEED: number,
    CAMERA_TRANSITION_OUT_SPEED: number,
    
    -- Camera Settings
    LOCKED_CAMERA_OFFSET: Vector3,
    TARGET_LOCK_OFFSET: Vector3,
    LOCKED_MOUSE_ICON: string,
    
    -- Input Settings
    SHIFT_LOCK_KEYBINDS: {Enum.KeyCode},
    TARGET_LOCK_BUTTON: Enum.UserInputType,
    
    -- Behavior Settings
    AUTO_ENABLE: boolean,
    ALLOW_TOGGLE: boolean,
    MOVEMENT_ROTATION_DELAY: number,
    
    -- Target Lock Settings
    TARGET_LOCK_ENABLED: boolean,
    TARGET_LOCK_ANGLE_THRESHOLD: number,
    TARGET_LOCK_MAX_DISTANCE: number,
    TARGET_LOCK_SMOOTH_SPEED: number,
    TARGET_PRIORITY_PLAYERS: boolean,
    
    -- Performance Settings
    UPDATE_RATE: number,
    TARGET_SCAN_INTERVAL: number
}

--// Enhanced Configuration \\--
local Config: ShiftLockConfig = table.freeze({
    -- Core Settings
    MOBILE_SUPPORT = true,
    SMOOTH_CHARACTER_ROTATION = true,
    CHARACTER_ROTATION_SPEED = 4,
    
    -- Transition Settings
    TRANSITION_SPRING_DAMPER = 1,
    CAMERA_TRANSITION_IN_SPEED = 6,
    CAMERA_TRANSITION_OUT_SPEED = 6,
    
    -- Camera Settings
    LOCKED_CAMERA_OFFSET = Constants.SHIFT_LOCK_OFFSET or Vector3.new(2, 0, 0),
    TARGET_LOCK_OFFSET = Vector3.new(3, 2, 10),
    LOCKED_MOUSE_ICON = "rbxassetid://9126971632",
    
    -- Input Settings
    SHIFT_LOCK_KEYBINDS = {Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift},
    TARGET_LOCK_BUTTON = Enum.UserInputType.MouseButton3,
    
    -- Behavior Settings
    AUTO_ENABLE = true,
    ALLOW_TOGGLE = false,
    MOVEMENT_ROTATION_DELAY = 0,
    
    -- Target Lock Settings
    TARGET_LOCK_ENABLED = true,
    TARGET_LOCK_ANGLE_THRESHOLD = 45, -- Degrees
    TARGET_LOCK_MAX_DISTANCE = 100, -- Studs
    TARGET_LOCK_SMOOTH_SPEED = 8,
    TARGET_PRIORITY_PLAYERS = true,
    
    -- Performance Settings
    UPDATE_RATE = 1/120, -- 120 FPS
    TARGET_SCAN_INTERVAL = 0.05 -- Scan for targets every 50ms
})

--// Module \\--
local ShiftLock = {}
ShiftLock.__index = ShiftLock

-- State Management
local ShiftLockState = Instance.new("IntValue")
ShiftLockState.Name = "ShiftLockState"
ShiftLockState.Value = ShiftLockMode.OFF
ShiftLockState.Parent = ReplicatedStorage

-------------------------
--// Private Methods \\--
-------------------------

--- Optimized angle calculation between vectors
local function getAngleBetweenVectors(a: Vector3, b: Vector3): number
    local dot = a:Dot(b)
    local magnitudes = a.Magnitude * b.Magnitude
    if magnitudes == 0 then return 180 end
    
    local cosAngle = math_min(math_max(dot / magnitudes, -1), 1)
    return math_deg(math_acos(cosAngle))
end

--- Calculate priority score for target selection
local function calculateTargetPriority(target, distance: number, angle: number, isPlayer: boolean): number
    local score = 0
    
    -- Distance factor (closer = higher priority)
    score = score + (1 - (distance / Config.TARGET_LOCK_MAX_DISTANCE)) * 50
    
    -- Angle factor (more centered = higher priority)
    score = score + (1 - (angle / Config.TARGET_LOCK_ANGLE_THRESHOLD)) * 30
    
    -- Player priority bonus
    if isPlayer and Config.TARGET_PRIORITY_PLAYERS then
        score = score + 20
    end
    
    return score
end

--- Refreshes character-related variables
function ShiftLock:_refreshCharacterVariables()
    self.Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    self.RootPart = self.Character:WaitForChild("HumanoidRootPart")
    self.Humanoid = self.Character:WaitForChild("Humanoid")
    self.Head = self.Character:WaitForChild("Head")
    
    -- Reset state on character respawn
    if self.Mode ~= ShiftLockMode.OFF and Config.AUTO_ENABLE then
        task.wait(0.1)
        self:SetMode(ShiftLockMode.SHIFT_LOCK)
    end
end

--- Enhanced target finding with caching and optimization
function ShiftLock:_findBestTarget()
    if not self.RootPart then return nil end
    
    local cameraPosition = Camera.CFrame.Position
    local lookVector = Camera.CFrame.LookVector
    local candidates = {}
    
    -- Helper function to evaluate a potential target
    local function evaluateTarget(targetModel, isPlayer: boolean)
        local targetRoot = targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Head")
        if not targetRoot then return end
        
        local humanoid = targetModel:FindFirstChild("Humanoid")
        if humanoid and humanoid.Health <= 0 then return end
        
        local toTarget = targetRoot.Position - cameraPosition
        local distance = toTarget.Magnitude
        
        -- Skip if too far
        if distance > Config.TARGET_LOCK_MAX_DISTANCE then return end
        
        -- Calculate angle
        local angle = getAngleBetweenVectors(lookVector, toTarget.Unit)
        
        -- Skip if outside angle threshold
        if angle > Config.TARGET_LOCK_ANGLE_THRESHOLD then return end
        
        -- Calculate priority score
        local priority = calculateTargetPriority(targetModel, distance, angle, isPlayer)
        
        table.insert(candidates, {
            target = targetModel,
            distance = distance,
            angle = angle,
            priority = priority
        })
    end
    
    -- Scan players
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            evaluateTarget(player.Character, true)
        end
    end
    
    -- Scan NPCs (with error handling)
    local npcFolder = Workspace:FindFirstChild("World") and 
                     Workspace.World:FindFirstChild("Living") and 
                     Workspace.World.Living:FindFirstChild("NPCs")
    
    if npcFolder then
        for _, npc in ipairs(npcFolder:GetChildren()) do
            evaluateTarget(npc, false)
        end
    end
    
    -- Sort by priority and return best target
    if #candidates > 0 then
        table.sort(candidates, function(a, b)
            return a.priority > b.priority
        end)
        return candidates[1].target
    end
    
    return nil
end

--- Handle shift lock key press
function ShiftLock:_handleShiftLockInput(_, state: Enum.UserInputState)
    if state ~= Enum.UserInputState.Begin then
        return Enum.ContextActionResult.Pass
    end
    
    if not Config.ALLOW_TOGGLE and Config.AUTO_ENABLE and self.Mode == ShiftLockMode.OFF then
        self:SetMode(ShiftLockMode.SHIFT_LOCK)
    elseif Config.ALLOW_TOGGLE then
        self:ToggleShiftLock()
    end
    
    return Enum.ContextActionResult.Sink
end

--- Handle target lock input
function ShiftLock:_handleTargetLockInput(_, state: Enum.UserInputState)
    if state ~= Enum.UserInputState.Begin or not Config.TARGET_LOCK_ENABLED then
        return Enum.ContextActionResult.Pass
    end
    
    if self.Mode == ShiftLockMode.TARGET_LOCK then
        self:SetMode(ShiftLockMode.OFF)
    else
        local target = self:_findBestTarget()
        if target then
            self.CurrentTarget = target
            self:SetMode(ShiftLockMode.TARGET_LOCK)
        end
    end
    
    return Enum.ContextActionResult.Sink
end

--- Update mouse behavior
function ShiftLock:_updateMouseState()
    UserInputService.MouseBehavior = self.Mode ~= ShiftLockMode.OFF and 
                                    Enum.MouseBehavior.LockCenter or 
                                    Enum.MouseBehavior.Default
end

--- Update mouse icon
function ShiftLock:_updateMouseIcon()
    PlayerMouse.Icon = self.Mode ~= ShiftLockMode.OFF and Config.LOCKED_MOUSE_ICON or ""
end

--- Transition camera offset
function ShiftLock:_transitionCameraOffset()
    local targetOffset = VECTOR3_ZERO
    local transitionSpeed = Config.CAMERA_TRANSITION_OUT_SPEED
    
    if self.Mode == ShiftLockMode.SHIFT_LOCK then
        targetOffset = Config.LOCKED_CAMERA_OFFSET
        transitionSpeed = Config.CAMERA_TRANSITION_IN_SPEED
    elseif self.Mode == ShiftLockMode.TARGET_LOCK then
        targetOffset = Config.TARGET_LOCK_OFFSET
        transitionSpeed = Config.CAMERA_TRANSITION_IN_SPEED
    end
    
    self._cameraOffsetSpring.Speed = transitionSpeed
    self._cameraOffsetSpring.Target = targetOffset
end

--- Main update loop for camera and rotation
function ShiftLock:_updateCameraAndRotation(deltaTime: number)
    if not self.Head or self.Head.LocalTransparencyModifier > 0.6 then return end
    
    local distance = (self.Head.Position - Camera.CFrame.Position).Magnitude
    if distance <= 1 then return end
    
    -- Handle different modes
    if self.Mode == ShiftLockMode.TARGET_LOCK and self.CurrentTarget then
        local targetRoot = self.CurrentTarget:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            -- Smooth target rotation
            local targetLookAt = CFrame.lookAt(self.RootPart.Position, 
                                              Vector3.new(targetRoot.Position.X, self.RootPart.Position.Y, targetRoot.Position.Z))
            self.RootPart.CFrame = self.RootPart.CFrame:Lerp(targetLookAt, deltaTime * Config.TARGET_LOCK_SMOOTH_SPEED)
            
            -- Update camera for target lock
            local cameraOffset = self.RootPart.CFrame * CFrame_new(self._cameraOffsetSpring.Position)
            Camera.CFrame = CFrame.lookAt(cameraOffset.Position, targetRoot.Position)
        else
            -- Target lost, revert to shift lock
            self:SetMode(ShiftLockMode.SHIFT_LOCK)
        end
    else
        -- Standard shift lock camera offset
        Camera.CFrame = Camera.CFrame * CFrame_new(self._cameraOffsetSpring.Position)
    end
    
    -- Ensure mouse stays locked
    if self.Mode ~= ShiftLockMode.OFF and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
        self:_updateMouseState()
    end
end

--- Handle character rotation
function ShiftLock:_handleCharacterRotation(deltaTime: number)
    if not self.Humanoid or not self.RootPart or self.Mode == ShiftLockMode.OFF then
        return
    end
    
    self.Humanoid.AutoRotate = false
    
    if self.Humanoid.Sit then return end
    
    -- Skip rotation for target lock (handled separately)
    if self.Mode == ShiftLockMode.TARGET_LOCK then return end
    
    -- Movement tracking
    local currentMoveDirection = self.Humanoid.MoveDirection
    local isMoving = currentMoveDirection.Magnitude > 0.1
    local wasMoving = self._lastMoveDirection.Magnitude > 0.1
    
    if isMoving and not wasMoving then
        self._movementStartTime = tick()
    end
    
    local timeSinceMovementStart = tick() - self._movementStartTime
    
    -- Calculate rotation
    local _, y = Camera.CFrame:ToOrientation()
    local targetCFrame = CFrame_new(self.RootPart.Position) * CFrame_Angles(0, y, 0)
    
    if Config.SMOOTH_CHARACTER_ROTATION then
        local rotationSpeed = Config.CHARACTER_ROTATION_SPEED
        
        -- Adjust rotation speed based on movement
        if isMoving and timeSinceMovementStart < Config.MOVEMENT_ROTATION_DELAY then
            rotationSpeed = rotationSpeed * 0.2
        elseif isMoving then
            rotationSpeed = rotationSpeed * 0.6
        end
        
        local lerpAlpha = math_min(deltaTime * 5 * rotationSpeed, 1)
        self.RootPart.CFrame = self.RootPart.CFrame:Lerp(targetCFrame, lerpAlpha)
    else
        if not isMoving then
            self.RootPart.CFrame = targetCFrame
        end
    end
    
    self._lastMoveDirection = currentMoveDirection
end

-------------------------
--// Public Methods \\--
-------------------------

--- Create new ShiftLock instance
function ShiftLock.new()
    local self = setmetatable({}, ShiftLock)
    
    -- Maids for cleanup
    self._runtimeMaid = Cleaner.new()
    self._modeMaid = Cleaner.new()
    
    -- Spring for camera transitions
    self._cameraOffsetSpring = Spring.new(VECTOR3_ZERO)
    self._cameraOffsetSpring.Damper = Config.TRANSITION_SPRING_DAMPER
    
    -- State
    self.Mode = ShiftLockMode.OFF
    self.CurrentTarget = nil
    self._lastMoveDirection = VECTOR3_ZERO
    self._movementStartTime = 0
    self._lastTargetScan = 0
    
    return self
end

--- Enable the shift lock system
function ShiftLock:Enable()
    self:_refreshCharacterVariables()
    
    if Config.AUTO_ENABLE then
        task.wait(0.1)
        self:SetMode(ShiftLockMode.SHIFT_LOCK)
    end
    
    -- Character respawn handler
    self._runtimeMaid:Connect(LocalPlayer.CharacterAdded, function()
        self:_refreshCharacterVariables()
    end)
    
    -- Bind inputs
    ContextActionService:BindActionAtPriority(
        "ShiftLockSwitchAction",
        function(...) return self:_handleShiftLockInput(...) end,
        Config.MOBILE_SUPPORT,
        Enum.ContextActionPriority.Medium.Value,
        unpack(Config.SHIFT_LOCK_KEYBINDS)
    )
    
    if Config.TARGET_LOCK_ENABLED then
        ContextActionService:BindActionAtPriority(
            "TargetLockAction",
            function(...) return self:_handleTargetLockInput(...) end,
            Config.MOBILE_SUPPORT,
            Enum.ContextActionPriority.Medium.Value,
            Config.TARGET_LOCK_BUTTON
        )
    end
    
    -- Main update loop
    self._runtimeMaid:Connect(RunService.RenderStepped, function(deltaTime)
        self:_updateCameraAndRotation(deltaTime)
    end)
end

--- Disable the system
function ShiftLock:Disable()
    self:SetMode(ShiftLockMode.OFF)
    self._runtimeMaid:Destroy()
    self._modeMaid:Destroy()
    ContextActionService:UnbindAction("ShiftLockSwitchAction")
    ContextActionService:UnbindAction("TargetLockAction")
end

--- Set the lock mode
function ShiftLock:SetMode(mode: number)
    if self.Mode == mode then return end
    
    self.Mode = mode
    ShiftLockState.Value = mode
    
    self:_updateMouseState()
    self:_updateMouseIcon()
    self:_transitionCameraOffset()
    
    -- Clear mode-specific connections
    self._modeMaid:Clear()
    
    if mode == ShiftLockMode.OFF then
        if self.Humanoid then
            self.Humanoid.AutoRotate = true
        end
        self.CurrentTarget = nil
        self._lastMoveDirection = VECTOR3_ZERO
        self._movementStartTime = 0
    else
        -- Setup rotation handler
        self._modeMaid:Connect(RunService.RenderStepped, function(deltaTime)
            self:_handleCharacterRotation(deltaTime)
        end)
        
        -- Periodic target validation for target lock
        if mode == ShiftLockMode.TARGET_LOCK then
            self._modeMaid:Connect(RunService.Heartbeat, function()
                if tick() - self._lastTargetScan > Config.TARGET_SCAN_INTERVAL then
                    self._lastTargetScan = tick()
                    
                    -- Validate current target still exists
                    if self.CurrentTarget then
                        local humanoid = self.CurrentTarget:FindFirstChild("Humanoid")
                        if not humanoid or humanoid.Health <= 0 then
                            self:SetMode(ShiftLockMode.SHIFT_LOCK)
                        end
                    end
                end
            end)
        end
    end
end

--- Toggle shift lock
function ShiftLock:ToggleShiftLock()
    if self.Mode == ShiftLockMode.SHIFT_LOCK then
        self:SetMode(ShiftLockMode.OFF)
    else
        self:SetMode(ShiftLockMode.SHIFT_LOCK)
    end
end

--- Check if enabled
function ShiftLock:IsEnabled(): boolean
    return self.Mode ~= ShiftLockMode.OFF
end

--- Get current mode
function ShiftLock:GetMode(): number
    return self.Mode
end

--- Get the global shift lock state
function ShiftLock.GetGlobalState(): number
    return ShiftLockState.Value
end

-------------------------
--// Module Export \\--
-------------------------
return ShiftLock.new()