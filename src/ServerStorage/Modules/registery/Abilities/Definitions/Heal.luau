--!strict
-- Heal ability - restoration ability

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage.Modules.Types.Enums)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

local HEAL_AMOUNT: number = 50
local HEAL_COOLDOWN: number = 8 -- seconds
local HEAL_STAMINA_COST: number = 20
local HEAL_RANGE: number = 10 -- studs

local function performHeal(context: AbilityTypes.AbilityContext): AbilityTypes.AbilityResult
	local character: AbilityTypes.CharacterRef = context.character
	if not character.Character or not character.Humanoid then
		return {
			success = false,
			errorMessage = "No character model or Humanoid",
		}
	end

	local humanoid: Humanoid = character.Humanoid :: Humanoid
	local currentHealth = humanoid.Health
	local maxHealth = humanoid.MaxHealth
	
	-- Check if healing is needed
	if currentHealth >= maxHealth then
		return {
			success = false,
			errorMessage = "Already at full health",
		}
	end
	
	-- Calculate actual heal amount
	local actualHealAmount = math.min(HEAL_AMOUNT, maxHealth - currentHealth)
	
	-- Apply healing
	humanoid.Health = currentHealth + actualHealAmount
	
	-- Set character state briefly
	character.StateManager:Set("IsHealing", true)
	task.spawn(function()
		task.wait(1) -- Brief heal animation time
		character.StateManager:Set("IsHealing", false)
	end)
	
	return {
		success = true,
		data = {
			healAmount = actualHealAmount,
			newHealth = humanoid.Health,
			maxHealth = maxHealth,
		},
	}
end

-- Export the ability definition
return {
	id = Enums.AbilityId.Heal,
	type = "Active" :: "Active",
	name = "Heal",
	description = "Restore health to yourself or a target",
	targetType = "Self" :: "Self",
	cooldown = HEAL_COOLDOWN,
	staminaCost = HEAL_STAMINA_COST,
	range = HEAL_RANGE,
	castTime = 1,
	interruptible = true,
	serverActivate = performHeal,
}
