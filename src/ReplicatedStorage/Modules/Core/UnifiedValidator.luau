--!strict
-- Unified validation system for both client and server
-- Single source of truth for all validation logic

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CategorySystem = require(ReplicatedStorage.Modules.Utility.CategorySystem)
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

type ValidationResult = { success: boolean, reason: string? }
type ValidationRule<T> = (config: T, context: any) -> ValidationResult
type CategoryRules = { [string]: ValidationRule<any> }

-- Strict typed configuration constraints
export type ValidationConstraints = {
    maxAmmo: number,
    minCooldown: number,
    maxCooldown: number,
    maxRange: number,
    requiresTarget: boolean,
}

-- Abstract validation rules by category
local CATEGORY_CONSTRAINTS: { [Types.AbilityCategory]: ValidationConstraints } = {
    Primary = {
        maxAmmo = 50,
        minCooldown = 0,
        maxCooldown = 0,
        maxRange = 500,
        requiresTarget = true,
    },
    Active = {
        maxAmmo = 0,
        minCooldown = 1.0,
        maxCooldown = 30.0,
        maxRange = 300,
        requiresTarget = false,
    },
    Secondary = {
        maxAmmo = 0,
        minCooldown = 0.5,
        maxCooldown = 15.0,
        maxRange = 200,
        requiresTarget = false,
    },
    Ultimate = {
        maxAmmo = 0,
        minCooldown = 20.0,
        maxCooldown = 600.0,
        maxRange = 1000,
        requiresTarget = false,
    },
    Passive = {
        maxAmmo = 0,
        minCooldown = 0,
        maxCooldown = 0,
        maxRange = 0,
        requiresTarget = false,
    },
}

local UnifiedValidator = {}

-- Abstract validation with strict typing
function UnifiedValidator.Validate<T>(
    abilityModule: T,
    context: Types.SharedAbilityContext,
    isServer: boolean
): ValidationResult
    local sharedModule = (abilityModule :: any).GetSharedModule()
    local config = sharedModule.GetConfig()
    local category: Types.AbilityCategory = config.ABILITY_CATEGORY
    
    local constraints = CATEGORY_CONSTRAINTS[category]
    if not constraints then
        return { success = false, reason = `Invalid category: {category}` }
    end
    
    local behavior = CategorySystem.GetBehavior(category)
    if not behavior then
        return { success = false, reason = `Category not found: {category}` }
    end
    
    -- Target validation
    if config.REQUIRES_TARGET and not context.inputData.target then
        return { success = false, reason = `{category} requires target` }
    end
    
    -- Range validation with enhanced type checking
    if config.ATTACK_RANGE and context.inputData.target then
        local playerPos = context.characterState.position
        local targetPos = context.inputData.target
        
        if typeof(playerPos) ~= "Vector3" or typeof(targetPos) ~= "Vector3" then
            warn(`[UnifiedValidator] Invalid position - Player: {typeof(playerPos)}, Target: {typeof(targetPos)}`)
            return { success = false, reason = "Invalid position data" }
        end
        
        local distance = ((playerPos :: Vector3) - (targetPos :: Vector3)).Magnitude
        
        -- Debug abnormal distances
        if distance > 1000 then
            warn(`[UnifiedValidator] Abnormal distance: {distance} at Player: {playerPos}, Target: {targetPos}`)
        end
        
        if distance > config.ATTACK_RANGE then
            return { success = false, reason = `Out of range: {distance} > {config.ATTACK_RANGE}` }
        end
        
        -- Enforce max range constraint
        if distance > constraints.maxRange then
            return { success = false, reason = `Exceeds category limit: {distance} > {constraints.maxRange}` }
        end
    end
    
    -- Resource validation based on category
    if behavior.usesAmmo then
        local maxAmmo = config.MAX_AMMO or behavior.defaultMaxAmmo :: number
        if maxAmmo > constraints.maxAmmo then
            return { success = false, reason = `Ammo exceeds limit: {maxAmmo} > {constraints.maxAmmo}` }
        end
    end
    
    if behavior.usesCooldown then
        local cooldown = config.COOLDOWN_TIME or behavior.defaultCooldown :: number
        if cooldown < constraints.minCooldown then
            return { success = false, reason = `Cooldown too short: {cooldown}s < {constraints.minCooldown}s` }
        end
        if cooldown > constraints.maxCooldown then
            return { success = false, reason = `Cooldown too long: {cooldown}s > {constraints.maxCooldown}s` }
        end
    end
    
    -- Server-only anti-cheat validation
    if isServer then
        -- Add server-specific validation here
        local timeSinceLastUse = context.timestamp - (context.lastUseTime or 0)
        if timeSinceLastUse < 0.1 then -- Prevent spam
            return { success = false, reason = "Rate limit exceeded" }
        end
    end
    
    return { success = true }
end

return UnifiedValidator