local Config = {
    REQUIRES_TARGET = true,
    ATTACK_RANGE = 150,
    ABILITY_CATEGORY = "Active",
    COOLDOWN_TIME = 12.0, -- 12 second cooldown for smoke
    FIRE_RATE = 0.5, -- Minimum time between casts (prevent spam)
    DAMAGE = 0, -- Smoke doesn't do damage
    ANIMATION = "M1",
    PROJECTILE_SPEED = 100,
}

return Config :: typeof(Config)