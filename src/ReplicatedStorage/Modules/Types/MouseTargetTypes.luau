--!strict
--[[
	Types for mouse targeting system
	
	@author: GitHub Copilot
	@version: 1.0.0
]]

export type TargetHighlightConfig = {
	fillColor: Color3,
	outlineColor: Color3,
	fillTransparency: number,
	outlineTransparency: number,
	glowDuration: number,
	glowIntensity: number,
}

export type RaycastConfig = {
	maxDistance: number,
	ignoreWater: boolean,
	filterType: Enum.RaycastFilterType,
}

export type DebugConfig = {
	enabled: boolean,
	raycastVisualization: boolean,
	logging: boolean,
}

export type MouseTargetConfig = {
	highlight: TargetHighlightConfig,
	raycast: RaycastConfig,
	debug: DebugConfig,
}

export type TargetChangedCallback = (newTarget: Model?, oldTarget: Model?) -> ()

return {}
