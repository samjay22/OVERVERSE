--!strict
-- Improved Network Server with event-driven architecture

local NetworkManager = require(game.ServerStorage.Modules.Core.NetworkManager)
-- Create network manager instance
local networkManager = NetworkManager.New()
return networkManager
