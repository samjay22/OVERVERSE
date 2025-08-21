--!strict
-- ServiceFactory: Bootstraps and configures all services with proper dependency injection
-- Provides centralized service initialization and lifecycle management

local ServiceManager = require(game.ServerStorage.Modules.Core.ServiceManager)
local CharacterService = require(game.ServerStorage.Modules.Services.CharacterService)
local AbilityService = require(game.ServerStorage.Modules.Services.AbilityService)
local InputHandler = require(game.ServerStorage.Modules.Handlers.InputHandler)
-- Ability registry removed
local ErrorHandler = require(game.ServerStorage.Modules.Handlers.ErrorHandler)

export type ServiceFactory = {
	CreateServices: () -> ServiceManager.ServiceManager,
	GetGlobalServiceManager: () -> ServiceManager.ServiceManager?,
}

local ServiceFactory = {}
local globalServiceManager: ServiceManager.ServiceManager? = nil

-- Create and configure all services
function ServiceFactory.CreateServices(): ServiceManager.ServiceManager
	local serviceManager = ServiceManager.New()
	
	-- Set up error handling
	ErrorHandler.SetLogLevel("INFO")
	
	-- Create service instances
	local characterService = CharacterService.New()
	local inputHandler = InputHandler.New({
		characterService = characterService,
		abilityService = nil, -- Will be set after ability service is created
	})
	
	local abilityService = AbilityService.New()
	
	-- Wire up cross-dependencies
	inputHandler:SetAbilityService(abilityService)
	
	-- Register services with the service manager
	serviceManager:Register({
		id = "CharacterService",
		data = characterService,
		initialize = function(service)
			ErrorHandler.Info("Initializing CharacterService")
			-- Character service doesn't need special initialization
		end,
		start = function(service)
			ErrorHandler.Info("Starting CharacterService")
			-- Start any background processes if needed
		end,
		stop = function(service)
			ErrorHandler.Info("Stopping CharacterService")
			-- Clean up if needed
		end,
	})
	
	serviceManager:Register({
		id = "AbilityService",
		data = abilityService,
		dependencies = {"CharacterService"},
		initialize = function(service)
			ErrorHandler.Info("Initializing AbilityService")
		end,
		start = function(service)
			ErrorHandler.Info("Starting AbilityService")
		end,
	})
	
	serviceManager:Register({
		id = "InputHandler",
		data = inputHandler,
		dependencies = {"CharacterService", "AbilityService"},
		initialize = function(service)
			ErrorHandler.Info("Initializing InputHandler")
			-- Register any default input handlers
		end,
		start = function(service)
			ErrorHandler.Info("Starting InputHandler")
			-- Connect to network events if needed
		end,
	})
	
	-- Register additional services here as needed...
	
	return serviceManager
end

-- Get the global service manager (singleton pattern)
function ServiceFactory.GetGlobalServiceManager(): ServiceManager.ServiceManager?
	return globalServiceManager
end

-- Initialize the global service manager
function ServiceFactory.InitializeGlobal(): ServiceManager.ServiceManager
	if globalServiceManager then
		ErrorHandler.Warn("Global service manager already initialized")
		return globalServiceManager
	end
	
	globalServiceManager = ServiceFactory.CreateServices()
	
	-- Initialize and start all services
	local manager = globalServiceManager
	if manager then
		manager:StartAll()
	end
	
	ErrorHandler.Info("Global service manager initialized and started")
	return globalServiceManager :: any
end

-- Get a specific service from the global manager
function ServiceFactory.GetService<T>(serviceId: string): T?
	if not globalServiceManager then
		ErrorHandler.Error(`Attempted to get service '{serviceId}' but global service manager not initialized`)
		return nil
	end
	
	return globalServiceManager:Get(serviceId)
end

-- Shutdown the global service manager
function ServiceFactory.Shutdown(): ()
	if globalServiceManager then
		globalServiceManager:StopAll()
		globalServiceManager = nil
		ErrorHandler.Info("Global service manager shut down")
	end
end

-- Service accessor functions for common services
function ServiceFactory.GetCharacterService(): CharacterService.ICharacterService?
	return ServiceFactory.GetService("CharacterService")
end

function ServiceFactory.GetAbilityService(): AbilityService.IAbilityService?
	return ServiceFactory.GetService("AbilityService")
end

function ServiceFactory.GetInputHandler(): InputHandler.IInputHandler?
	return ServiceFactory.GetService("InputHandler")
end

-- Development helpers
function ServiceFactory.DebugServices(): ()
	if not globalServiceManager then
		print("Global service manager not initialized")
		return
	end
	
	print("\n=== Service Manager Debug ===")
	-- TODO: Implement GetServiceIds method
	print("Service debugging not yet implemented")
	print("=== End Debug ===\n")
end

-- Health check for all services
function ServiceFactory.HealthCheck(): {[string]: boolean}
	local health = {}
	
	if not globalServiceManager then
		return {["ServiceManager"] = false}
	end
	
	-- TODO: Implement proper health checking
	health["ServiceManager"] = true
	return health
end

-- Update all services (call this from a main update loop)
function ServiceFactory.UpdateServices(deltaTime: number): ()
	if globalServiceManager then
		globalServiceManager:Update(deltaTime)
	end
end

return ServiceFactory
