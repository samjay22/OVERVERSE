--!strict
-- Client-side validator using unified system
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UnifiedValidator = require(ReplicatedStorage.Modules.Core.UnifiedValidator)
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

type ValidationResult = { success: boolean, reason: string? }

local ClientCategoryValidator = {}

function ClientCategoryValidator.ValidateAbility(
    abilityModule: Types.ClientAbility,
    context: Types.SharedAbilityContext
): ValidationResult
    return UnifiedValidator.Validate(abilityModule, context, false)
end

-- Legacy compatibility (can be removed later)
ClientCategoryValidator.ValidatePrimary = ClientCategoryValidator.ValidateAbility
ClientCategoryValidator.ValidateActive = ClientCategoryValidator.ValidateAbility
ClientCategoryValidator.ValidatePassive = ClientCategoryValidator.ValidateAbility
ClientCategoryValidator.ValidateSecondary = ClientCategoryValidator.ValidateAbility
ClientCategoryValidator.ValidateUltimate = ClientCategoryValidator.ValidateAbility

return ClientCategoryValidator