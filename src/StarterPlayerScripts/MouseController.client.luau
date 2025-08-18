--!strict
--[[
	Mouse Controller Client
	Simplified and clean mouse targeting system using the modular MouseTargetController
	
	@author: GitHub Copilot
	@version: 2.0.0
]]
local Players = game:GetService("Players")
local HTTPService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local targetKey = HTTPService:GenerateGUID()

--// Modules \\--
local MouseTargetController = require(game.ReplicatedStorage.Modules.Utility.MouseTargetController)
local MouseTargetConfig = require(game.ReplicatedStorage.Modules.Utility.MouseTargetConfig)

--// Create and configure the mouse target controller \\--
local config = MouseTargetConfig
-- Enable debug features if needed during development
-- config.debug.enabled = true
-- config.debug.raycastVisualization = true
-- config.debug.logging = true

local mouseController = MouseTargetController.new(config)

--// Set up target change callback \\--
mouseController:onTargetChanged(function(newTarget: Model?, oldTarget: Model?)
	if oldTarget then 
		CollectionService:RemoveTag(oldTarget, targetKey)
	end

	if newTarget then
		CollectionService:AddTag(newTarget, targetKey)
	end
end)

--// Start the targeting system \\--
mouseController:start()

--// Optional: Expose controller globally for other scripts \\--
-- You can access the current target via: mouseController:getCurrentTarget()
-- Or register callbacks via: mouseController:onTargetChanged(callback)
_G.MouseTargetController = mouseController
Players.LocalPlayer:SetAttribute("targetKey", targetKey)
