--!strict
-- Dash - Active ability that provides quick movement burst

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

local Player = Players.LocalPlayer

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

-- Configuration
local DASH_DISTANCE = 20 -- studs
local DASH_DURATION = 0.3 -- seconds
local COOLDOWN_TIME = 3.0 -- seconds
local STAMINA_COST = 25

local Dash = {}

function Dash.onRequest(ctx: SharedAbilityContext): AbilityResult
    -- Check stamina
    local currentStamina = ctx.characterState.stamina or 0
    if currentStamina < STAMINA_COST then
        return { success = false, reason = "Insufficient stamina" }
    end

    return {
        success = true,
        cooldowns = { [tostring(ctx.abilityId)] = ctx.timestamp + COOLDOWN_TIME },
    }
end

function Dash.onCast(ctx: SharedAbilityContext)
end

function Dash.onConfirm(ctx: SharedAbilityContext, serverData: any?)
    -- Server confirmed the dash - could add additional effects here
    print("Dash confirmed by server")
end

function Dash.onReject(ctx: SharedAbilityContext, reason: string?)
    -- Server rejected the dash - revert any client-side changes
    print(`Dash rejected: {reason or "Unknown reason"}`)
end

function Dash._playDashEffects(rootPart: BasePart)
    -- Add visual effects for the dash
    -- This could include particles, sounds, etc.
    
    -- Example: Create a simple particle effect
    local attachment = Instance.new("Attachment")
    attachment.Parent = rootPart
    
    -- TODO: Add actual particle effects, sounds, etc.
    
    -- Clean up after a short time
    game:GetService("Debris"):AddItem(attachment, 1.0)
end

-- Ability metadata functions
function Dash.getAbilityInputRequired()
    return Enum.KeyCode.Q -- Default Q key
end

function Dash.getAbilityClassId()
    return nil -- Available to all classes
end

function Dash.getAbilityCategory()
    return "Active"
end

function Dash.getAbilityRange()
    return DASH_DISTANCE
end

function Dash.getRequiresTarget()
    return false -- No target required, uses movement direction
end

return Dash
