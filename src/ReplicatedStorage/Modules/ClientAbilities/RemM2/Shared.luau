--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local Config = require(script.Parent.Config)

local Shared = {}

function Shared.IsValid(ctx: Types.SharedAbilityContext): boolean
    -- Basic validation for healing ability
    if not ctx or not ctx.inputData then
        return false
    end
    
    -- Must have target position for healing
    if not ctx.inputData.target then
        return false
    end
    
    return true
end

function Shared.GetConfig()
    -- Return the full config directly
    return Config
end

function Shared.GetAssets(): Folder
    return script.Parent.Assets
end

return Shared