--[[
    Provides smooth shift lock functionality for the character camera system.
    Handles transitions, character rotation, and mouse behavior.
    
    @author: Zach
    @version: 1.0.0
]]

--// Services \\--
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Dependencies \\--
local SharedUtils = ReplicatedStorage.Modules.Utility
local Cleaner = require(SharedUtils.Cleaner)
local Spring = require(SharedUtils.Spring)

--// Constants \\--
local LocalPlayer = Players.LocalPlayer
local PlayerMouse = LocalPlayer:GetMouse()
local Camera = Workspace.CurrentCamera
local VECTOR3_ZERO = Vector3.new(0, 0, 0)
local CFrame_new = CFrame.new
local CFrame_Angles = CFrame.Angles

--// Types \\--
type ShiftLockConfig = {
    MOBILE_SUPPORT: boolean,
    SMOOTH_CHARACTER_ROTATION: boolean,
    CHARACTER_ROTATION_SPEED: number,
    TRANSITION_SPRING_DAMPER: number,
    CAMERA_TRANSITION_IN_SPEED: number,
    CAMERA_TRANSITION_OUT_SPEED: number,
    LOCKED_CAMERA_OFFSET: Vector3,
    LOCKED_MOUSE_ICON: string,
    SHIFT_LOCK_KEYBINDS: {Enum.KeyCode},
    AUTO_ENABLE: boolean,
    ALLOW_TOGGLE: boolean
}

type ShiftLockClass = {
    new: () -> ShiftLockClass,
    Enable: (self: ShiftLockClass) -> (),
    Disable: (self: ShiftLockClass) -> (),
    IsEnabled: (self: ShiftLockClass) -> boolean,
    ToggleShiftLock: (self: ShiftLockClass, Enable: boolean?) -> (),
    
    _refreshCharacterVariables: (self: ShiftLockClass) -> (),
    _doShiftLockSwitch: (self: ShiftLockClass, _: any, State: Enum.UserInputState) -> Enum.ContextActionResult,
    _updateMouseState: (self: ShiftLockClass) -> (),
    _updateMouseIcon: (self: ShiftLockClass) -> (),
    _transitionLockOffset: (self: ShiftLockClass) -> ()
}

--// Configuration \\--
local Config: ShiftLockConfig = table.freeze({
    MOBILE_SUPPORT = false,
    SMOOTH_CHARACTER_ROTATION = true,
    CHARACTER_ROTATION_SPEED = 4,
    TRANSITION_SPRING_DAMPER = 0.5,
    CAMERA_TRANSITION_IN_SPEED = 12,
    CAMERA_TRANSITION_OUT_SPEED = 12,
    LOCKED_CAMERA_OFFSET = Vector3.new(3, 0.25, 0),
    LOCKED_MOUSE_ICON = "rbxassetid://111111111",
    SHIFT_LOCK_KEYBINDS = {Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift},
    AUTO_ENABLE = true,
    ALLOW_TOGGLE = true
})

--// Module \\--
local ShiftLock = {} :: ShiftLockClass
ShiftLock.__index = ShiftLock

local ShiftLockState = Instance.new("BoolValue")
ShiftLockState.Name = "ShiftLockState"
ShiftLockState.Value = false
ShiftLockState.Parent = ReplicatedStorage

-------------------------
--// Private Methods \\--
-------------------------

--- Refreshes character-related variables when character changes
--- @return nil

function ShiftLock:_refreshCharacterVariables()
	self.Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	self.RootPart = self.Character:WaitForChild("HumanoidRootPart")
	self.Humanoid = self.Character:WaitForChild("Humanoid")
	self.Head = self.Character:WaitForChild("Head")
end


local function getAngleBetweenVectors(a, b)
	local dotProduct = a:Dot(b)
	local angleRadians = math.acos(dotProduct / (a.Magnitude * b.Magnitude))
	local angleDegrees = math.deg(angleRadians)
	return angleDegrees
end

function ShiftLock:_CheckTarget()
	local Lookvector= Camera.CFrame.LookVector
	local result = nil
	local lastsangle = nil
	
	for i ,v in Players:GetPlayers() do
		if v == LocalPlayer then continue end
		local directionv = (v.Character.Head.Position - Camera.CFrame.Position).Unit
		local angle = getAngleBetweenVectors(Lookvector, directionv)
		if angle < 100 then
			if lastsangle then
				if lastsangle> angle then
					result = v
					lastsangle = angle
				end
			else
				result = v
				lastsangle = angle
				
			end
		end
	end

	for i ,v in game.Workspace.World.Living.NPCs:GetChildren() do
		local directionv = (v.Head.Position - Camera.CFrame.Position).Unit
		local angle = getAngleBetweenVectors(Lookvector, directionv)
		if angle < 100 then
			if lastsangle then
				if lastsangle> angle then
					result = v
					lastsangle = angle
				end
			else
				result = v
				lastsangle = angle

			end
		end
	end
	print(result)
	self.Target = result
	return result
end


--- Handles the shift lock key press event
--- @param _ any
--- @param State Enum.UserInputState
--- @return Enum.ContextActionResult
function ShiftLock:_doShiftLockSwitch(_, State: Enum.UserInputState)
    if State ~= Enum.UserInputState.Begin then
        return Enum.ContextActionResult.Pass
    end

    if not Config.ALLOW_TOGGLE then
		if Config.AUTO_ENABLE and not self.Enabled then
            self:ToggleShiftLock(2)
        end
        return Enum.ContextActionResult.Sink
    end

    self:ToggleShiftLock()
    return Enum.ContextActionResult.Sink
end

function ShiftLock:_doLockSwitch(_, State: Enum.UserInputState)
	if State ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	if not Config.ALLOW_TOGGLE then
		if Config.AUTO_ENABLE and not self.Enabled then
			self:ToggleLock(2)
		end
		return Enum.ContextActionResult.Sink
	end
	local target = self:_CheckTarget()
	print(target)
	if not target then

		return Enum.ContextActionResult.Sink
	end
	warn(self.Enabled)
	self:ToggleLock()
	return Enum.ContextActionResult.Sink
end
--- Updates the mouse behavior based on shift lock state
--- @return nil
function ShiftLock:_updateMouseState()
    UserInputService.MouseBehavior = self.Enabled and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
end

--- Updates the mouse icon based on shift lock state
--- @return nil
function ShiftLock:_updateMouseIcon()
    PlayerMouse.Icon = self.Enabled and Config.LOCKED_MOUSE_ICON or ""
end

--- Transitions the camera offset using spring physics
--- @return nil
function ShiftLock:_transitionLockOffset()
    if self.Enabled == true then
        self._cameraOffsetSpring.Speed = Config.CAMERA_TRANSITION_IN_SPEED
		self._cameraOffsetSpring.Target = Config.LOCKED_CAMERA_OFFSET
	elseif self.Enabled == 2 then -- 2 means lock on target mode

		self._cameraOffsetSpring.Speed = Config.CAMERA_TRANSITION_IN_SPEED
		self._cameraOffsetSpring.Target = Vector3.new(3,2,10)
    else
        self._cameraOffsetSpring.Speed = Config.CAMERA_TRANSITION_OUT_SPEED
        self._cameraOffsetSpring.Target = VECTOR3_ZERO
    end
end

-------------------------
--// Public Methods \\--
-------------------------

--- Creates a new ShiftLock instance
-- @return ShiftLockClass
function ShiftLock.new()
    local self = setmetatable({}, ShiftLock)
    
    self._runtimeMaid = Cleaner.new()
    self._shiftlockMaid = Cleaner.new()
    self._cameraOffsetSpring = Spring.new(VECTOR3_ZERO)
    self._cameraOffsetSpring.Damper = Config.TRANSITION_SPRING_DAMPER
    
    self.Enabled = false
        
    return self
end

--- Enables the shift lock system
--- @return nil
function ShiftLock:Enable()
    self:_refreshCharacterVariables()
    
    if Config.AUTO_ENABLE then
        task.wait(0.1)
        self:ToggleShiftLock(true)
    end
    
    self._runtimeMaid:Connect(LocalPlayer.CharacterAdded, function()
        self:_refreshCharacterVariables()
        if Config.AUTO_ENABLE then
            task.wait(0.1)
            self:ToggleShiftLock(true)
        end
    end)

	ContextActionService:BindActionAtPriority(
		"LockSwitchAction",
		function(Name, State, Input) return self:_doLockSwitch(Name, State, Input) end,
		Config.MOBILE_SUPPORT,
		Enum.ContextActionPriority.Medium.Value,
		Enum.UserInputType.MouseButton3
	)
    ContextActionService:BindActionAtPriority(
        "ShiftLockSwitchAction",
        function(Name, State, Input) return self:_doShiftLockSwitch(Name, State, Input) end,
        Config.MOBILE_SUPPORT,
        Enum.ContextActionPriority.Medium.Value,
        unpack(Config.SHIFT_LOCK_KEYBINDS)
    )
    
    self._runtimeMaid:Connect(RunService.RenderStepped, function()
        if self.Head.LocalTransparencyModifier > 0.6 then return end
        local cameraCFrame = Camera.CFrame
        local distance = (self.Head.Position - cameraCFrame.Position).Magnitude
        
        if distance <= 1 then return end
		if self.Enabled == 2 then
			self.RootPart.CFrame = CFrame.new(self.RootPart.Position,self.Target.HumanoidRootPart.Position)

			Camera.CFrame = CFrame.lookAt(self.RootPart.CFrame * CFrame_new(Vector3.new(3,2,10)).Position,self.Target.HumanoidRootPart.Position)

		else
			Camera.CFrame = Camera.CFrame * CFrame_new(self._cameraOffsetSpring.Position)

		end

        if self.Enabled and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
            self:_updateMouseState()
        end
    end)
end

--- Disables the shift lock system
--- @return nil
function ShiftLock:Disable()
    self._runtimeMaid:Destroy()
    self._shiftlockMaid:Destroy()
    ContextActionService:UnbindAction("ShiftLockSwitchAction")
end

--- Checks if shift lock is currently enabled
--- @return boolean
function ShiftLock:IsEnabled(): boolean
    return self.Enabled
end

--- Static function to get the current shift lock state
--- @return boolean
function ShiftLock.GetIsEnabled(): boolean
    return ShiftLockState.Value
end

--- Toggles the shift lock state
--- @param Enable boolean?
--- @return nil
function ShiftLock:ToggleShiftLock(Enable: boolean?)
    if Enable ~= nil then
		self.Enabled = Enable
    else
		self.Enabled = not self.Enabled
    end
    
    ShiftLockState.Value = self.Enabled
    
    self:_updateMouseState()
    self:_updateMouseIcon()
    self:_transitionLockOffset()
    
    if not self.Enabled then
        self.Humanoid.AutoRotate = true
        self._shiftlockMaid:Clear()
        return
    end
    
    self._shiftlockMaid:Connect(RunService.RenderStepped, function(Delta: number)
        if not self.Humanoid or not self.RootPart then return end
        
        self.Humanoid.AutoRotate = not self.Enabled
        
        if self.Humanoid.Sit then return end
        if Config.SMOOTH_CHARACTER_ROTATION then
            local _, y = Camera.CFrame:ToOrientation()
            self.RootPart.CFrame = self.RootPart.CFrame:Lerp(
                CFrame_new(self.RootPart.Position) * CFrame_Angles(0, y, 0),
                Delta * 5 * Config.CHARACTER_ROTATION_SPEED
            )
        else
            local _, y = Camera.CFrame:ToOrientation()
            self.RootPart.CFrame = CFrame_new(self.RootPart.Position) * CFrame_Angles(0, y, 0)
		end

    end)
end

function ShiftLock:ToggleLock(Enable)
	if self.Enabled ~= 2 then
		self.Enabled = 2
	else
		self.Enabled = false
	end

	ShiftLockState.Value = self.Enabled

	self:_updateMouseState()
	self:_updateMouseIcon()
	self:_transitionLockOffset()

	if not self.Enabled then
		self.Humanoid.AutoRotate = true
		self._shiftlockMaid:Clear()
		return
	end

	self._shiftlockMaid:Connect(RunService.RenderStepped, function(Delta: number)
		if not self.Humanoid or not self.RootPart then return end

		self.Humanoid.AutoRotate = not self.Enabled

		if self.Humanoid.Sit then return end

		if Config.SMOOTH_CHARACTER_ROTATION then
			local _, y = Camera.CFrame:ToOrientation()
			self.RootPart.CFrame = self.RootPart.CFrame:Lerp(
				CFrame_new(self.RootPart.Position) * CFrame_Angles(0, y, 0),
				Delta * 5 * Config.CHARACTER_ROTATION_SPEED
			)
		else
			local _, y = Camera.CFrame:ToOrientation()
			self.RootPart.CFrame = CFrame_new(self.RootPart.Position) * CFrame_Angles(0, y, 0)
		end
	end)
end

-------------------------
--// Module Export \\--
-------------------------
return ShiftLock.new()