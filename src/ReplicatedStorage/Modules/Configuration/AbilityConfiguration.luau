--!strict
-- AbilityConfiguration: Centralized configuration for all abilities
-- Makes the system highly configurable and easy to extend

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

type AbilityCategory = Types.AbilityCategory

export type InputBinding = {
    type: "keyboard" | "mouse" | "gamepad",
    key: EnumItem,
    modifier: EnumItem?, -- Shift, Ctrl, Alt
    holdable: boolean?, -- Can be held down
}

export type UIConfig = {
    color: Color3,
    icon: string?, -- Asset ID
    position: number, -- Display order
    keyDisplay: string, -- Display text for key
    glowColor: Color3?,
    pulseOnReady: boolean?,
}

export type ResourceConfig = {
    type: "ammo" | "cooldown" | "energy" | "charges" | "heat",
    -- Ammo specific
    maxAmmo: number?,
    reloadTime: number?,
    autoReload: boolean?,
    -- Cooldown specific
    cooldownTime: number?,
    -- Energy specific
    maxEnergy: number?,
    regenRate: number?, -- per second
    -- Charges specific
    maxCharges: number?,
    chargeRegenTime: number?,
    -- Heat specific
    maxHeat: number?,
    heatPerUse: number?,
    cooldownRate: number?, -- per second
    -- Common
    fireRate: number?, -- Minimum time between uses
}

export type AbilityDefinition = {
    id: string,
    numericId: number,
    displayName: string,
    description: string?,
    category: AbilityCategory,
    resource: ResourceConfig,
    input: InputBinding,
    ui: UIConfig,
    enabled: boolean,
    requiresTarget: boolean?,
    attackRange: number?,
    -- Modifiers (for future upgrade system)
    baseValues: {[string]: any}?,
    tags: {string}?, -- For filtering/searching
}

export type CategoryDefinition = {
    name: AbilityCategory,
    displayName: string,
    defaultResourceType: "ammo" | "cooldown" | "energy" | "charges" | "heat",
    defaultResource: ResourceConfig?,
    allowReload: boolean?,
    icon: string?,
    color: Color3?,
}

export type UIConfiguration = {
    position: UDim2,
    size: UDim2,
    theme: string,
    animations: {
        cooldownStyle: "fill" | "drain" | "pulse" | "sweep",
        transitionSpeed: number,
        flashOnUse: boolean,
        shakeOnEmpty: boolean,
    },
    layout: "horizontal" | "vertical" | "grid",
    spacing: number,
    showKeybinds: boolean,
    showCooldownText: boolean,
    showResourceCount: boolean,
}

export type Configuration = {
    abilities: {[string]: AbilityDefinition},
    categories: {[string]: CategoryDefinition},
    ui: UIConfiguration,
    version: string,
}

-- Default configuration
local DEFAULT_CONFIG: Configuration = {
    version = "1.0.0",
    
    abilities = {
        RemM1 = {
            id = "RemM1",
            numericId = 1,
            displayName = "Healing Shot",
            description = "Primary healing projectile with spiral effect",
            category = "Primary",
            resource = {
                type = "ammo",
                maxAmmo = 24,
                reloadTime = 5,
                autoReload = true,
                fireRate = 0.5,
            },
            input = {
                type = "mouse",
                key = Enum.UserInputType.MouseButton1,
                holdable = true,
            },
            ui = {
                color = Color3.new(0.15, 1, 0.4), -- Healing green color from config
                position = 1,
                keyDisplay = "MB1",
                glowColor = Color3.new(0.3, 1, 0.6),
                pulseOnReady = true,
            },
            enabled = true,
            requiresTarget = true,
            attackRange = 120,
            baseValues = {
                healAmount = 30,
                projectileSpeed = 75,
                spiralRadius = 2,
                spiralFrequency = 8,
            },
            tags = {"healing", "projectile", "primary"},
        },
        
        RemM2 = {
            id = "RemM2",
            numericId = 2,
            displayName = "Burst Heal",
            description = "Powerful area healing burst",
            category = "Primary",
            resource = {
                type = "ammo",
                maxAmmo = 12,
                reloadTime = 4,
                autoReload = true,
                fireRate = 0.3,
            },
            input = {
                type = "mouse",
                key = Enum.UserInputType.MouseButton2,
                holdable = true,
            },
            ui = {
                color = Color3.new(0.4, 0.8, 1), -- Healing blue
                position = 2,
                keyDisplay = "MB2",
                glowColor = Color3.new(0.6, 0.9, 1),
                pulseOnReady = false,
            },
            enabled = true,
            requiresTarget = true,
            attackRange = 100,
            baseValues = {
                healAmount = 50,
                burstRadius = 15,
            },
            tags = {"healing", "burst", "secondary"},
        },
        
        Dash = {
            id = "Dash",
            numericId = 3,
            displayName = "Swift Dash",
            description = "Quick directional movement",
            category = "Active",
            resource = {
                type = "charges",
                maxCharges = 2,
                chargeRegenTime = 5,
            },
            input = {
                type = "keyboard",
                key = Enum.KeyCode.Q,
                holdable = false,
            },
            ui = {
                color = Color3.new(0.3, 0.9, 1), -- Swift cyan
                position = 4,
                keyDisplay = "Q",
                glowColor = Color3.new(0.5, 1, 1),
                pulseOnReady = true,
            },
            enabled = true,
            requiresTarget = false,
            baseValues = {
                dashDistance = 30,
                dashSpeed = 100,
            },
            tags = {"movement", "mobility"},
        },
        
        RemE = {
            id = "RemE",
            numericId = 4,
            displayName = "Smoke Screen",
            description = "Deploy vision-blocking smoke cloud",
            category = "Active",
            resource = {
                type = "cooldown",
                cooldownTime = 12,
            },
            input = {
                type = "keyboard",
                key = Enum.KeyCode.E,
                holdable = false,
            },
            ui = {
                color = Color3.new(0.6, 0.6, 0.7), -- Smoke gray-purple
                position = 3,
                keyDisplay = "E",
                glowColor = Color3.new(0.8, 0.8, 0.9),
                pulseOnReady = false,
            },
            enabled = true,
            requiresTarget = true,
            attackRange = 150,
            baseValues = {
                smokeDuration = 8,
                smokeRadius = 20,
            },
            tags = {"utility", "area", "vision"},
        },
        
        RemR = {
            id = "RemR",
            numericId = 5,
            displayName = "Resurrection",
            description = "Ultimate healing revival ability",
            category = "Ultimate",
            resource = {
                type = "energy",
                maxEnergy = 100,
                regenRate = 2, -- 2 energy per second
                energyCost = 100,
            },
            input = {
                type = "keyboard",
                key = Enum.KeyCode.R,
                holdable = false,
            },
            ui = {
                color = Color3.new(1, 0.8, 0.2),
                position = 5,
                keyDisplay = "R",
                glowColor = Color3.new(1, 1, 0.4),
                pulseOnReady = true,
            },
            enabled = false, -- Disabled: ability module not implemented
            requiresTarget = true,
            attackRange = 200,
            baseValues = {
                reviveHealth = 50,
                castTime = 2,
            },
            tags = {"ultimate", "healing", "revival"},
        },
        
        RemF = {
            id = "RemF",
            numericId = 6,
            displayName = "Heal Beam",
            description = "Continuous healing beam",
            category = "Active",
            resource = {
                type = "heat",
                maxHeat = 100,
                heatPerUse = 5,
                cooldownRate = 20,
                overheatPenalty = 3,
            },
            input = {
                type = "keyboard",
                key = Enum.KeyCode.F,
                holdable = true,
            },
            ui = {
                color = Color3.new(1, 0.5, 0.8),
                position = 6,
                keyDisplay = "F",
                glowColor = Color3.new(1, 0.7, 0.9),
                pulseOnReady = false,
            },
            enabled = true,
            requiresTarget = true,
            attackRange = 80,
            baseValues = {
                healPerSecond = 40,
                beamWidth = 2,
            },
            tags = {"healing", "channeled", "beam"},
        },
    },
    
    categories = {
        Primary = {
            name = "Primary",
            displayName = "Primary Abilities",
            defaultResourceType = "ammo",
            defaultResource = {
                type = "ammo",
                maxAmmo = 6,
                reloadTime = 2,
                autoReload = true,
            },
            allowReload = true,
            color = Color3.new(1, 0.4, 0.4),
        },
        
        Secondary = {
            name = "Secondary",
            displayName = "Secondary Abilities",
            defaultResourceType = "cooldown",
            defaultResource = {
                type = "cooldown",
                cooldownTime = 3,
            },
            allowReload = false,
            color = Color3.new(0.4, 0.6, 1),
        },
        
        Active = {
            name = "Active",
            displayName = "Active Abilities",
            defaultResourceType = "cooldown",
            defaultResource = {
                type = "cooldown",
                cooldownTime = 10,
            },
            allowReload = false,
            color = Color3.new(0.6, 0.8, 0.4),
        },
        
        Ultimate = {
            name = "Ultimate",
            displayName = "Ultimate Abilities",
            defaultResourceType = "energy",
            defaultResource = {
                type = "energy",
                maxEnergy = 100,
                regenRate = 1,
            },
            allowReload = false,
            color = Color3.new(1, 0.8, 0.2),
        },
        
        Passive = {
            name = "Passive",
            displayName = "Passive Abilities",
            defaultResourceType = "cooldown",
            defaultResource = {
                type = "cooldown",
                cooldownTime = 0,
            },
            allowReload = false,
            color = Color3.new(0.5, 0.5, 0.7),
        },
    },
    
    ui = {
        position = UDim2.new(0.275, 0, 1, -110),
        size = UDim2.new(0.45, 0, 0, 90),
        theme = "modern-dark",
        animations = {
            cooldownStyle = "fill",
            transitionSpeed = 0.1,
            flashOnUse = true,
            shakeOnEmpty = true,
        },
        layout = "horizontal",
        spacing = 8,
        showKeybinds = true,
        showCooldownText = true,
        showResourceCount = true,
    },
}

-- Configuration manager
local AbilityConfiguration = {}
AbilityConfiguration.__index = AbilityConfiguration

-- Private storage
local currentConfig: Configuration = DEFAULT_CONFIG
local configChangeCallbacks: {(config: Configuration) -> ()} = {}

-- Get the current configuration
function AbilityConfiguration.GetConfig(): Configuration
    return currentConfig
end

-- Get a specific ability configuration
function AbilityConfiguration.GetAbility(abilityId: string): AbilityDefinition?
    return currentConfig.abilities[abilityId]
end

-- Get all abilities for a category
function AbilityConfiguration.GetAbilitiesByCategory(category: AbilityCategory): {AbilityDefinition}
    local abilities = {}
    for _, ability in pairs(currentConfig.abilities) do
        if ability.category == category and ability.enabled then
            table.insert(abilities, ability)
        end
    end
    table.sort(abilities, function(a, b)
        return a.ui.position < b.ui.position
    end)
    return abilities
end

-- Get enabled abilities only
function AbilityConfiguration.GetEnabledAbilities(): {AbilityDefinition}
    local abilities = {}
    for _, ability in pairs(currentConfig.abilities) do
        if ability.enabled then
            table.insert(abilities, ability)
        end
    end
    table.sort(abilities, function(a, b)
        return a.ui.position < b.ui.position
    end)
    return abilities
end

-- Get category configuration
function AbilityConfiguration.GetCategory(category: AbilityCategory): CategoryDefinition?
    return currentConfig.categories[category]
end

-- Get UI configuration
function AbilityConfiguration.GetUIConfig(): UIConfiguration
    return currentConfig.ui
end

-- Update configuration (merge with existing)
function AbilityConfiguration.UpdateConfig(updates: {[string]: any})
    -- Deep merge the updates
    for key, value in pairs(updates) do
        if typeof(value) == "table" and typeof(currentConfig[key]) == "table" then
            -- Merge tables
            for subKey, subValue in pairs(value) do
                currentConfig[key][subKey] = subValue
            end
        else
            currentConfig[key] = value
        end
    end
    
    -- Notify listeners
    for _, callback in ipairs(configChangeCallbacks) do
        task.spawn(callback, currentConfig)
    end
end

-- Subscribe to configuration changes
function AbilityConfiguration.OnConfigChanged(callback: (config: Configuration) -> ()): () -> ()
    table.insert(configChangeCallbacks, callback)
    
    -- Return disconnect function
    return function()
        local index = table.find(configChangeCallbacks, callback)
        if index then
            table.remove(configChangeCallbacks, index)
        end
    end
end

-- Load configuration from DataStore or ModuleScript
function AbilityConfiguration.LoadConfig(source: ModuleScript | {[string]: any}?)
    if source then
        if typeof(source) == "Instance" and source:IsA("ModuleScript") then
            local loadedConfig = require(source)
            if loadedConfig and loadedConfig.version then
                currentConfig = loadedConfig
            end
        elseif typeof(source) == "table" then
            currentConfig = source :: any
        end
    end
end

-- Export for type checking
export type AbilityConfiguration = typeof(AbilityConfiguration)

return AbilityConfiguration