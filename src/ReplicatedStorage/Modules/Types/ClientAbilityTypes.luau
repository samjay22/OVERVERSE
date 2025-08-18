
export type AbilityId = "Dash" | "Keen" | "Heal" | "Block" | "Parry" | "Charge" | "Slam" | "Thrust"
export type GameTimestamp = number

-- Class identifier type used for filtering abilities by player class attribute
export type ClassId = string | number

export type StateSnapshot = {
    timestamp: GameTimestamp,
    position: Vector3?,
    velocity: Vector3?,
    health: number?,
    stamina: number?,
    cooldowns: {[string]: number}?,
    effects: {[string]: any}?,
}

export type SharedAbilityContext = {
    playerId: number,
    abilityId: AbilityId,
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

-- Each client ability module should return a table implementing this interface.
-- onRequest: invoked immediately on input to predict and drive local feedback.
-- onCast: invoked when the server confirms the cast; do authoritative VFX/SFX here.
-- OnCancel: invoked when the server rejects/cancels; revert visuals or state.
export type ClientAbilityModule = {
  -- Back-compat adapter for older callers
	onCast: (ctx: SharedAbilityContext) -> AbilityResult,
	onConfirm: ((ctx: SharedAbilityContext, serverData: any?) -> ())?,
	onReject: ((ctx: SharedAbilityContext, reason: string?) -> ())?,

	-- New static interface surface (delegates to per-ability module when present)
	onRequest: ((ctx: SharedAbilityContext) -> AbilityResult)?,
	OnCancel: ((ctx: SharedAbilityContext, reason: string?) -> ())?,

    getAbilityInputRequired : () -> Enum.KeyCode | Enum.UserInputType,
    -- Optional flag to indicate which class can use this ability. Return nil for "any class".
    getAbilityClassId: () -> ClassId?,
    getAbilityRange: () -> number?,
    getRequiresTarget: () -> boolean?
}

return {}
