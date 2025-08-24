
export type GameTimestamp = number

-- Class identifier type used for filtering abilities by player class attribute
export type ClassId = string | number

-- Ability categorization for clearer separation of logic
export type AbilityCategory = "Primary" | "Active" | "Passive" | "Secondary" | "Ultimate"

export type AbilityPackage = {
    Config : ModuleScript,
    Assets : Folder,
    Server : ModuleScript,
    Client : ModuleScript,
    Shared : ModuleScript
}

export type Shared = {
    IsValid : (ctx: SharedAbilityContext) -> boolean,
    GetConfig : () -> AbilityConfig,
    GetAssets : () -> Folder,
}

export type AbilityConfig = {
    ABILITY_CATEGORY : AbilityCategory,
    REQUIRES_TARGET : boolean,
    ATTACK_RANGE : number,
    COOLDOWN_TIME : number?, -- Optional for ammo-based abilities
    MAX_AMMO : number?, -- Optional for cooldown-based abilities
    RELOAD_TIME : number?, -- Optional for cooldown-based abilities
    [string] : any,
}
-- Belongs to ClientAbilityPackage.Client module
export type ClientAbility = {
    OnReplicate : (ctx: SharedAbilityContext, serverData: any?) -> (),
    OnCast : (ctx: SharedAbilityContext) -> (),
    OnCancel : (ctx: SharedAbilityContext, reason: string?) -> (),
    GetSharedModule : () -> Shared
}

export type ServerAbility = {
    OnRequest : (ctx: SharedAbilityContext) -> AbilityResult,
    GetSharedModule : () -> Shared
}

export type StateSnapshot = {
    timestamp: GameTimestamp,
    position: Vector3?,
    velocity: Vector3?,
    health: number?,
    stamina: number?,
    cooldowns: {[string]: number}?,
    effects: {[string]: any}?,
    passiveModifiers: {[string]: number}?, -- New: for passive ability effects
}

export type SharedAbilityContext = {
    playerId: number,
    abilityId: number,
    timestamp: GameTimestamp,
    inputData: {
        position: Vector3?,
        direction: Vector3?,
        target: Vector3?,
        mouseHit: Vector3?,
        extraData: {[string]: any}?,
    },
    characterState: StateSnapshot,
}

-- Minimal client result: only success and cooldowns (flat)
export type AbilityResult = {
    success: boolean,
    reason: string?,
    cooldowns: {[string]: number}?,
}

-- Export type constants for runtime use
return {
    AbilityCategory = {
        Primary = "Primary",
        Active = "Active", 
        Passive = "Passive",
        Secondary = "Secondary",
        Ultimate = "Ultimate"
    }
}
