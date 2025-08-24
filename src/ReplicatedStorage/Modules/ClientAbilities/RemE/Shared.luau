local Types = require(game.ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local Configs = require(script.Parent.Config)

local Shared : Types.Shared = {
    IsValid = function(ctx)
        -- Basic context validation
        if not ctx.characterState or not ctx.inputData then
            return false, "Missing required context data"
        end
        
        -- Validate player exists
        local player = game.Players:GetPlayerByUserId(ctx.playerId)
        if not player then
            return false, "Player not found"
        end
        
        -- Validate character exists and has required components
        local character = player.Character
        if not character then
            return false, "Character not found"
        end
        
        local humanoid = character:FindFirstChild("Humanoid")
        if not humanoid then
            return false, "Humanoid not found"
        end
        
        -- Check if player is alive
        if humanoid.Health <= 0 then
            return false, "Player is dead"
        end
        
        -- Validate wand exists
        local wand = character:FindFirstChild("Wand..")
        if not wand or not wand:FindFirstChild("Part") then
            return false, "Wand not equipped"
        end
        
        -- Validate target input
        if not ctx.inputData.target then
            return false, "No target specified"
        end
        
        -- Validate target is within range
        local startPos = wand.Part.Position
        local targetPos = ctx.inputData.target
        local distance = (targetPos - startPos).Magnitude
        
        if distance > Configs.ATTACK_RANGE then
            return false, `Target out of range (${math.floor(distance)}/${Configs.ATTACK_RANGE})`
        end
        
        -- Validate target position is reasonable (not underground, not too high)
        if targetPos.Y < -100 or targetPos.Y > 1000 then
            return false, "Invalid target position"
        end
        
        -- Check cooldown (if available in character state)
        if ctx.characterState.cooldowns then
            local cooldownKey = tostring(ctx.abilityId)
            local cooldownEnd = ctx.characterState.cooldowns[cooldownKey]
            if cooldownEnd and ctx.timestamp < cooldownEnd then
                local remainingTime = cooldownEnd - ctx.timestamp
                return false, `Ability on cooldown (${math.ceil(remainingTime)}s remaining)`
            end
        end
        
        -- Check stamina/mana requirements (if available)
        if ctx.characterState.stamina and ctx.characterState.stamina < 10 then
            return false, "Insufficient stamina"
        end
        
        return true
    end,
    
    -- Additional utility functions for the ability
    GetProjectileSpeed = function()
        return Configs.PROJECTILE_SPEED
    end,
    
    GetMaxRange = function()
        return Configs.ATTACK_RANGE
    end,
    
    GetDamage = function()
        return Configs.DAMAGE
    end,
    
    GetCooldown = function()
        return Configs.COOLDOWN_TIME
    end,
    
    CalculateImpactTime = function(startPos: Vector3, targetPos: Vector3)
        local distance = (targetPos - startPos).Magnitude
        return distance / Configs.PROJECTILE_SPEED
    end
} :: any

return Shared