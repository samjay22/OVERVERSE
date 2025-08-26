--!strict
-- ComponentManager - Handles component registration, initialization, and updates
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)
local BaseComponent = require(game.ServerStorage.Modules.Components.BaseComponent)

type ComponentInterface = CharacterTypes.ComponentInterface
type internalCharacter = CharacterTypes.internalCharacter
type CharacterConfig = CharacterTypes.CharacterConfig
type BaseComponentType = BaseComponent.BaseComponent

export type ComponentUpdater = {
	name: string,
	fn: (internalCharacter, number) -> ()
}

export type IComponentManager = {
	RegisterComponent: (self: IComponentManager, name: string, component: ComponentInterface | BaseComponentType) -> (),
	UnregisterComponent: (self: IComponentManager, name: string) -> (),
	InitializeComponents: (self: IComponentManager, characterData: internalCharacter, config: CharacterConfig?) -> (),
	UpdateComponents: (self: IComponentManager, characterData: internalCharacter, dt: number) -> (),
	CleanupComponents: (self: IComponentManager, characterData: internalCharacter) -> (),
	GetComponent: (self: IComponentManager, name: string) -> (ComponentInterface | BaseComponentType)?,
	GetAllComponents: (self: IComponentManager) -> {[string]: ComponentInterface | BaseComponentType},
	EnableComponent: (self: IComponentManager, characterData: internalCharacter, name: string) -> (),
	DisableComponent: (self: IComponentManager, characterData: internalCharacter, name: string) -> (),
	IsComponentEnabled: (self: IComponentManager, characterData: internalCharacter, name: string) -> boolean,
}

local ComponentManager = {}
ComponentManager.__index = ComponentManager

function ComponentManager.new(): IComponentManager
	local self = setmetatable({}, ComponentManager)
	
	self._components = {} :: {[string]: ComponentInterface | BaseComponentType}
	self._updaters = {} :: {ComponentUpdater}
	
	-- Performance optimization: Pre-allocate arrays for hot paths
	self._updateOrder = {} :: {string} -- Cached update order for better performance
	self._criticalComponents = {} :: {string} -- Components that must update every frame
	self._deferredComponents = {} :: {string} -- Components that can skip frames
	
	return (self :: any) :: IComponentManager
end

function ComponentManager:RegisterComponent(name: string, component: ComponentInterface | BaseComponentType)
	if self._components[name] then
		warn(`Component {name} already registered, overwriting`)
	end
	
	self._components[name] = component
	
	-- Cache updater if present with performance classification
	if component and component.Update and typeof(component.Update) == "function" then
		-- Handle both old-style and new BaseComponent-style components
		local updateFn = function(characterData, dt)
			-- Check if it's a BaseComponent with self parameter
			if (component :: any).Name and (component :: any).IsEnabled then
				return component.Update(component, characterData, dt)
			else
				-- Old-style component
				return component.Update(characterData, dt)
			end
		end
		
		table.insert(self._updaters, { name = name, fn = updateFn })
		
		-- Classify component for performance optimization
		local isCritical = self:_IsCriticalComponent(name)
		if isCritical then
			table.insert(self._criticalComponents, name)
		else
			table.insert(self._deferredComponents, name)
		end
	end
	
	-- Rebuild update order cache
	self:_BuildUpdateOrder()
end

-- Determine if a component needs critical (every frame) updates
function ComponentManager:_IsCriticalComponent(componentName: string): boolean
	local criticalComponents = {
		"Health", "Movement", "Combat", "Input", "Mouse"
	}
	
	for _, critical in ipairs(criticalComponents) do
		if componentName == critical then
			return true
		end
	end
	return false
end

-- Build optimized update order based on dependencies
function ComponentManager:_BuildUpdateOrder()
	table.clear(self._updateOrder)
	
	-- Add critical components first
	for _, name in ipairs(self._criticalComponents) do
		table.insert(self._updateOrder, name)
	end
	
	-- Add deferred components
	for _, name in ipairs(self._deferredComponents) do
		table.insert(self._updateOrder, name)
	end
end

function ComponentManager:UnregisterComponent(name: string)
	self._components[name] = nil
	
	-- Remove any cached updater entries for this component name
	for i = #self._updaters, 1, -1 do
		if self._updaters[i].name == name then
			table.remove(self._updaters, i)
		end
	end
end

function ComponentManager:InitializeComponents(characterData: internalCharacter, config: CharacterConfig?)
	for componentName, component in pairs(self._components) do
		if component.Initialize then
			local componentConfig = config
			
			-- Special handling for Ability component - inject default loadout if not provided
			if componentName == "Ability" then
				local Constants = require(game.ReplicatedStorage.Modules.Utility.Constants)
				local AbilityLoadouts = require(game.ServerStorage.Modules.registery.Loadouts)
				
				local assetKey = Constants.CHARACTER_ASSET_DEFAULT
				local loadout = AbilityLoadouts.Get(assetKey)
				local merged = table.clone(config or {}) :: any
				local abilityLoadout = (config and ((config :: any).AbilityLoadout :: any)) or loadout
				merged.AbilityLoadout = abilityLoadout
				componentConfig = merged :: any
			end
			
			-- Initialize component with character data and config
			-- Handle both old-style and new BaseComponent-style components
			local success, err
			if (component :: any).Name and (component :: any).IsEnabled then
				-- BaseComponent style
				success, err = pcall(component.Initialize, component, characterData, componentConfig)
			else
				-- Old style
				success, err = pcall(component.Initialize, characterData, componentConfig)
			end
			
			if not success then
				warn(`Failed to initialize component {componentName}: {err}`)
			end
		end
	end
end

function ComponentManager:UpdateComponents(characterData: internalCharacter, dt: number)
	-- Optimized update using cached updater list and error resilience
	local updateCount = #self._updaters
	local failedComponents = 0
	
	for i = 1, updateCount do
		local entry = self._updaters[i]
		local success = pcall(entry.fn, characterData, dt)
		if not success then
			failedComponents = failedComponents + 1
			-- Only warn periodically to avoid spam
			if failedComponents <= 3 then
				warn(`Component {entry.name} update failed`)
			end
		end
	end
	
	-- Report excessive failures
	if failedComponents > updateCount * 0.5 then
		warn(`High component failure rate: {failedComponents}/{updateCount} components failed`)
	end
end

function ComponentManager:CleanupComponents(characterData: internalCharacter)
	for componentName, component in pairs(self._components) do
		if component.Cleanup then
			local success, err
			if (component :: any).Name and (component :: any).IsEnabled then
				-- BaseComponent style
				success, err = pcall(component.Cleanup, component, characterData)
			else
				-- Old style
				success, err = pcall(component.Cleanup, characterData)
			end
			
			if not success then
				warn(`Failed to cleanup component {componentName}: {err}`)
			end
		end
	end
end

function ComponentManager:GetComponent(name: string): (ComponentInterface | BaseComponentType)?
	return self._components[name]
end

function ComponentManager:GetAllComponents(): {[string]: ComponentInterface | BaseComponentType}
	return table.clone(self._components)
end

function ComponentManager:EnableComponent(characterData: internalCharacter, name: string)
	local component = self._components[name]
	if component and (component :: any).Enable then
		(component :: any):Enable(characterData)
	end
end

function ComponentManager:DisableComponent(characterData: internalCharacter, name: string)
	local component = self._components[name]
	if component and (component :: any).Disable then
		(component :: any):Disable(characterData)
	end
end

function ComponentManager:IsComponentEnabled(characterData: internalCharacter, name: string): boolean
	local component = self._components[name]
	if component and (component :: any).IsEnabled then
		return (component :: any):IsEnabled(characterData)
	end
	return true -- Default to enabled for old-style components
end

return ComponentManager
