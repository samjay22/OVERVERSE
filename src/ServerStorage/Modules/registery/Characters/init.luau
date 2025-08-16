--!strict
-- Character class registry using Core.Registry (inlined)

local Registry = require(game.ServerStorage.Modules.Core.Registry)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

export type CharacterDefinition = CharacterTypes.CharacterDefinition

local function validate(def: any): (boolean, CharacterDefinition?)
	if typeof(def) ~= "table" then return false, nil end
	if typeof(def.id) ~= "string" or def.id == "" then
		warn("CharacterDefinition missing id")
		return false, nil
	end
	return true, def
end

local reg = Registry.New(validate)

local CharacterRegistry = {}

function CharacterRegistry.Register(id: string, def: CharacterDefinition)
	reg:Register(id, def)
end

function CharacterRegistry.Get(id: string): CharacterDefinition?
	return reg:Get(id)
end

function CharacterRegistry.GetAll(): {[string]: CharacterDefinition}
	return reg:GetAll() :: any
end

function CharacterRegistry.Has(id: string): boolean
	return reg:Has(id)
end

function CharacterRegistry.Remove(id: string): boolean
	return reg:Remove(id)
end

function CharacterRegistry.LoadFromFolder(folder: Folder): number
	return reg:LoadFromFolder(folder)
end

function CharacterRegistry.GetIds(): {string}
	return reg:GetIds()
end

function CharacterRegistry.Count(): number
	return reg:Count()
end

function CharacterRegistry.GetHandlerName(): string
	return "Characters"
end

local function autoLoad()
	local defs = script:FindFirstChild("Definitions")
	if defs then
		local n = CharacterRegistry.LoadFromFolder(defs)
		print(`CharacterRegistry: Loaded {n} character classes`)
	else
		warn("CharacterRegistry: No Definitions folder")
	end
end

autoLoad()

return CharacterRegistry
