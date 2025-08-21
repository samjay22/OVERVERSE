--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientAbilityTypes = require(game.ReplicatedStorage.Modules.Types.ClientAbilityTypes)

export type AbilityId = string
export type StateSnapshot = ClientAbilityTypes.StateSnapshot
export type AbilityResult = ClientAbilityTypes.AbilityResult
export type SharedAbilityContext = ClientAbilityTypes.SharedAbilityContext
export type ClientAbilityModule = ClientAbilityTypes.ClientAbilityModule

export type PredictionRequest = {
    predictionId: string,
    abilityId: AbilityId,
    inputData: {[string]: any},
    timestamp: number,
    originalState: StateSnapshot,
}

export type ValidationResult = {
    predictionId: string,
    success: boolean,
    reason: string?,
    correctedState: StateSnapshot?,
    authorizedEffects: {[string]: any}?,
}

return {}
