--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = {
    -- Ability Configuration
    ABILITY_CLASS = "Rem",
    ANIMATION_NAME = "M1",
    REQUIRES_TARGET = true,

    -- Animation Constants
    ANIM_FADE_TIME = 0.125,
    ANIM_PRIORITY = Enum.AnimationPriority.Action4,

    -- Projectile Constants
    PROJECTILE_SPEED = 75, -- Faster projectile for M2

    -- Effect Constants
    PROJECTILE_LIFETIME = 2.5,
    ABILITY_CATEGORY = "Primary",
    
    -- Primary ability resource system (ammo-based)
    ATTACK_RANGE = 100, -- Slightly shorter range
    MAX_AMMO = 12, -- 12 ammo total (4 bursts of 3 shots each)
    RELOAD_TIME = 4, -- 4 second reload
    FIRE_RATE = 0.3, -- Minimum time between burst triggers
    BURST_COUNT = 3, -- 3 shots per burst
    BURST_DELAY = 0.1, -- Delay between each shot in the burst
    -- Note: Each trigger consumes 3 ammo (1 per shot in burst)
    
    -- Audio Configuration
    SOUND_CAST_ID = "rbxasset://sounds/electronicpingshort.wav", -- Default Roblox sound
    SOUND_IMPACT_ID = "rbxasset://sounds/impact_generic.mp3", -- Default Roblox sound
    SOUND_VOLUME = 0.4, -- Volume level
}

return Config