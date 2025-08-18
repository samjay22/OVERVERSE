--!strict
--[[
	Mouse Target Controller
	A clean, modular system for handling mouse-based target selection
	
	@author: GitHub Copilot
	@version: 1.0.0
]]

--// Services \\--
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

--// Modules \\--
local MouseTargetTypes = require(game.ReplicatedStorage.Modules.Types.MouseTargetTypes)
local MouseTargetConfig = require(game.ReplicatedStorage.Modules.Utility.MouseTargetConfig)
local TargetValidator = require(game.ReplicatedStorage.Modules.Utility.TargetValidator)
local HighlightManager = require(game.ReplicatedStorage.Modules.Utility.HighlightManager)
local DebugManager = require(game.ReplicatedStorage.Modules.Utility.DebugManager)
local Constants = require(game.ReplicatedStorage.Modules.Utility.Constants)

--// Types \\--
type MouseTargetConfig = MouseTargetTypes.MouseTargetConfig
type TargetChangedCallback = MouseTargetTypes.TargetChangedCallback

export type MouseTargetController = {
	getCurrentTarget: (self: MouseTargetController) -> Model?,
	onTargetChanged: (self: MouseTargetController, callback: TargetChangedCallback) -> () -> (),
	setConfig: (self: MouseTargetController, config: MouseTargetConfig) -> (),
	start: (self: MouseTargetController) -> (),
	stop: (self: MouseTargetController) -> (),
	destroy: (self: MouseTargetController) -> (),
	
	_config: MouseTargetConfig,
	_player: Player,
	_camera: Camera,
	_mouse: Mouse,
	_currentTarget: Model?,
	_currentTargetValue: ObjectValue,
	_highlightManager: any, -- HighlightManager type
	_debugManager: any, -- DebugManager type
	_callbacks: {TargetChangedCallback},
	_connection: RBXScriptConnection?,
	_running: boolean,
}

--// Module \\--
local MouseTargetController = {}
MouseTargetController.__index = MouseTargetController

--[[
	Creates a new mouse target controller instance
	
	@param config - Optional configuration override
	@return MouseTargetController - New controller instance
]]
function MouseTargetController.new(config: MouseTargetConfig?): MouseTargetController
	local self = setmetatable({}, MouseTargetController) :: any
	
	self._config = config or MouseTargetConfig
	self._player = Players.LocalPlayer
	self._camera = workspace.CurrentCamera
	self._mouse = self._player:GetMouse()
	self._currentTarget = nil
	self._callbacks = {}
	self._connection = nil
	self._running = false
	
	-- Create current target value for other scripts
	local currentTargetValue = Instance.new("ObjectValue")
	currentTargetValue.Name = "CurrentTarget"
	currentTargetValue.Value = nil
	currentTargetValue.Parent = self._player
	self._currentTargetValue = currentTargetValue
	
	-- Initialize managers
	self._highlightManager = HighlightManager.new(self._config.highlight)
	self._debugManager = DebugManager.new(self._config.debug)
	
	return self
end

--[[
	Gets the currently targeted model
	
	@return Model? - The current target, or nil if none
]]
function MouseTargetController:getCurrentTarget(): Model?
	return self._currentTarget
end

--[[
	Registers a callback for when the target changes
	
	@param callback - Function to call when target changes
	@return function - Disconnect function to remove the callback
]]
function MouseTargetController:onTargetChanged(callback: TargetChangedCallback): () -> ()
	table.insert(self._callbacks, callback)
	
	return function()
		local index = table.find(self._callbacks, callback)
		if index then
			table.remove(self._callbacks, index)
		end
	end
end

--[[
	Updates the configuration
	
	@param config - New configuration to apply
]]
function MouseTargetController:setConfig(config: MouseTargetConfig): ()
	self._config = config
	-- Recreate managers with new config
	self._highlightManager:destroy()
	self._debugManager:destroy()
	self._highlightManager = HighlightManager.new(config.highlight)
	self._debugManager = DebugManager.new(config.debug)
end

--[[
	Starts the mouse targeting system
]]
function MouseTargetController:start(): ()
	if self._running then
		return
	end
	
	self._running = true
	self._debugManager:log("Starting mouse targeting system")
	
	-- Bind to render step for smooth updates
	self._connection = RunService.Heartbeat:Connect(function()
		self:_updateTarget()
	end)
end

--[[
	Stops the mouse targeting system
]]
function MouseTargetController:stop(): ()
	if not self._running then
		return
	end
	
	self._running = false
	self._debugManager:log("Stopping mouse targeting system")
	
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil :: any
	end
	
	-- Clear current target
	self:_setCurrentTarget(nil)
end

--[[
	Destroys the controller and cleans up all resources
]]
function MouseTargetController:destroy(): ()
	self:stop()
	
	-- Clean up managers
	self._highlightManager:destroy()
	self._debugManager:destroy()
	
	-- Clean up target value
	if self._currentTargetValue then
		self._currentTargetValue:Destroy()
	end
	
	-- Clear callbacks
	self._callbacks = {}
end

--[[
	Creates a raycast from the mouse position
	
	@return RaycastResult? - The raycast result, if any
]]
function MouseTargetController:_createMouseRaycast(): RaycastResult?
    if not self._player.Character then
        return nil
    end

    -- Set up raycast parameters
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = self._config.raycast.filterType
    raycastParams.IgnoreWater = self._config.raycast.ignoreWater
    raycastParams.FilterDescendantsInstances = { self._player.Character }

    -- Get mouse position and create world ray
    local mousePos = UserInputService:GetMouseLocation()
    local unitRay : Ray = (self._camera :: Camera):ViewportPointToRay(mousePos.X, mousePos.Y)

    -- Step 1: Find the target point in the world from the camera
    local cameraRaycast = workspace:Raycast(unitRay.Origin, unitRay.Direction * self._config.raycast.maxDistance, raycastParams)
    local targetPoint = cameraRaycast and cameraRaycast.Position or (unitRay.Origin + unitRay.Direction * self._config.raycast.maxDistance)

    -- Step 2: Cast from the character's head toward the target point
    local head : Part = self._player.Character:FindFirstChild("Head") :: any
    if not head then
        return nil
    end
    
    -- Use the same origin point for both direction calculation and raycast
    local rayOrigin = head.Position
    local direction = (targetPoint - rayOrigin).Unit * self._config.raycast.maxDistance

    return workspace:Raycast(rayOrigin, direction, raycastParams)
end


--[[
	Updates the current target based on mouse raycast
]]
function MouseTargetController:_updateTarget(): ()
	local raycastResult = self:_createMouseRaycast()
	
	-- Update debug visualization
	if raycastResult then
		local mousePos = UserInputService:GetMouseLocation()
		local unitRay = self._camera:ScreenPointToRay(mousePos.X, mousePos.Y)
		self._debugManager:updateRaycastVisual(raycastResult, unitRay)
	end
	
	local hitPart = raycastResult and raycastResult.Instance
	local newTarget = TargetValidator.getTargetableModelFromHit(hitPart, self._player)
	
	-- Check if current target was destroyed
	if self._currentTarget and not self._currentTarget:IsDescendantOf(game) then
		newTarget = nil
	end
	
	-- Update target if it changed
	local currentTarget: Model? = self._currentTarget
	if newTarget ~= currentTarget then
		self:_setCurrentTarget(newTarget)
	end
end

--[[
	Sets the current target and triggers callbacks
	
	@param newTarget - The new target model, or nil to clear
]]
function MouseTargetController:_setCurrentTarget(newTarget: Model?): ()
	local oldTarget = self._currentTarget
	self._currentTarget = newTarget
	self._currentTargetValue.Value = newTarget
	
	-- Update highlight
	self._highlightManager:setTarget(newTarget)
	
	-- Log target change
	if newTarget then
		self._debugManager:log(`Targeting: {newTarget.Name}`)
	else
		self._debugManager:log("No target")
	end
	
	-- Fire callbacks
	for _, callback in ipairs(self._callbacks) do
		task.spawn(callback, newTarget, oldTarget)
	end
end

return MouseTargetController
