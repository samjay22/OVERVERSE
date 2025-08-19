--!strict
--[[
	Mouse Controller Client
	Simplified and clean mouse targeting system using the modular MouseTargetController
	
	@author: GitHub Copilot
	@version: 2.0.0
]]
--// Modules \\--
local MouseTargetController = require(game.ReplicatedStorage.Modules.Utility.MouseTargetController)
local MouseTargetConfig = require(game.ReplicatedStorage.Modules.Utility.MouseTargetConfig)

local TargetUpdateEvent : RemoteFunction = game.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UpdatePlayerTarget") :: RemoteFunction

local Player : Player = game.Players.LocalPlayer
--// Create and configure the mouse target controller \\--
local config = MouseTargetConfig
-- Enable debug features if needed during development
-- config.debug.enabled = true
-- config.debug.raycastVisualization = true
-- config.debug.logging = true

local mouseController = MouseTargetController.new(config)

--// Set up target change callback \\--
mouseController:onTargetChanged(function(newTarget: Model?, oldTarget: Model?)
	while Player:GetAttribute("UsingAbility") do 
		task.wait()
	end

	TargetUpdateEvent:InvokeServer(newTarget)
end)

--// Start the targeting system \\--
mouseController:start()

--// Optional: Expose controller globally for other scripts \\--
-- You can access the current target via: mouseController:getCurrentTarget()
-- Or register callbacks via: mouseController:onTargetChanged(callback)
_G.MouseTargetController = mouseController
