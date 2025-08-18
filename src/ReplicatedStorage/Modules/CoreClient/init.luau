--[[
    CoreClient init.luau
    
    Core client-side modules for OVERVERSE.
    Provides centralized access to camera and other client systems.
    
    Author: Created for OVERVERSE v2.0.0
    Date: August 17, 2025
--]]

local CoreClient = {}

-- Export camera modules
CoreClient.CameraFollow = require(script.CameraFollow)
CoreClient.CameraShiftLock = require(script.ShiftLock)

return CoreClient
