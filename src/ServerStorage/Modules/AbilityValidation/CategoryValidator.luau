--!strict
-- Server-side validator using unified system
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UnifiedValidator = require(ReplicatedStorage.Modules.Core.UnifiedValidator)
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

type ValidationResult = { success: boolean, reason: string? }

local CategoryValidator = {}

function CategoryValidator.ValidateAbility(
    abilityModule: Types.ServerAbility,
    context: Types.SharedAbilityContext
): ValidationResult
    return UnifiedValidator.Validate(abilityModule, context, true)
end

-- Legacy compatibility
CategoryValidator.ValidatePrimary = CategoryValidator.ValidateAbility
CategoryValidator.ValidateActive = CategoryValidator.ValidateAbility
CategoryValidator.ValidatePassive = CategoryValidator.ValidateAbility
CategoryValidator.ValidateSecondary = CategoryValidator.ValidateAbility
CategoryValidator.ValidateUltimate = CategoryValidator.ValidateAbility

return CategoryValidator