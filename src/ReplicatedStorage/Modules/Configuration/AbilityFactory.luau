--!strict
-- AbilityFactory: Simplified ability creation and registration
-- Makes it easy to add new abilities to the system

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityConfiguration = require(script.Parent:WaitForChild("AbilityConfiguration"))
local ResourceTypes = require(script.Parent:WaitForChild("ResourceTypes"))
local InputConfiguration = require(script.Parent:WaitForChild("InputConfiguration"))

export type QuickAbilityConfig = {
    -- Required fields
    id: string,
    displayName: string,
    category: "Primary" | "Secondary" | "Active" | "Ultimate" | "Passive",
    resourceType: "ammo" | "cooldown" | "energy" | "charges" | "heat",
    
    -- Resource configuration (based on type)
    cooldown: number?, -- For cooldown type
    maxAmmo: number?, -- For ammo type
    reloadTime: number?, -- For ammo type
    maxCharges: number?, -- For charges type
    chargeRegenTime: number?, -- For charges type
    maxEnergy: number?, -- For energy type
    energyCost: number?, -- For energy type
    energyRegenRate: number?, -- For energy type
    maxHeat: number?, -- For heat type
    heatPerUse: number?, -- For heat type
    cooldownRate: number?, -- For heat type (cooling rate)
    
    -- Common settings
    fireRate: number?, -- Minimum time between uses (default: 0.1)
    attackRange: number?, -- Maximum range (default: 100)
    requiresTarget: boolean?, -- Does it need a target? (default: false)
    
    -- Input binding
    inputKey: EnumItem, -- The key/button to trigger
    holdable: boolean?, -- Can be held down? (default: false)
    
    -- Visual settings
    color: Color3?, -- Main color (default based on category)
    glowColor: Color3?, -- Glow effect color
    pulseOnReady: boolean?, -- Pulse when ready? (default: true)
    icon: string?, -- Optional icon asset ID
    
    -- Optional metadata
    description: string?,
    tags: {string}?,
    baseValues: {[string]: any}?,
}

local AbilityFactory = {}

-- Default colors by category
local CATEGORY_COLORS = {
    Primary = Color3.new(0.2, 1, 0.4),
    Secondary = Color3.new(0.4, 0.8, 1),
    Active = Color3.new(0.6, 0.4, 1),
    Ultimate = Color3.new(1, 0.8, 0.2),
    Passive = Color3.new(0.5, 0.5, 0.7),
}

-- Create a new ability from simplified config
function AbilityFactory.CreateAbility(config: QuickAbilityConfig): boolean
    -- Validate required fields
    if not config.id or not config.displayName or not config.category or not config.resourceType then
        warn("[AbilityFactory] Missing required fields")
        return false
    end
    
    -- Build resource configuration based on type
    local resourceConfig = {
        type = config.resourceType,
        fireRate = config.fireRate or 0.1,
    }
    
    if config.resourceType == "ammo" then
        resourceConfig.maxAmmo = config.maxAmmo or 6
        resourceConfig.reloadTime = config.reloadTime or 2
        resourceConfig.autoReload = true
    elseif config.resourceType == "cooldown" then
        resourceConfig.cooldownTime = config.cooldown or 5
    elseif config.resourceType == "charges" then
        resourceConfig.maxCharges = config.maxCharges or 3
        resourceConfig.chargeRegenTime = config.chargeRegenTime or 5
    elseif config.resourceType == "energy" then
        resourceConfig.maxEnergy = config.maxEnergy or 100
        resourceConfig.energyCost = config.energyCost or 25
        resourceConfig.regenRate = config.energyRegenRate or 5
        resourceConfig.regenDelay = 2
    elseif config.resourceType == "heat" then
        resourceConfig.maxHeat = config.maxHeat or 100
        resourceConfig.heatPerUse = config.heatPerUse or 20
        resourceConfig.cooldownRate = config.cooldownRate or 10
        resourceConfig.overheatPenalty = 3
    end
    
    -- Determine input type
    local inputType = "keyboard"
    if config.inputKey.EnumType == Enum.UserInputType then
        inputType = "mouse"
    elseif config.inputKey.EnumType == Enum.KeyCode then
        if config.inputKey.Name:find("Button") then
            inputType = "gamepad"
        end
    end
    
    -- Get the next numeric ID
    local existingAbilities = AbilityConfiguration.GetConfig().abilities
    local maxId = 0
    for _, ability in pairs(existingAbilities) do
        if ability.numericId > maxId then
            maxId = ability.numericId
        end
    end
    
    -- Build the full ability definition
    local abilityDef = {
        id = config.id,
        numericId = maxId + 1,
        displayName = config.displayName,
        description = config.description or "",
        category = config.category,
        resource = resourceConfig,
        input = {
            type = inputType,
            key = config.inputKey,
            holdable = config.holdable or false,
        },
        ui = {
            color = config.color or CATEGORY_COLORS[config.category] or Color3.new(0.5, 0.5, 0.5),
            position = maxId + 1,
            keyDisplay = config.inputKey.Name,
            glowColor = config.glowColor,
            pulseOnReady = config.pulseOnReady ~= false,
        },
        enabled = true,
        requiresTarget = config.requiresTarget or false,
        attackRange = config.attackRange or 100,
        baseValues = config.baseValues,
        tags = config.tags,
    }
    
    -- Register with configuration
    local currentConfig = AbilityConfiguration.GetConfig()
    currentConfig.abilities[config.id] = abilityDef
    
    -- Update configuration
    AbilityConfiguration.UpdateConfig({
        abilities = currentConfig.abilities
    })
    
    -- Also update input configuration mapping
    local slotId = `ability_slot_{maxId + 1}`
    InputConfiguration.SetCustomBinding(slotId, {
        primary = config.inputKey,
        holdable = config.holdable or false,
    })
    
    print(`[AbilityFactory] Created ability {config.id} with ID {maxId + 1}`)
    return true
end

-- Quick builders for common ability types
function AbilityFactory.CreateDamageAbility(id: string, name: string, damage: number, cooldown: number, key: EnumItem): boolean
    return AbilityFactory.CreateAbility({
        id = id,
        displayName = name,
        category = "Active",
        resourceType = "cooldown",
        cooldown = cooldown,
        fireRate = 0.2,
        attackRange = 100,
        requiresTarget = true,
        inputKey = key,
        holdable = false,
        baseValues = {
            damage = damage,
        },
        tags = {"damage", "offensive"},
    })
end

function AbilityFactory.CreateHealAbility(id: string, name: string, healAmount: number, cooldown: number, key: EnumItem): boolean
    return AbilityFactory.CreateAbility({
        id = id,
        displayName = name,
        category = "Active",
        resourceType = "cooldown",
        cooldown = cooldown,
        fireRate = 0.2,
        attackRange = 100,
        requiresTarget = true,
        inputKey = key,
        holdable = false,
        color = Color3.new(0.2, 1, 0.4),
        baseValues = {
            healAmount = healAmount,
        },
        tags = {"healing", "support"},
    })
end

function AbilityFactory.CreateMovementAbility(id: string, name: string, distance: number, charges: number, key: EnumItem): boolean
    return AbilityFactory.CreateAbility({
        id = id,
        displayName = name,
        category = "Active",
        resourceType = "charges",
        maxCharges = charges,
        chargeRegenTime = 5,
        fireRate = 0.1,
        attackRange = distance,
        requiresTarget = false,
        inputKey = key,
        holdable = false,
        color = Color3.new(0.3, 0.9, 1),
        baseValues = {
            dashDistance = distance,
        },
        tags = {"movement", "mobility"},
    })
end

function AbilityFactory.CreateUltimateAbility(id: string, name: string, energyCost: number, key: EnumItem, config: {[string]: any}): boolean
    return AbilityFactory.CreateAbility({
        id = id,
        displayName = name,
        category = "Ultimate",
        resourceType = "energy",
        maxEnergy = 100,
        energyCost = energyCost,
        energyRegenRate = 2,
        fireRate = 0.5,
        attackRange = 200,
        requiresTarget = true,
        inputKey = key,
        holdable = false,
        pulseOnReady = true,
        baseValues = config,
        tags = {"ultimate", "powerful"},
    })
end

-- Example usage:
--[[
    -- Create a new fireball ability
    AbilityFactory.CreateDamageAbility(
        "Fireball",           -- ID
        "Fireball",           -- Display name
        50,                   -- Damage
        5,                    -- Cooldown
        Enum.KeyCode.F        -- Key binding
    )
    
    -- Create a teleport ability with charges
    AbilityFactory.CreateMovementAbility(
        "Teleport",
        "Teleport",
        50,                   -- Distance
        3,                    -- Number of charges
        Enum.KeyCode.T
    )
    
    -- Create a custom ability
    AbilityFactory.CreateAbility({
        id = "Lightning",
        displayName = "Lightning Strike",
        category = "Active",
        resourceType = "energy",
        maxEnergy = 100,
        energyCost = 30,
        energyRegenRate = 5,
        fireRate = 0.3,
        attackRange = 150,
        requiresTarget = true,
        inputKey = Enum.KeyCode.L,
        holdable = false,
        color = Color3.new(0.8, 0.8, 1),
        glowColor = Color3.new(1, 1, 1),
        baseValues = {
            damage = 75,
            stunDuration = 1,
        },
        tags = {"damage", "stun", "electric"},
    })
--]]

return AbilityFactory