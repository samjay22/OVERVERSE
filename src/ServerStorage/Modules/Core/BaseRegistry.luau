--!strict
-- BaseRegistry: Abstract base class for all registry implementations
-- Provides consistent interface and auto-loading capabilities

local Registry = require(game.ServerStorage.Modules.Core.Registry)
local CoreTypes = require(game.ServerStorage.Modules.Types.CoreTypes)

export type IRegistry<T> = CoreTypes.IRegistry<T>
export type RegistryId = CoreTypes.RegistryId

type ValidationFunction<T> = (data: any) -> (boolean, T?)
type TransformFunction<T> = (data: any) -> T
type LoaderFunction<T> = (moduleScript: ModuleScript) -> T?

type BaseRegistryConfig<T> = {
	name: string,
	validate: ValidationFunction<T>?,
	transform: TransformFunction<T>?,
	loader: LoaderFunction<T>?,
	autoLoad: boolean?,
	definitionsFolder: string?,
}

local BaseRegistry = {}
BaseRegistry.__index = BaseRegistry

function BaseRegistry.New<T>(config: BaseRegistryConfig<T>): IRegistry<T>
	local self = setmetatable({}, BaseRegistry)
	
	self._name = config.name
	self._registry = Registry.New(config.validate, config.transform)
	self._loader = config.loader
	self._loaded = false
	
	-- Auto-load if specified
	if config.autoLoad ~= false then
		self:_AutoLoad(config.definitionsFolder or "Definitions")
	end
	
	return (self :: any) :: IRegistry<T>
end

-- Register an item
function BaseRegistry:Register<T>(id: RegistryId, item: T): ()
	self._registry:Register(id, item)
end

-- Get an item by ID
function BaseRegistry:Get<T>(id: RegistryId): T?
	return self._registry:Get(id)
end

-- Get all items
function BaseRegistry:GetAll<T>(): {[RegistryId]: T}
	return self._registry:GetAll()
end

-- Check if an item exists
function BaseRegistry:Has(id: RegistryId): boolean
	return self._registry:Has(id)
end

-- Remove an item
function BaseRegistry:Remove(id: RegistryId): boolean
	return self._registry:Remove(id)
end

-- Load from folder using base registry logic
function BaseRegistry:LoadFromFolder<T>(folder: Folder): number
	return self._registry:LoadFromFolder(folder)
end

-- Get all IDs
function BaseRegistry:GetIds(): {RegistryId}
	return self._registry:GetIds()
end

-- Get count
function BaseRegistry:Count(): number
	return self._registry:Count()
end

-- Auto-load definitions from a folder
function BaseRegistry:_AutoLoad(folderName: string): ()
	if self._loaded then
		return
	end
	
	local definitionsFolder = script:FindFirstChild(folderName)
	if not definitionsFolder then
		warn(`{self._name}: No '{folderName}' folder found`)
		return
	end
	
	local loaded = 0
	
	if self._loader then
		-- Use custom loader
		for _, child in ipairs(definitionsFolder:GetChildren()) do
			if child:IsA("ModuleScript") then
				local success, result = pcall(self._loader, child)
				if success and result then
					local id = self:_ExtractId(child, result)
					self:Register(id, result)
					loaded += 1
				else
					warn(`{self._name}: Failed to load module '{child.Name}': {result}`)
				end
			end
		end
	else
		-- Use default loading
		loaded = self:LoadFromFolder(definitionsFolder)
	end
	
	self._loaded = true
	print(`{self._name}: Loaded {loaded} items`)
end

-- Extract ID from module or result
function BaseRegistry:_ExtractId(moduleScript: ModuleScript, result: any): string
	-- Prefer explicit ID from result
	if typeof(result) == "table" and typeof(result.id) == "string" then
		return result.id
	end
	
	-- Fall back to module name
	return moduleScript.Name
end

-- Get registry name for debugging
function BaseRegistry:GetName(): string
	return self._name
end

-- Force reload
function BaseRegistry:Reload(folderName: string?): number
	self._loaded = false
	self._registry:Clear()
	self:_AutoLoad(folderName or "Definitions")
	return self:Count()
end

return BaseRegistry
