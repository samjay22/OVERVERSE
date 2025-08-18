--!strict
--[[
	Highlight manager for mouse targeting system
	Handles target highlighting and glow effects
	
	@author: GitHub Copilot
	@version: 1.0.0
]]

--// Services \\--
local TweenService = game:GetService("TweenService")

--// Modules \\--
local MouseTargetTypes = require(game.ReplicatedStorage.Modules.Types.MouseTargetTypes)
type TargetHighlightConfig = MouseTargetTypes.TargetHighlightConfig

--// Types \\--
export type HighlightManager = {
	setTarget: (self: HighlightManager, model: Model?) -> (),
	destroy: (self: HighlightManager) -> (),
	_highlight: Highlight,
	_glowTween: Tween?,
	_config: TargetHighlightConfig,
	_startGlow: (self: HighlightManager) -> (),
	_stopGlow: (self: HighlightManager) -> (),
}

--// Module \\--
local HighlightManager = {}
HighlightManager.__index = HighlightManager

--[[
	Creates a new highlight manager instance
	
	@param config - Configuration for the highlight appearance
	@return HighlightManager - New highlight manager instance
]]
function HighlightManager.new(config: TargetHighlightConfig): HighlightManager
	local self = setmetatable({}, HighlightManager) :: any
	
	self._config = config
	self._glowTween = nil
	
	-- Create single reusable highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "TargetHighlight"
	highlight.FillColor = config.fillColor
	highlight.OutlineColor = config.outlineColor
	highlight.FillTransparency = config.fillTransparency
	highlight.OutlineTransparency = config.outlineTransparency
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = workspace
	
	self._highlight = highlight
	
	return self
end

--[[
	Sets the current target for highlighting
	
	@param model - The model to highlight, or nil to clear highlight
]]
function HighlightManager:setTarget(model: Model?): ()
	if model and model.Parent then
		self._highlight.Adornee = model
		self._highlight.Enabled = true
		self:_startGlow()
	else
		self._highlight.Adornee = nil :: any -- Type cast for clearing
		self._highlight.Enabled = false
		self:_stopGlow()
	end
end

--[[
	Starts the glow animation effect
]]
function HighlightManager:_startGlow(): ()
	-- Stop any existing tween
	if self._glowTween then 
		self._glowTween:Cancel() 
	end
	
	-- Reset to initial state
	self._highlight.OutlineTransparency = self._config.outlineTransparency
	self._highlight.FillTransparency = self._config.fillTransparency

	-- Create pulsing animation
	local tweenInfo = TweenInfo.new(
		self._config.glowDuration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1, -- repeat forever
		true, -- reverse
		0
	)

	self._glowTween = TweenService:Create(self._highlight, tweenInfo, {
		OutlineTransparency = self._config.glowIntensity,
		FillTransparency = math.max(0, (self._config :: any).fillTransparency - 0.15),
	})
	
	if self._glowTween then
		self._glowTween:Play()
	end
end

--[[
	Stops the glow animation effect
]]
function HighlightManager:_stopGlow(): ()
	if self._glowTween then
		self._glowTween:Cancel()
		self._glowTween = nil :: any
	end
end

--[[
	Destroys the highlight manager and cleans up resources
]]
function HighlightManager:destroy(): ()
	self:_stopGlow()
	if self._highlight then
		self._highlight:Destroy()
	end
end

return HighlightManager
