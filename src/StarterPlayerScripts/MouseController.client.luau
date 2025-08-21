--!strict
--[[
	Mouse Controller Client
	Simplified and clean mouse targeting system using the modular MouseTargetController
	
	@author: Sam
	@version: 2.0.0
]]

local Players = game:GetService("Players")

--// Modules \\--
local MouseTargetController = require(game.ReplicatedStorage.Modules.Utility.MouseTargetController)
local MouseTargetConfig = require(game.ReplicatedStorage.Modules.Utility.MouseTargetConfig)
local TargetSystem = require(game.ReplicatedStorage.Modules.CoreClient.Targeting).new()

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

	TargetSystem:SetTarget(Players.LocalPlayer, newTarget)
end)

--// Start the targeting system \\--
mouseController:start()