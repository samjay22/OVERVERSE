--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types: {  } = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

local Config: {
    ABILITY_CLASS: string,
    ANIMATION_NAME: string,
    REQUIRES_TARGET: boolean,
    HEAL_AMOUNT : number,
    HEAL_RANGE_MULTIPLIER: number,
    OVERHEAL_PERCENTAGE: number,

    ANIM_FADE_TIME: number,
    ANIM_PRIORITY: Enum.AnimationPriority,

    PROJECTILE_SPEED: number,
    SPIRAL_RADIUS: number,
    SPIRAL_FREQUENCY: number,
    PROJECTILE_SIZE: Vector3,
    PROJECTILE_COLOR: Color3,

    EFFECT_CLEANUP_TIME: number,
    LIGHT_BRIGHTNESS: number,
    LIGHT_RANGE: number,
    PARTICLE_RATE: number,
    ABILITY_CATEGORY: Types.AbilityCategory,
    
    -- Primary ability uses ammo system instead of cooldown
    ATTACK_RANGE: number,
    MAX_AMMO: number,
    RELOAD_TIME: number,
    
    -- Audio Configuration
    SOUND_CAST_ID: string,
    SOUND_IMPACT_ID: string,
    SOUND_VOLUME: number,
} = {
    -- Ability Configuration
    ABILITY_CLASS = "Dash",
    ANIMATION_NAME = "Dash",
    REQUIRES_TARGET = false,
    HEAL_AMOUNT = 0, -- No healing for dash
    HEAL_RANGE_MULTIPLIER = 1.0, -- Not used for dash
    OVERHEAL_PERCENTAGE = 0, -- Not used for dash

    -- Animation Constants
    ANIM_FADE_TIME = 0.125,
    ANIM_PRIORITY = Enum.AnimationPriority.Action4,

    -- Projectile Constants (not used for dash)
    PROJECTILE_SPEED = 0, -- No projectile
    SPIRAL_RADIUS = 0, -- No spiral
    SPIRAL_FREQUENCY = 0, -- No spiral
    PROJECTILE_SIZE = Vector3.new(0, 0, 0), -- No projectile
    PROJECTILE_COLOR = Color3.new(0.5, 0.5, 1), -- Blue color for dash effects

    -- Effect Constants
    EFFECT_CLEANUP_TIME = 2.5,
    LIGHT_BRIGHTNESS = 4, -- Brighter healing light
    LIGHT_RANGE = 10, -- Larger light range
    PARTICLE_RATE = 40, -- More particles for better visibility
    ABILITY_CATEGORY = "Active",
    
    -- Dash ability configuration
    ATTACK_RANGE = 50, -- Dash distance
    COOLDOWN_TIME = 5.0, -- Cooldown per charge
    FIRE_RATE = 0.2, -- Minimum time between dashes (prevent spam)
    
    -- Audio Configuration
    SOUND_CAST_ID = "rbxasset://sounds/electronicpingshort.wav", -- Default Roblox sound
    SOUND_IMPACT_ID = "rbxasset://sounds/impact_generic.mp3", -- Default Roblox sound
    SOUND_VOLUME = 0.5,
}

return Config