--!strict
-- Keen ability - passive ability that enhances perception and awareness

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage.Modules.Types.Enums)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

local Effects = require(game.ReplicatedStorage.Modules.AssetHandlers).OnModuleLoaded("Effects") :: any

-- Keen passive effects
local KEEN_DAMAGE_BONUS: number = 0.15 -- 15% damage increase
local KEEN_CRIT_CHANCE_BONUS: number = 0.10 -- 10% increased critical hit chance
local KEEN_DETECTION_RANGE_BONUS: number = 1.5 -- 50% increased detection range
local KEEN_MOVEMENT_SPEED_BONUS: number = 0.05 -- 5% movement speed increase

local function onEquip(context: AbilityTypes.AbilityContext): ()
    print("Equipping Keen ability...")

    local aura = Effects.GetAsset("RemAura").Instance

	local character: AbilityTypes.CharacterRef = context.character
	if not character.Character or not character.Humanoid then
		return
	end

    local newAura = aura:Clone()
    newAura.Parent = character.Character.PrimaryPart

	local humanoid: Humanoid = character.Humanoid :: Humanoid
	
	-- Apply movement speed bonus
	local baseWalkSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = baseWalkSpeed * (1 + KEEN_MOVEMENT_SPEED_BONUS)
	
	-- Store original values for cleanup
	character.StateManager:Set("KeenOriginalWalkSpeed", baseWalkSpeed)
	
	-- Apply damage and crit bonuses via modifiers
	local currentModifiers = character.StateManager:Get("DamageModifiers") or {}
	currentModifiers.KeenDamage = KEEN_DAMAGE_BONUS
	character.StateManager:Set("DamageModifiers", currentModifiers)
	
	local currentCritModifiers = character.StateManager:Get("CritChanceModifiers") or {}
	currentCritModifiers.KeenCrit = KEEN_CRIT_CHANCE_BONUS
	character.StateManager:Set("CritChanceModifiers", currentCritModifiers)
	
	-- Apply detection range bonus
	local currentDetectionModifiers = character.StateManager:Get("DetectionModifiers") or {}
	currentDetectionModifiers.KeenDetection = KEEN_DETECTION_RANGE_BONUS
	character.StateManager:Set("DetectionModifiers", currentDetectionModifiers)
	
	-- Set keen state
	character.StateManager:Set("HasKeen", true)
	
	print(`Keen activated for {character.Player.Name} - Enhanced awareness and combat prowess`)
end

local function onUnequip(context: AbilityTypes.AbilityContext): ()
	local character: AbilityTypes.CharacterRef = context.character
	if not character.Character or not character.Humanoid then
		return
	end

	local humanoid: Humanoid = character.Humanoid :: Humanoid
	
	-- Restore original movement speed
	local originalWalkSpeed = character.StateManager:Get("KeenOriginalWalkSpeed")
	if originalWalkSpeed then
		humanoid.WalkSpeed = originalWalkSpeed
		character.StateManager:Set("KeenOriginalWalkSpeed", nil)
	end
	
	-- Remove damage modifiers
	local currentModifiers = character.StateManager:Get("DamageModifiers") or {}
	currentModifiers.KeenDamage = nil
	character.StateManager:Set("DamageModifiers", currentModifiers)
	
	-- Remove crit modifiers
	local currentCritModifiers = character.StateManager:Get("CritChanceModifiers") or {}
	currentCritModifiers.KeenCrit = nil
	character.StateManager:Set("CritChanceModifiers", currentCritModifiers)
	
	-- Remove detection modifiers
	local currentDetectionModifiers = character.StateManager:Get("DetectionModifiers") or {}
	currentDetectionModifiers.KeenDetection = nil
	character.StateManager:Set("DetectionModifiers", currentDetectionModifiers)
	
	-- Remove keen state
	character.StateManager:Set("HasKeen", false)
	
	print(`Keen deactivated for {character.Player.Name}`)
end

local function onTick(context: AbilityTypes.AbilityContext, deltaTime: number): ()
	local character: AbilityTypes.CharacterRef = context.character

	-- Keen provides passive regeneration of stamina
	local STAMINA_REGEN_RATE = 2.0 -- 2 stamina per second
	local currentStamina = character.StateManager:Get("Stamina") or 0
	local maxStamina = character.StateManager:Get("MaxStamina") or 100
	
	if currentStamina < maxStamina then
		local newStamina = math.min(maxStamina, currentStamina + (STAMINA_REGEN_RATE * deltaTime))
		character.StateManager:Set("Stamina", newStamina)
	end
	
	-- Enhanced awareness - detect nearby enemies (could be expanded for PvP)
	local hasKeen = character.StateManager:Get("HasKeen")
	if hasKeen then
		-- This could be used to highlight enemies, show danger indicators, etc.
		-- For now, we'll just maintain the keen state
	end
end

-- Export the ability definition
return {
	id = Enums.AbilityId.Keen,
	type = "Passive" :: "Passive",
	name = "Keen",
	description = "Heightened awareness and combat reflexes. Increases damage, critical hit chance, movement speed, and provides stamina regeneration.",
	level = 1,
	tags = {"Combat", "Passive", "Enhancement", "Awareness"},
	
	-- Passive ability callbacks
	onEquip = onEquip,
	onUnequip = onUnequip,
	onTick = onTick,
	
	-- Modifiers that this ability provides
	modifiers = {
		damage = KEEN_DAMAGE_BONUS,
		critChance = KEEN_CRIT_CHANCE_BONUS,
		movementSpeed = KEEN_MOVEMENT_SPEED_BONUS,
		detectionRange = KEEN_DETECTION_RANGE_BONUS,
	},
}
