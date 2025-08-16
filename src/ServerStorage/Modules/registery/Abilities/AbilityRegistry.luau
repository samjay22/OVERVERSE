--!strict
-- Improved Ability Registry using the new Registry system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(game.ServerStorage.Modules.Core.Registry)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)
local Enums = require(ReplicatedStorage.Modules.Types.Enums)

export type AbilityDef = AbilityTypes.AbilityDef
export type ActiveAbilityDef = AbilityTypes.ActiveAbilityDef
export type PassiveAbilityDef = AbilityTypes.PassiveAbilityDef
export type ToggleAbilityDef = AbilityTypes.ToggleAbilityDef
export type AbilityId = AbilityTypes.AbilityId

-- Validation function for ability definitions
local function validateAbilityDefinition(data: any): (boolean, AbilityDef?)
	if typeof(data) ~= "table" then
		return false, nil
	end
	
	-- Check required fields
	if typeof(data.id) ~= "string" or data.id == "" then
		warn("Ability definition missing or invalid id")
		return false, nil
	end
	
	if typeof(data.type) ~= "string" or (data.type ~= "Active" and data.type ~= "Passive" and data.type ~= "Toggle") then
		warn(`Ability definition '{data.id}' has invalid type: {data.type}`)
		return false, nil
	end
	
	if typeof(data.name) ~= "string" or data.name == "" then
		warn(`Ability definition '{data.id}' missing or invalid name`)
		return false, nil
	end
	
	if typeof(data.description) ~= "string" then
		warn(`Ability definition '{data.id}' missing or invalid description`)
		return false, nil
	end
	
	-- Type-specific validation
	if data.type == "Active" then
		if typeof(data.serverActivate) ~= "function" then
			warn(`Active ability '{data.id}' missing serverActivate function`)
			return false, nil
		end
	elseif data.type == "Passive" then
		if not data.onEquip and not data.onTick and not data.onUnequip then
			warn(`Passive ability '{data.id}' missing callback functions`)
			return false, nil
		end
	elseif data.type == "Toggle" then
		if typeof(data.onActivate) ~= "function" or typeof(data.onDeactivate) ~= "function" then
			warn(`Toggle ability '{data.id}' missing toggle functions`)
			return false, nil
		end
	end
	
	return true, data
end

-- Create the registry instance
local abilityRegistry = Registry.New(validateAbilityDefinition)

local AbilityRegistry = {}

-- Core registry functions
function AbilityRegistry.Register(id: AbilityId, definition: AbilityDef): ()
	abilityRegistry:Register(id, definition)
end

function AbilityRegistry.Get(id: AbilityId): AbilityDef?
	return abilityRegistry:Get(id)
end

function AbilityRegistry.GetAll(): {[string]: AbilityDef}
	return abilityRegistry:GetAll() :: any
end

function AbilityRegistry.Has(id: AbilityId): boolean
	return abilityRegistry:Has(id)
end

function AbilityRegistry.Remove(id: AbilityId): boolean
	return abilityRegistry:Remove(id)
end

function AbilityRegistry.LoadFromFolder(folder: Folder): number
	return abilityRegistry:LoadFromFolder(folder)
end

function AbilityRegistry.Count(): number
	return abilityRegistry:Count()
end

function AbilityRegistry.GetIds(): {string}
	return abilityRegistry:GetIds()
end

-- Type-specific getters
function AbilityRegistry.GetActive(id: AbilityId): ActiveAbilityDef?
	local ability = abilityRegistry:Get(id)
	if ability and ability.type == "Active" then
		return ability :: ActiveAbilityDef
	end
	return nil
end

function AbilityRegistry.GetPassive(id: AbilityId): PassiveAbilityDef?
	local ability = abilityRegistry:Get(id)
	if ability and ability.type == "Passive" then
		return ability :: PassiveAbilityDef
	end
	return nil
end

function AbilityRegistry.GetToggle(id: AbilityId): ToggleAbilityDef?
	local ability = abilityRegistry:Get(id)
	if ability and ability.type == "Toggle" then
		return ability :: ToggleAbilityDef
	end
	return nil
end

function AbilityRegistry.GetByType(abilityType: Enums.AbilityType): {[string]: AbilityDef}
	local abilities = {}
	for id, definition in pairs(abilityRegistry:GetAll()) do
		if definition.type == abilityType then
			abilities[id] = definition
		end
	end
	return abilities
end

function AbilityRegistry.GetAllActives(): {[string]: ActiveAbilityDef}
	local actives = {}
	for id, definition in pairs(abilityRegistry:GetAll()) do
		if definition.type == "Active" then
			actives[id] = definition :: ActiveAbilityDef
		end
	end
	return actives
end

function AbilityRegistry.GetAllPassives(): {[string]: PassiveAbilityDef}
	local passives = {}
	for id, definition in pairs(abilityRegistry:GetAll()) do
		if definition.type == "Passive" then
			passives[id] = definition :: PassiveAbilityDef
		end
	end
	return passives
end

function AbilityRegistry.GetAllToggles(): {[string]: ToggleAbilityDef}
	local toggles = {}
	for id, definition in pairs(abilityRegistry:GetAll()) do
		if definition.type == "Toggle" then
			toggles[id] = definition :: ToggleAbilityDef
		end
	end
	return toggles
end

-- Utility functions
function AbilityRegistry.ValidateDefinition(definition: any): (boolean, AbilityDef?)
	return validateAbilityDefinition(definition)
end

function AbilityRegistry.GetHandlerName(): string
	return "Abilities"
end

-- Auto-load abilities from the Definitions folder
local function autoLoadAbilities()
	local definitionsFolder = script.Parent:FindFirstChild("Definitions")
	if definitionsFolder then
		local loaded = AbilityRegistry.LoadFromFolder(definitionsFolder)
		print(`AbilityRegistry: Loaded {loaded} abilities`)
	else
		warn("AbilityRegistry: No Definitions folder found")
	end
end

-- Initialize on first require
autoLoadAbilities()

return AbilityRegistry
