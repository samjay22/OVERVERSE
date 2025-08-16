--!strict
-- Generic Registry system for dynamic content loading with strong typing

local CoreTypes = require(game.ServerStorage.Modules.Types.CoreTypes)

export type IRegistry<T> = CoreTypes.IRegistry<T>
export type RegistryId = CoreTypes.RegistryId

type RegistryItem<T> = {
	id: RegistryId,
	data: T,
	metadata: {[string]: any}?,
}

type ValidationFunction<T> = (data: any) -> (boolean, T?)
type TransformFunction<T> = (data: any) -> T

local Registry = {}
Registry.__index = Registry

function Registry.New<T>(
	validate: ValidationFunction<T>?,
	transform: TransformFunction<T>?
): IRegistry<T>
	local self = setmetatable({}, Registry)
	
	self._items = {} :: {[RegistryId]: T}
	self._metadata = {} :: {[RegistryId]: {[string]: any}}
	self._validate = validate
	self._transform = transform
	
	return (self :: any) :: IRegistry<T>
end

function Registry:Register<T>(id: RegistryId, item: T): ()
	if self._validate then
		local isValid, transformedItem = self._validate(item)
		if not isValid then
			warn(`Registry: Invalid item for id '{id}'`)
			return
		end
		if transformedItem then
			item = transformedItem
		end
	end
	
	if self._transform then
		item = self._transform(item)
	end
	
	self._items[id] = item
end

function Registry:Get<T>(id: RegistryId): T?
	return self._items[id]
end

function Registry:GetAll<T>(): {[RegistryId]: T}
	return table.clone(self._items)
end

function Registry:Has(id: RegistryId): boolean
	return self._items[id] ~= nil
end

function Registry:Remove(id: RegistryId): boolean
	if self._items[id] then
		self._items[id] = nil
		self._metadata[id] = nil
		return true
	end
	return false
end

function Registry:LoadFromFolder<T>(folder: Folder): number
	local loaded = 0
	
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local success, result = pcall(require, child)
			if success and result then
				local id = child.Name
				
				-- If the module exports an id field, use that instead
				if typeof(result) == "table" and typeof(result.id) == "string" then
					id = result.id
				end
				
				self:Register(id, result)
				loaded += 1
			else
				warn(`Registry: Failed to load module '{child.Name}': {result}`)
			end
		end
	end
	
	return loaded
end

function Registry:GetIds(): {RegistryId}
	local ids = {}
	for id in pairs(self._items) do
		table.insert(ids, id)
	end
	return ids
end

function Registry:Count(): number
	local count = 0
	for _ in pairs(self._items) do
		count += 1
	end
	return count
end

function Registry:SetMetadata(id: RegistryId, metadata: {[string]: any}): ()
	if self._items[id] then
		self._metadata[id] = metadata
	end
end

function Registry:GetMetadata(id: RegistryId): {[string]: any}?
	return self._metadata[id]
end

function Registry:Clear(): ()
	table.clear(self._items)
	table.clear(self._metadata)
end

return Registry
