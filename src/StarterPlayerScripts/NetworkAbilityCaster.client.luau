--!strict
-- Client-side network ability caster with ping compensation
-- Sends ability cast requests to server for network-aware damage application

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local NetworkClient = require(ReplicatedStorage.Modules.Network.Client)

local LOCAL_PLAYER = Players.LocalPlayer

-- Ability ID mapping (you may need to adjust this based on your system)
local ABILITY_IDS = {
    ["Rem_M1"] = 1,
    ["M1"] = 1,
    -- Add more ability mappings as needed
}

-- Track ability cast requests to avoid spam
local lastCastTime = {}
local CAST_COOLDOWN = 0.1 -- Minimum time between casts in seconds

-- Function to send ability cast request to server
local function sendAbilityCastRequest(abilityName: string, targetPosition: Vector3?, target: Model?)
    local abilityId = ABILITY_IDS[abilityName]
    if not abilityId then
        warn(`[NetworkAbilityCaster] Unknown ability: {abilityName}`)
        return false
    end
    
    -- Check cooldown to prevent spam
    local currentTime = tick()
    local lastTime = lastCastTime[abilityName] or 0
    if currentTime - lastTime < CAST_COOLDOWN then
        return false
    end
    lastCastTime[abilityName] = currentTime
    
    -- Get target position from mouse if not provided
    if not targetPosition then
        local mouse = LOCAL_PLAYER:GetMouse()
        if mouse and mouse.Hit then
            targetPosition = mouse.Hit.Position
        else
            targetPosition = Vector3.new(0, 0, 0)
        end
    end

    -- Ensure targetPosition is never nil
    targetPosition = targetPosition or Vector3.new(0, 0, 0)
    
    -- Send request to server
    local requestData = {
        AbilityId = abilityId,
        Target = target,
        Position = targetPosition
    }
    
    NetworkClient.RequestAbilityCast.Fire(requestData)
    print(`[NetworkAbilityCaster] Sent ability cast request: {abilityName} (ID: {abilityId}) to position {targetPosition}`)
    
    return true
end

-- Listen for M1 input and send network request
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        -- Send M1 ability cast request
        sendAbilityCastRequest("Rem_M1")
    end
end)

-- Export function for other scripts to use
_G.SendAbilityCastRequest = sendAbilityCastRequest

print("[NetworkAbilityCaster] Initialized - Ready to send ability cast requests")
