--!strict
-- Client-side handler for ability visual effects
-- Listens for server ability cast events and plays appropriate effects

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Network module
local NetworkClient = require(ReplicatedStorage.Modules.Network.Client)

-- Effect handlers for each ability
-- Load Rem M1 effects
local Abilities = require(game.ReplicatedStorage.Modules.Abilities.Rem)

-- Listen for ability cast events from server
NetworkClient.CastAbility.On(function(data: {
    AbilityName: string,
    CharacterName: string,
    PlayerCaster: Player,
    Direction: Vector3,
    Position: Vector3
})
    -- Try to find ability by various naming conventions
    -- AbilityName might be "rem_m1", "M1", etc.
    local abilityModule = nil
    
    -- First try direct name match
    abilityModule = Abilities[data.AbilityName]
    
    -- If not found, try extracting the ability type (e.g., "rem_m1" -> "M1")
    if not abilityModule then
        local parts = string.split(data.AbilityName:lower(), "_")
        if #parts >= 2 then
            local abilityType = parts[#parts]:upper() -- Get last part and uppercase it
            abilityModule = Abilities[abilityType]
        end
    end
    
    -- If still not found, warn and return
    if not abilityModule then
        return warn(`[AbilityEffectsHandler] Ability module not found for: {data.AbilityName}`)
    end
    
    -- Check if the ability has a Client handler
    local handler = abilityModule.Client
    if not handler then
        -- No visual handler for this ability yet
        return warn(`[AbilityEffectsHandler] No Client handler found for ability: {data.AbilityName}`)
    end
    
    -- Execute the client handler
    handler:OnUse(Players.LocalPlayer)
end)
