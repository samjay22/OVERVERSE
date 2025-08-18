--!strict
-- ComponentManager - Handles component registration, initialization, and updates
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

type ComponentInterface = CharacterTypes.ComponentInterface
type internalCharacter = CharacterTypes.internalCharacter
type CharacterConfig = CharacterTypes.CharacterConfig

export type ComponentUpdater = {
	name: string,
	fn: (internalCharacter, number) -> ()
}

export type IComponentManager = {
	RegisterComponent: (self: IComponentManager, name: string, component: ComponentInterface) -> (),
	UnregisterComponent: (self: IComponentManager, name: string) -> (),
	InitializeComponents: (self: IComponentManager, characterData: internalCharacter, config: CharacterConfig?) -> (),
	UpdateComponents: (self: IComponentManager, characterData: internalCharacter, dt: number) -> (),
	CleanupComponents: (self: IComponentManager, characterData: internalCharacter) -> (),
	GetComponent: (self: IComponentManager, name: string) -> ComponentInterface?,
	GetAllComponents: (self: IComponentManager) -> {[string]: ComponentInterface},
}

local ComponentManager = {}
ComponentManager.__index = ComponentManager

function ComponentManager.new(): IComponentManager
	local self = setmetatable({}, ComponentManager)
	
	self._components = {} :: {[string]: ComponentInterface}
	self._updaters = {} :: {ComponentUpdater}
	
	return self
end

function ComponentManager:RegisterComponent(name: string, component: ComponentInterface)
	if self._components[name] then
		warn(`Component {name} already registered, overwriting`)
	end
	
	self._components[name] = component
	
	-- Cache updater if present
	if component and component.Update and typeof(component.Update) == "function" then
		table.insert(self._updaters, { name = name, fn = component.Update })
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
			local success, err = pcall(component.Initialize, characterData, componentConfig)
			if not success then
				warn(`Failed to initialize component {componentName}: {err}`)
			end
		end
	end
end

function ComponentManager:UpdateComponents(characterData: internalCharacter, dt: number)
	-- Update components using cached updater list for performance
	for i = 1, #self._updaters do
		local entry = self._updaters[i]
		local success, err = pcall(entry.fn, characterData, dt)
		if not success then
			warn(`Component {entry.name} update failed: {err}`)
		end
	end
end

function ComponentManager:CleanupComponents(characterData: internalCharacter)
	for componentName, component in pairs(self._components) do
		if component.Cleanup then
			local success, err = pcall(component.Cleanup, characterData)
			if not success then
				warn(`Failed to cleanup component {componentName}: {err}`)
			end
		end
	end
end

function ComponentManager:GetComponent(name: string): ComponentInterface?
	return self._components[name]
end

function ComponentManager:GetAllComponents(): {[string]: ComponentInterface}
	return table.clone(self._components)
end

return ComponentManager
