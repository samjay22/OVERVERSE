--!strict
--[[
	Debug utilities for mouse targeting system
	Handles raycast visualization and logging
	
	@author: GitHub Copilot
	@version: 1.0.0
]]

--// Modules \\--
local MouseTargetTypes = require(game.ReplicatedStorage.Modules.Types.MouseTargetTypes)
type DebugConfig = MouseTargetTypes.DebugConfig

--// Types \\--
export type DebugManager = {
	updateRaycastVisual: (self: DebugManager, raycastResult: RaycastResult?, ray: Ray) -> (),
	log: (self: DebugManager, message: string) -> (),
	destroy: (self: DebugManager) -> (),
	_config: DebugConfig,
	_raycastPart: Part?,
}

--// Module \\--
local DebugManager = {}
DebugManager.__index = DebugManager

--[[
	Creates a new debug manager instance
	
	@param config - Configuration for debug features
	@return DebugManager - New debug manager instance
]]
function DebugManager.new(config: DebugConfig): DebugManager
	local self = setmetatable({}, DebugManager) :: any
	
	self._config = config
	self._raycastPart = nil
	
	-- Create raycast visualization part if enabled
	if config.enabled and config.raycastVisualization then
		local raycastPart = Instance.new("Part")
		raycastPart.Name = "RaycastDebug"
		raycastPart.Material = Enum.Material.Neon
		raycastPart.BrickColor = BrickColor.new("Bright red")
		raycastPart.CanCollide = false
		raycastPart.Anchored = true
		raycastPart.Size = Vector3.new(0.1, 0.1, 1)
		raycastPart.Parent = workspace
		
		self._raycastPart = raycastPart
	end
	
	return self
end

--[[
	Updates the visual representation of the raycast
	
	@param raycastResult - The result of the raycast, if any
	@param ray - The ray that was cast
]]
function DebugManager:updateRaycastVisual(raycastResult: RaycastResult?, ray: Ray): ()
	if not self._config.enabled or not self._config.raycastVisualization or not self._raycastPart then
		return
	end
	
	if raycastResult then
		-- Show ray from origin to hit point
		local startPos = ray.Origin
		local endPos = raycastResult.Position
		local distance = (endPos - startPos).Magnitude
		
		self._raycastPart.Size = Vector3.new(0.1, 0.1, distance)
		self._raycastPart.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -distance/2)
		self._raycastPart.Transparency = 0
	else
		-- Show ray extending into distance
		local startPos = ray.Origin
		local endPos = startPos + (ray.Direction * 100)
		
		self._raycastPart.Size = Vector3.new(0.1, 0.1, 100)
		self._raycastPart.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -50)
		self._raycastPart.Transparency = 0.9
	end
end

--[[
	Logs a debug message if logging is enabled
	
	@param message - The message to log
]]
function DebugManager:log(message: string): ()
	if self._config.enabled and self._config.logging then
		print(`[MouseTarget] {message}`)
	end
end

--[[
	Destroys the debug manager and cleans up resources
]]
function DebugManager:destroy(): ()
	if self._raycastPart then
		self._raycastPart:Destroy()
		self._raycastPart = nil :: any
	end
end

return DebugManager
