--!strict
-- Types for client-server prediction system
-- Following SOLID principles: Single Responsibility, Interface Segregation

-- Import shared enums
export type AbilityId = "Dash" | "Keen" | "Heal" | "Block" | "Parry" | "Charge" | "Slam" | "Thrust"

-- Prediction unique identifier for tracking client predictions
export type PredictionId = string

-- Timestamp for synchronization and rollback
export type GameTimestamp = number

-- State snapshot for rollback capabilities (ACID properties)
export type StateSnapshot = {
    timestamp: GameTimestamp,
    position: Vector3?,
    velocity: Vector3?,
    health: number?,
    stamina: number?,
    cooldowns: {[AbilityId]: number}?,
    effects: {[string]: any}?,
    -- Add more state as needed
}

-- Client prediction request - atomicity principle
export type PredictionRequest = {
    predictionId: PredictionId,
    timestamp: GameTimestamp,
    abilityId: AbilityId,
    inputData: {
        position: Vector3?,
        direction: Vector3?,
        target: Vector3?,
        mouseHit: Vector3?,
        extraData: {[string]: any}?,
    },
    preExecutionState: StateSnapshot,
}

-- Server validation result - consistency principle  
export type ValidationResult = {
    predictionId: PredictionId,
    timestamp: GameTimestamp,
    success: boolean,
    reason: string?,
    correctedState: StateSnapshot?,
    authorizedEffects: {[string]: any}?,
}

-- Prediction status for client tracking
export type PredictionStatus = "pending" | "confirmed" | "rejected" | "timed_out"

-- Client prediction entry - durability through persistence
export type ClientPrediction = {
    id: PredictionId,
    timestamp: GameTimestamp,
    status: PredictionStatus,
    request: PredictionRequest,
    result: ValidationResult?,
    rollbackData: StateSnapshot,
    timeoutHandle: thread?,
}

-- Network packet for batched communication (performance optimization)
export type PredictionBatch = {
    timestamp: GameTimestamp,
    requests: {PredictionRequest}?,
    validations: {ValidationResult}?,
}

-- Ability execution context shared between client and server
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

-- Result of ability execution (shared logic)
export type SharedAbilityResult = {
    success: boolean,
    reason: string?,
    stateChanges: {
        position: Vector3?,
        velocity: Vector3?,
        health: number?,
        stamina: number?,
        cooldowns: {[AbilityId]: number}?,
        effects: {[string]: any}?,
    }?,
    visualEffects: {{
        effect: string,
        position: Vector3?,
        direction: Vector3?,
        duration: number?,
        extraData: {[string]: any}?,
    }}?,
    soundEffects: {{
        sound: string,
        position: Vector3?,
        volume: number?,
        pitch: number?,
    }}?,
}

-- Interface for ability implementations (Interface Segregation Principle)
export type IAbilityExecutor = {
    CanExecute: (context: SharedAbilityContext) -> boolean,
    Execute: (context: SharedAbilityContext) -> SharedAbilityResult,
    GetCooldown: () -> number,
    GetStaminaCost: () -> number,
}

-- Interface for state management (Single Responsibility)
export type IStateManager = {
    CreateSnapshot: () -> StateSnapshot,
    ApplySnapshot: (snapshot: StateSnapshot) -> (),
    GetTimestamp: () -> GameTimestamp,
}

-- Interface for prediction reconciliation (Dependency Inversion)
export type IPredictionReconciler = {
    SubmitPrediction: (request: PredictionRequest) -> (),
    ValidatePrediction: (request: PredictionRequest) -> ValidationResult,
    ReconcileState: (validation: ValidationResult) -> (),
}

-- Network optimization interface (Open/Closed Principle)
export type INetworkOptimizer = {
    ShouldBatch: () -> boolean,
    CreateBatch: (items: {any}) -> PredictionBatch,
    ProcessBatch: (batch: PredictionBatch) -> (),
}

return {}
