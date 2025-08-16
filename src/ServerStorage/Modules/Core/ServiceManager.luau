--!strict
-- ServiceManager: Centralized service lifecycle and dependency management
-- Provides dependency injection, service lifecycle, and organized service initialization

local CoreTypes = require(game.ServerStorage.Modules.Types.CoreTypes)

export type ServiceDefinition<T> = CoreTypes.ServiceDefinition<T>
export type ServiceManager = CoreTypes.ServiceManager
export type ServiceId = CoreTypes.ServiceId

type ServiceEntry = {
	instance: any,
	definition: ServiceDefinition<any>,
	initialized: boolean,
	started: boolean,
}

local ServiceManager = {}
ServiceManager.__index = ServiceManager

function ServiceManager.New(): ServiceManager
	local self = setmetatable({}, ServiceManager)
	
	self._services = {} :: {[ServiceId]: ServiceEntry}
	self._dependencies = {} :: {[ServiceId]: {ServiceId}}
	self._dependents = {} :: {[ServiceId]: {ServiceId}}
	self._initOrder = {} :: {ServiceId}
	
	return (self :: any) :: ServiceManager
end

-- Register a service with its definition
function ServiceManager:Register<T>(definition: ServiceDefinition<T>): ()
	if self._services[definition.id] then
		warn(`ServiceManager: Service '{definition.id}' already registered`)
		return
	end
	
	local entry: ServiceEntry = {
		instance = definition.data,
		definition = definition,
		initialized = false,
		started = false,
	}
	
	self._services[definition.id] = entry
	
	-- Track dependencies if specified
	if definition.dependencies then
		self._dependencies[definition.id] = definition.dependencies
		
		-- Build reverse dependency graph
		for _, depId in ipairs(definition.dependencies) do
			if not self._dependents[depId] then
				self._dependents[depId] = {}
			end
			table.insert(self._dependents[depId], definition.id)
		end
	end
end

-- Get a service instance
function ServiceManager:Get<T>(serviceId: ServiceId): T?
	local entry = self._services[serviceId]
	if not entry then
		warn(`ServiceManager: Service '{serviceId}' not found`)
		return nil
	end
	
	if not entry.initialized then
		self:_InitializeService(serviceId)
	end
	
	return entry.instance
end

-- Initialize a specific service and its dependencies
function ServiceManager:_InitializeService(serviceId: ServiceId): ()
	local entry = self._services[serviceId]
	if not entry or entry.initialized then
		return
	end
	
	-- Initialize dependencies first
	local deps = self._dependencies[serviceId]
	if deps then
		for _, depId in ipairs(deps) do
			self:_InitializeService(depId)
		end
	end
	
	-- Initialize the service
	if entry.definition.initialize then
		local success, err = pcall(entry.definition.initialize, entry.instance)
		if not success then
			warn(`ServiceManager: Failed to initialize service '{serviceId}': {err}`)
			return
		end
	end
	
	entry.initialized = true
	table.insert(self._initOrder, serviceId)
end

-- Start a specific service
function ServiceManager:Start(serviceId: ServiceId): ()
	local entry = self._services[serviceId]
	if not entry then
		warn(`ServiceManager: Service '{serviceId}' not found`)
		return
	end
	
	if not entry.initialized then
		self:_InitializeService(serviceId)
	end
	
	if entry.started then
		return
	end
	
	if entry.definition.start then
		local success, err = pcall(entry.definition.start, entry.instance)
		if not success then
			warn(`ServiceManager: Failed to start service '{serviceId}': {err}`)
			return
		end
	end
	
	entry.started = true
end

-- Stop a specific service
function ServiceManager:Stop(serviceId: ServiceId): ()
	local entry = self._services[serviceId]
	if not entry or not entry.started then
		return
	end
	
	-- Stop dependents first
	local dependents = self._dependents[serviceId]
	if dependents then
		for _, depId in ipairs(dependents) do
			self:Stop(depId)
		end
	end
	
	if entry.definition.stop then
		local success, err = pcall(entry.definition.stop, entry.instance)
		if not success then
			warn(`ServiceManager: Failed to stop service '{serviceId}': {err}`)
		end
	end
	
	entry.started = false
end

-- Start all registered services
function ServiceManager:StartAll(): ()
	for serviceId in pairs(self._services) do
		if not self._services[serviceId].started then
			self:Start(serviceId)
		end
	end
end

-- Stop all services in reverse order
function ServiceManager:StopAll(): ()
	-- Stop in reverse initialization order
	for i = #self._initOrder, 1, -1 do
		self:Stop(self._initOrder[i])
	end
end

-- Update all services that have an update method
function ServiceManager:Update(deltaTime: number): ()
	for _, entry in pairs(self._services) do
		if entry.started and entry.definition.update then
			local success, err = pcall(entry.definition.update, entry.instance, deltaTime)
			if not success then
				warn(`ServiceManager: Update failed for service '{entry.definition.id}': {err}`)
			end
		end
	end
end

-- Get all registered service IDs
function ServiceManager:GetServiceIds(): {ServiceId}
	local ids = {}
	for id in pairs(self._services) do
		table.insert(ids, id)
	end
	return ids
end

-- Check if a service is registered
function ServiceManager:HasService(serviceId: ServiceId): boolean
	return self._services[serviceId] ~= nil
end

-- Get service status
function ServiceManager:GetStatus(serviceId: ServiceId): {initialized: boolean, started: boolean}?
	local entry = self._services[serviceId]
	if not entry then
		return nil
	end
	
	return {
		initialized = entry.initialized,
		started = entry.started,
	}
end

return ServiceManager
