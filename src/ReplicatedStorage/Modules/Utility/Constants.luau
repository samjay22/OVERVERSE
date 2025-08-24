--!strict

export type StateValidator = (value: any) -> boolean
export type StateDefinition = {
    default: any,
    validator: StateValidator,
}

export type RegenRate = {
    regenRate: number,
    depleteRate: number?,
}

export type Constants = {
    DEFAULT_RESPAWN_TIME: number,
    BINDABLE_EVENT_POOL_SIZE: number,
    SHIFT_LOCK_OFFSET: Vector3,
    CHARACTER_STATE_DEFINITIONS: {[string]: StateDefinition},
    REGEN_RATES: {[string]: RegenRate},
    ATTACK_COOLDOWN: number,
    ATTACK_STAMINA_COST: number,
    BLOCK_EFFICIENCY: number,
    COMBO_RESET_TIME: number,
    GUARD_BREAK_RECOVERY_TIME: number,
    CHARACTER_ASSET_DEFAULT: string,
    ROBLOX_ANIMATION_SCRIPT: string,
    DEFAULT_BLOCKED_SPEED: number,
    DEFAULT_STUNNED_SPEED: number,
    DEFAULT_WALK_SPEED: number,
    DEFAULT_RUN_SPEED: number,
    DEFAULT_JUMP_POWER: number,
}

local constants: Constants = {
    DEFAULT_RESPAWN_TIME = 5,
    BINDABLE_EVENT_POOL_SIZE = 5000,
    SHIFT_LOCK_OFFSET =  Vector3.new(3, 0.25, 0),

    CHARACTER_STATE_DEFINITIONS = {
        Health = {
            default = 100,
            validator = function(v) return type(v) == "number" and v >= 0 end,
        },
        -- Unified form/state used by some character classes (e.g., Human/Beast or Rem/Ram)
        -- Provide a safe default so code paths relying on ShiftState work for all characters.
        MaxHealth = {
            default = 100,
            validator = function(v) return type(v) == "number" and v > 0 end,
        },
        Stamina = {
            default = 100,
            validator = function(v) return type(v) == "number" and v >= 0 end,
        },
        MaxStamina = {
            default = 100,
            validator = function(v) return type(v) == "number" and v > 0 end,
        },
        Guard = {
            default = 100,
            validator = function(v) return type(v) == "number" and v >= 0 end,
        },
        MaxGuard = {
            default = 100,
            validator = function(v) return type(v) == "number" and v > 0 end,
        },
        IsDead = {
            default = false,
            validator = function(v) return type(v) == "boolean" end,
        },
        IsRunning = {
            default = false,
            validator = function(v) return type(v) == "boolean" end,
        },
        IsBlocking = {
            default = false,
            validator = function(v) return type(v) == "boolean" end,
        },
        IsStunned = {
            default = false,
            validator = function(v) return type(v) == "boolean" end,
        },
        IsDashing = {
            default = false,
            validator = function(v) return type(v) == "boolean" end,
        },
        LastDamage = {
            default = 0,
            validator = function(v) return type(v) == "number" and v >= 0 end,
        },

        -- Buff/Debuff-derived modifiers (available on character state)
        -- Multipliers default to 1 and allow non-negative values; bonuses default to 0 and allow any number.
        OutgoingDamageMult = {
            default = 1,
            validator = function(v) return type(v) == "number" and v >= 0 end,
        },
        IncomingDamageMult = {
            default = 1,
            validator = function(v) return type(v) == "number" and v >= 0 end,
        },
        StaminaCostMult = {
            default = 1,
            validator = function(v) return type(v) == "number" and v >= 0 end,
        },
        AttackCooldownMult = {
            default = 1,
            validator = function(v) return type(v) == "number" and v >= 0 end,
        },
        GuardRegenMult = {
            default = 1,
            validator = function(v) return type(v) == "number" and v >= 0 end,
        },
        StaminaRegenBonus = {
            default = 0,
            validator = function(v) return type(v) == "number" end,
        },
        CritChance = {
            default = 0,
            validator = function(v) return type(v) == "number" and v >= 0 end,
        },
        CritDamage = {
            default = 0,
            validator = function(v) return type(v) == "number" end,
        },

        -- Input state reported from client (sanitized/used server-side only)
        ActiveKeys = {
            default = {},
            validator = function(v) return type(v) == "table" end,
        },
    },

    REGEN_RATES = {
        Stamina = {
            regenRate = 10,
            depleteRate = 20,
        },
        Guard = {
            regenRate = 5,
        },
    },

    -- Combat tuning
    ATTACK_COOLDOWN = 0.25, -- seconds between attacks
    ATTACK_STAMINA_COST = 2, -- stamina cost per attack
    BLOCK_EFFICIENCY = 0.5, -- portion of damage that goes to guard when blocking (0.0-1.0)
    COMBO_RESET_TIME = 3, -- seconds to reset combo counter after last attack
    GUARD_BREAK_RECOVERY_TIME = 2, -- seconds stunned after guard breaks

    CHARACTER_ASSET_DEFAULT = "Default", -- Default character asset name
    ROBLOX_ANIMATION_SCRIPT = "71137563547577", -- Default Roblox Animate script asset ID

    DEFAULT_BLOCKED_SPEED = 8, -- Default speed when blocked
    DEFAULT_STUNNED_SPEED = 4, -- Default speed when stunned
    DEFAULT_WALK_SPEED = 16, -- Default walk speed
    DEFAULT_RUN_SPEED = 26, -- Default run speed
    DEFAULT_JUMP_POWER = 50, -- Default jump power
}

return constants