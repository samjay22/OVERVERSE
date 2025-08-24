--!strict
-- Dash Server Module - Active Category Ability
-- Server-side validation and execution for dash ability

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local Config = require(script.Parent.Config)

local Server = {}

-- Validate the dash request
function Server.Validate(player: Player, context: Types.SharedAbilityContext): Types.ValidationResult
    local character = player.Character
    if not character then
        return {
            success = false,
            reason = "No character"
        }
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return {
            success = false,
            reason = "Character is dead"
        }
    end
    
    -- Could add additional server-side checks here
    -- e.g., stamina, status effects, etc.
    
    return {
        success = true
    }
end

-- Execute server-side dash logic
function Server.Execute(player: Player, context: Types.SharedAbilityContext)
    local character = player.Character
    if not character then return end
    
    -- Server could apply additional effects here
    -- e.g., invulnerability frames, speed boost, etc.
    
    return {
        success = true,
        cooldownEndTime = workspace:GetServerTimeNow() + Config.RELOAD_TIME
    }
end

-- Handle ability cancellation
function Server.OnCancel(player: Player, context: Types.SharedAbilityContext, reason: string?)
    -- Clean up any server-side effects if needed
end

return Server