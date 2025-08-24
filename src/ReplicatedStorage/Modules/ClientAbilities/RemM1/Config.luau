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
    ABILITY_CLASS = "Rem",
    ANIMATION_NAME = "M1",
    REQUIRES_TARGET = true,
    HEAL_AMOUNT = 45, -- Increased healing to make it more impactful
    HEAL_RANGE_MULTIPLIER = 0.8, -- Allow healing at 80% of max range for flexibility
    OVERHEAL_PERCENTAGE = 0.15, -- Allow 15% overheal for strategic play

    -- Animation Constants
    ANIM_FADE_TIME = 0.125,
    ANIM_PRIORITY = Enum.AnimationPriority.Action4,

    -- Projectile Constants
    PROJECTILE_SPEED = 95, -- Slightly faster for responsiveness
    SPIRAL_RADIUS = 3.5, -- Tighter spiral for precision
    SPIRAL_FREQUENCY = 8, -- More spiral rotations for visual appeal
    PROJECTILE_SIZE = Vector3.new(0.4, 0.4, 0.4), -- Slightly larger
    PROJECTILE_COLOR = Color3.new(0.15, 1, 0.4), -- More vibrant healing color

    -- Effect Constants
    EFFECT_CLEANUP_TIME = 2.5,
    LIGHT_BRIGHTNESS = 4, -- Brighter healing light
    LIGHT_RANGE = 10, -- Larger light range
    PARTICLE_RATE = 40, -- More particles for better visibility
    ABILITY_CATEGORY = "Primary",
    
    -- Primary ability resource system (ammo instead of cooldown)
    ATTACK_RANGE = 120, -- Increased range for better utility
    MAX_AMMO = 6, -- 6 healing shots before reload
    RELOAD_TIME = 2.5, -- 2.5 second reload time
    COOLDOWN_TIME = 1.6, -- Cooldown between shots
    
    -- Audio Configuration
    SOUND_CAST_ID = "rbxasset://sounds/electronicpingshort.wav", -- Default Roblox sound
    SOUND_IMPACT_ID = "rbxasset://sounds/impact_generic.mp3", -- Default Roblox sound
    SOUND_VOLUME = 0.5,
}

return Config