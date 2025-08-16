--!strict
-- ImprovedAbilityRegistry: Unified ability registry using BaseRegistry pattern
-- Provides better error handling, validation, and consistent interface

local BaseRegistry = require(game.ServerStorage.Modules.Core.BaseRegistry)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

export type AbilityId = AbilityTypes.AbilityId
export type AbilityDef = AbilityTypes.AbilityDef
export type ActiveAbilityDef = AbilityTypes.ActiveAbilityDef
export type PassiveAbilityDef = AbilityTypes.PassiveAbilityDef
export type ToggleAbilityDef = AbilityTypes.ToggleAbilityDef

local ImprovedAbilityRegistry = {}

-- Validation function for abilities
local function validateAbilityDefinition(data: any): (boolean, AbilityDef?)
	if typeof(data) ~= "table" then
		return false, nil
	end
	
	-- Required fields
	if not data.id or typeof(data.id) ~= "string" then
		warn("Ability definition missing or invalid id field")
		return false, nil
	end
	
	if not data.type or typeof(data.type) ~= "string" then
		warn(`Ability {data.id} missing or invalid type field`)
		return false, nil
	end
	
	if not data.name or typeof(data.name) ~= "string" then
		warn(`Ability {data.id} missing or invalid name field`)
		return false, nil
	end
	
	-- Type-specific validation
	if data.type == "Active" then
		-- No serverActivate required; abilities execute on client with server-side validation
	elseif data.type == "Passive" then
		-- Passive abilities should have at least one of: onEquip, onUnequip, onTick
		if not (data.onEquip or data.onUnequip or data.onTick) then
			warn(`Passive ability {data.id} has no passive effects`)
			return false, nil
		end
	elseif data.type == "Toggle" then
		if not data.onActivate or typeof(data.onActivate) ~= "function" then
			warn(`Toggle ability {data.id} missing onActivate function`)
			return false, nil
		end
		if not data.onDeactivate or typeof(data.onDeactivate) ~= "function" then
			warn(`Toggle ability {data.id} missing onDeactivate function`)
			return false, nil
		end
	else
		warn(`Ability {data.id} has unknown type: {data.type}`)
		return false, nil
	end
	
	return true, data
end

-- Transform function to normalize ability data
local function transformAbilityDefinition(data: any): AbilityDef
	-- Ensure numeric fields have defaults
	data.cooldown = data.cooldown or 0
	data.staminaCost = data.staminaCost or 0
	data.manaCost = data.manaCost or 0
	data.level = data.level or 1
	
	-- Ensure arrays exist
	data.tags = data.tags or {}
	
	-- Normalize description
	data.description = data.description or ""
	
	return data
end

-- Custom loader for ability modules
local function loadAbilityModule(moduleScript: ModuleScript): AbilityDef?
	local success, result = pcall(require, moduleScript)
	if not success then
		warn(`Failed to require ability module {moduleScript.Name}: {result}`)
		return nil
	end
	
	-- Handle different module formats
	if typeof(result) == "table" then
		-- Single ability definition
		if result.id and result.type then
			return result
		end
		
		-- Multiple definitions in .Definitions array
		if result.Definitions and typeof(result.Definitions) == "table" then
			-- Return first definition (BaseRegistry will call this for each child)
			-- This is a limitation we'll handle differently
			return result.Definitions[1]
		end
	end
	
	warn(`Ability module {moduleScript.Name} has invalid format`)
	return nil
end

-- Initialize the registry
local abilityRegistry = BaseRegistry.New({
	name = "AbilityRegistry",
	validate = validateAbilityDefinition,
	transform = transformAbilityDefinition,
	loader = loadAbilityModule,
	autoLoad = false, -- We'll manually load to control the folder path
	definitionsFolder = "Definitions",
})

-- Manual load from the correct definitions folder
local function loadAbilities()
	-- This module lives in Modules/registery, so Abilities is a sibling under the parent 'Modules'
	local modulesFolder = script.Parent and script.Parent.Parent
	local abilitiesFolder = modulesFolder and modulesFolder:FindFirstChild("Abilities")
	local definitionsFolder = abilitiesFolder and abilitiesFolder:FindFirstChild("Definitions")
	if definitionsFolder then
		local loaded = 0
		for _, child in ipairs(definitionsFolder:GetChildren()) do
			if child:IsA("ModuleScript") then
				local success, result = pcall(loadAbilityModule, child)
				if success and result then
					local isValid, validatedDef = validateAbilityDefinition(result)
					if isValid and validatedDef then
						local transformedDef = transformAbilityDefinition(validatedDef)
						abilityRegistry:Register(transformedDef.id, transformedDef)
						loaded += 1
					end
				else
					warn(`ImprovedAbilityRegistry: Failed to load {child.Name}: {result}`)
				end
			end
		end
		print(`ImprovedAbilityRegistry: Loaded {loaded} abilities`)
	else
		warn("ImprovedAbilityRegistry: No Definitions folder found at expected path")
	end
end

-- Load abilities on initialization
loadAbilities()

-- Public interface
function ImprovedAbilityRegistry.Get(id: AbilityId): AbilityDef?
	return abilityRegistry:Get(id)
end

function ImprovedAbilityRegistry.GetAll(): {[AbilityId]: AbilityDef}
	return abilityRegistry:GetAll()
end

function ImprovedAbilityRegistry.GetActive(id: AbilityId): ActiveAbilityDef?
	local ability = abilityRegistry:Get(id)
	if ability and ability.type == "Active" then
		return (ability :: any) :: ActiveAbilityDef
	end
	return nil
end

function ImprovedAbilityRegistry.GetPassive(id: AbilityId): PassiveAbilityDef?
	local ability = abilityRegistry:Get(id)
	if ability and ability.type == "Passive" then
		return (ability :: any) :: PassiveAbilityDef
	end
	return nil
end

function ImprovedAbilityRegistry.GetToggle(id: AbilityId): ToggleAbilityDef?
	local ability = abilityRegistry:Get(id)
	if ability and ability.type == "Toggle" then
		return (ability :: any) :: ToggleAbilityDef
	end
	return nil
end

function ImprovedAbilityRegistry.GetAllActives(): {[AbilityId]: ActiveAbilityDef}
	local allAbilities = abilityRegistry:GetAll()
	local actives: {[AbilityId]: ActiveAbilityDef} = {}
	
	for id, ability in pairs(allAbilities) do
		if ability.type == "Active" then
			actives[id] = (ability :: any) :: ActiveAbilityDef
		end
	end
	
	return actives
end

function ImprovedAbilityRegistry.GetAllPassives(): {[AbilityId]: PassiveAbilityDef}
	local allAbilities = abilityRegistry:GetAll()
	local passives: {[AbilityId]: PassiveAbilityDef} = {}
	
	for id, ability in pairs(allAbilities) do
		if ability.type == "Passive" then
			passives[id] = (ability :: any) :: PassiveAbilityDef
		end
	end
	
	return passives
end

function ImprovedAbilityRegistry.GetAllToggles(): {[AbilityId]: ToggleAbilityDef}
	local allAbilities = abilityRegistry:GetAll()
	local toggles: {[AbilityId]: ToggleAbilityDef} = {}
	
	for id, ability in pairs(allAbilities) do
		if ability.type == "Toggle" then
			toggles[id] = (ability :: any) :: ToggleAbilityDef
		end
	end
	
	return toggles
end

-- Registry management
function ImprovedAbilityRegistry.Register(id: AbilityId, ability: AbilityDef): ()
	abilityRegistry:Register(id, ability)
end

function ImprovedAbilityRegistry.Has(id: AbilityId): boolean
	return abilityRegistry:Has(id)
end

function ImprovedAbilityRegistry.Count(): number
	return abilityRegistry:Count()
end

function ImprovedAbilityRegistry.GetIds(): {AbilityId}
	return abilityRegistry:GetIds()
end

-- Filtering by tags
function ImprovedAbilityRegistry.GetByTag(tag: string): {[AbilityId]: AbilityDef}
	local allAbilities = abilityRegistry:GetAll()
	local tagged: {[AbilityId]: AbilityDef} = {}
	
	for id, ability in pairs(allAbilities) do
		if (ability :: any).tags and table.find((ability :: any).tags, tag) then
			tagged[id] = ability
		end
	end
	
	return tagged
end

-- Filtering by level
function ImprovedAbilityRegistry.GetByLevel(minLevel: number, maxLevel: number?): {[AbilityId]: AbilityDef}
	local allAbilities = abilityRegistry:GetAll()
	local filtered: {[AbilityId]: AbilityDef} = {}
	local max = maxLevel or math.huge
	
	for id, ability in pairs(allAbilities) do
		local level = (ability :: any).level or 1
		if level >= minLevel and level <= max then
			filtered[id] = ability
		end
	end
	
	return filtered
end

-- Utility functions
function ImprovedAbilityRegistry.ValidateDefinition(definition: any): (boolean, AbilityDef?)
	return validateAbilityDefinition(definition)
end

function ImprovedAbilityRegistry.GetHandlerName(): string
	return "Abilities"
end

-- Reload abilities (useful for development)
function ImprovedAbilityRegistry.Reload(): number
	-- Clear existing abilities by removing all
	for id, _ in pairs(abilityRegistry:GetAll()) do
		abilityRegistry:Remove(id)
	end
	
	-- Reload from definitions folder
	loadAbilities()
	return abilityRegistry:Count()
end

-- Get registry statistics
function ImprovedAbilityRegistry.GetStats(): {[string]: number}
	local allAbilities = abilityRegistry:GetAll()
	local stats = {
		total = 0,
		active = 0,
		passive = 0,
		toggle = 0,
		unknown = 0,
	}
	
	for _, ability in pairs(allAbilities) do
		stats.total += 1
		if ability.type == "Active" then
			stats.active += 1
		elseif ability.type == "Passive" then
			stats.passive += 1
		elseif ability.type == "Toggle" then
			stats.toggle += 1
		else
			stats.unknown += 1
		end
	end
	
	return stats
end

-- Debug function to print all abilities
function ImprovedAbilityRegistry.DebugPrint(): ()
	local stats = ImprovedAbilityRegistry.GetStats()
	print(`\n=== Ability Registry Debug ===`)
	print(`Total abilities: {stats.total}`)
	print(`Active: {stats.active}, Passive: {stats.passive}, Toggle: {stats.toggle}`)
	
	if stats.unknown > 0 then
		print(`Unknown types: {stats.unknown}`)
	end
	
	local allAbilities = abilityRegistry:GetAll()
	for id, ability in pairs(allAbilities) do
		local tags = if (ability :: any).tags and #(ability :: any).tags > 0 then table.concat((ability :: any).tags, ", ") else "none"
		print(`  {id} ({ability.type}) - {ability.name} [tags: {tags}]`)
	end
	print(`=== End Debug ===\n`)
end

return ImprovedAbilityRegistry
