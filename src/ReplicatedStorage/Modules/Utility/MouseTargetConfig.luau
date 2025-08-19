--!strict
--[[
	Configuration constants for mouse targeting system
	
	@author: GitHub Copilot
	@version: 1.0.0
]]

local MouseTargetTypes = require(game.ReplicatedStorage.Modules.Types.MouseTargetTypes)
type MouseTargetConfig = MouseTargetTypes.MouseTargetConfig

local MouseTargetConfig: MouseTargetConfig = {
	highlight = {
		fillColor = Color3.fromRGB(255, 64, 64),
		outlineColor = Color3.fromRGB(255, 0, 0),
		fillTransparency = 0.65,
		outlineTransparency = 0.12,
		glowDuration = 0.6,
		glowIntensity = 0.35,
	},
	
	raycast = {
		maxDistance = 1000,
		ignoreWater = true,
		filterType = Enum.RaycastFilterType.Include,
	},
	
	debug = {
		enabled = true, -- Set to true to enable debug features
		raycastVisualization = false,
		logging = true,
	},
}

return MouseTargetConfig
