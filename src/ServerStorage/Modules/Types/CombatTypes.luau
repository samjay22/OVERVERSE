--!strict
-- Static types for Combat service and data

local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

export type AttackType = string

export type CombatPerCharacter = {
    LastAttackTime: number,
    LastBlockTime: number,
    ComboCount: number,
    GuardBreakRecovery: number,
}

export type CombatConfig = {
    ATTACK_COOLDOWN: number,
    ATTACK_STAMINA_COST: number,
    BLOCK_EFFICIENCY: number,
    COMBO_RESET_TIME: number,
    GUARD_BREAK_RECOVERY_TIME: number,
}

export type ICombatService = {
    Initialize: (self: ICombatService, character: CharacterTypes.Character, config: CombatConfig?) -> (),
    Update: (self: ICombatService, character: CharacterTypes.Character, dt: number) -> (),
    PerformAttack: (self: ICombatService, character: CharacterTypes.Character, attackType: AttackType?) -> boolean,
    PerformBlock: (self: ICombatService, character: CharacterTypes.Character, shouldBlock: boolean) -> boolean,
    TakeDamage: (self: ICombatService, character: CharacterTypes.Character, damage: number, canBlock: boolean?) -> number,
    HandleGuardBreak: (self: ICombatService, character: CharacterTypes.Character) -> (),
}

return 0
