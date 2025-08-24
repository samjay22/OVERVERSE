--!strict
-- Dash Client Module - Active Category Ability
-- Simple dash implementation for category-based execution system

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local Config = require(script.Parent.Config)

local Player = Players.LocalPlayer

local Client = {}

-- Helper function to get character and humanoid
local function getCharacterData()
    local character = Player.Character
    if not character then return nil, nil, nil end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    
    return character, humanoid, rootPart
end

-- Execute the dash ability
local function executeDash(direction: Vector3?)
    local character, humanoid, rootPart = getCharacterData()
    if not character or not humanoid or not rootPart then return end
    
    -- Use provided direction or character's look direction
    local dashDirection = direction or rootPart.CFrame.LookVector
    dashDirection = dashDirection.Unit
    
    -- Apply dash impulse
    local dashDistance = Config.ATTACK_RANGE
    local dashDuration = 0.3 -- Quick dash
    local dashVelocity = dashDirection * (dashDistance / dashDuration)
    
    -- Create BodyVelocity for smooth dash
    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(50000, 0, 50000) -- Only horizontal dash
    bodyVelocity.Velocity = Vector3.new(dashVelocity.X, 0, dashVelocity.Z)
    bodyVelocity.Parent = rootPart
    
    -- Clean up after dash
    task.wait(dashDuration)
    if bodyVelocity and bodyVelocity.Parent then
        bodyVelocity:Destroy()
    end
end

-- Main execution function called by CategoryHandler
function Client.Execute(context: Types.SharedAbilityContext)
    local direction = context.inputData.direction
    
    -- Perform the dash
    task.spawn(function()
        executeDash(direction)
    end)
    
    return {
        success = true,
        message = "Dash executed"
    }
end

-- Validation function
function Client.Validate(context: Types.SharedAbilityContext): Types.ValidationResult
    local character = Player.Character
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
    
    return {
        success = true
    }
end

-- Optional: Called when ability is cancelled/rejected
function Client.OnCancel(context: Types.SharedAbilityContext, reason: string?)
    -- Could add effects or cleanup here
end

-- Optional: Called on successful server validation
function Client.OnReplicate(context: Types.SharedAbilityContext, serverData: any)
    -- Could sync additional server state here
end

return Client