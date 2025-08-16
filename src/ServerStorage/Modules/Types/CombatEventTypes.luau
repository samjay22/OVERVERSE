--!strict
-- Static types for combat events and payloads

export type AttackRequested = (attackType: string?) -> ()
export type BlockRequested = (shouldBlock: boolean) -> ()
export type DamageRequested = (damage: number, canBlock: boolean?) -> ()

export type AttackPerformed = (success: boolean, attackType: string?, combo: number) -> ()
export type BlockStateChanged = (isBlocking: boolean) -> ()
export type DamageApplied = (amount: number, wasBlocked: boolean?) -> ()
export type GuardChanged = (newGuard: number, oldGuard: number) -> ()
export type GuardBroken = () -> ()
export type ComboChanged = (combo: number) -> ()
export type Tick = (dt: number) -> ()

export type ICombatEventBus = {
    -- request-side
    AttackRequested: { Connect: (self: any, fn: AttackRequested) -> RBXScriptConnection, Fire: (self: any, attackType: string?) -> () },
    BlockRequested: { Connect: (self: any, fn: BlockRequested) -> RBXScriptConnection, Fire: (self: any, shouldBlock: boolean) -> () },
    DamageRequested: { Connect: (self: any, fn: DamageRequested) -> RBXScriptConnection, Fire: (self: any, damage: number, canBlock: boolean?) -> () },

    -- notify-side
    AttackPerformed: { Connect: (self: any, fn: AttackPerformed) -> RBXScriptConnection, Fire: (self: any, success: boolean, attackType: string?, combo: number) -> () },
    BlockStateChanged: { Connect: (self: any, fn: BlockStateChanged) -> RBXScriptConnection, Fire: (self: any, isBlocking: boolean) -> () },
    DamageApplied: { Connect: (self: any, fn: DamageApplied) -> RBXScriptConnection, Fire: (self: any, amount: number, wasBlocked: boolean?) -> () },
    GuardChanged: { Connect: (self: any, fn: GuardChanged) -> RBXScriptConnection, Fire: (self: any, newGuard: number, oldGuard: number) -> () },
    GuardBroken: { Connect: (self: any, fn: GuardBroken) -> RBXScriptConnection, Fire: (self: any) -> () },
    ComboChanged: { Connect: (self: any, fn: ComboChanged) -> RBXScriptConnection, Fire: (self: any, combo: number) -> () },
    Tick: { Connect: (self: any, fn: Tick) -> RBXScriptConnection, Fire: (self: any, dt: number) -> () },
}

return 0
