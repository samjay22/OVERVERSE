--!strict
-- Core types used throughout the system for strong typing

-- Base entity identifier types
export type PlayerId = number
export type EntityId = string
export type ComponentId = string
export type ServiceId = string

-- Registry types
export type RegistryId = string
export type RegistryItem<T> = {
	id: RegistryId,
	data: T,
	metadata: {[string]: any}?,
}

-- Event types
export type EventCallback<T...> = (T...) -> ()
export type EventConnection = RBXScriptConnection

-- Component system types
export type ComponentDefinition<T> = {
	id: ComponentId,
	data: T,
	initialize: ((any, any?) -> ())?,
	update: ((any, number) -> ())?,
	cleanup: ((any) -> ())?,
}

export type ComponentManager = {
	Register: <T>(self: ComponentManager, definition: ComponentDefinition<T>) -> (),
	Get: <T>(self: ComponentManager, entityId: EntityId, componentId: ComponentId) -> T?,
	Add: <T>(self: ComponentManager, entityId: EntityId, componentId: ComponentId, data: T) -> (),
	Remove: (self: ComponentManager, entityId: EntityId, componentId: ComponentId) -> (),
	Has: (self: ComponentManager, entityId: EntityId, componentId: ComponentId) -> boolean,
	GetAll: (self: ComponentManager, entityId: EntityId) -> {[ComponentId]: any},
	Update: (self: ComponentManager, entityId: EntityId, deltaTime: number) -> (),
	Cleanup: (self: ComponentManager, entityId: EntityId) -> (),
}

-- Service system types
export type ServiceDefinition<T> = {
	id: ServiceId,
	data: T,
	initialize: ((any) -> ())?,
	start: ((any) -> ())?,
	stop: ((any) -> ())?,
	update: ((any, number) -> ())?,
}

export type ServiceManager = {
	Register: <T>(self: ServiceManager, definition: ServiceDefinition<T>) -> (),
	Get: <T>(self: ServiceManager, serviceId: ServiceId) -> T?,
	Start: (self: ServiceManager, serviceId: ServiceId) -> (),
	Stop: (self: ServiceManager, serviceId: ServiceId) -> (),
	StartAll: (self: ServiceManager) -> (),
	StopAll: (self: ServiceManager) -> (),
	Update: (self: ServiceManager, deltaTime: number) -> (),
}

-- Registry system types
export type RegistryDefinition<T> = {
	id: RegistryId,
	validate: (data: any) -> boolean,
	transform: ((data: any) -> T)?,
	autoLoad: boolean?,
	folder: Folder?,
}

export type IRegistry<T> = {
	Register: (self: IRegistry<T>, id: RegistryId, item: T) -> (),
	Get: (self: IRegistry<T>, id: RegistryId) -> T?,
	GetAll: (self: IRegistry<T>) -> {[RegistryId]: T},
	Has: (self: IRegistry<T>, id: RegistryId) -> boolean,
	Remove: (self: IRegistry<T>, id: RegistryId) -> boolean,
	LoadFromFolder: (self: IRegistry<T>, folder: Folder) -> number,
	GetIds: (self: IRegistry<T>) -> {RegistryId},
	Count: (self: IRegistry<T>) -> number,
}

-- State management types
export type StateValue = string | number | boolean | {[any]: any} | nil
export type StateChangeCallback = (newValue: StateValue, oldValue: StateValue) -> ()

export type IStateManager = {
	Get: (self: IStateManager, key: string) -> StateValue,
	Set: (self: IStateManager, key: string, value: StateValue) -> (),
	SetMultiple: (self: IStateManager, states: {[string]: StateValue}) -> (),
	GetAll: (self: IStateManager) -> {[string]: StateValue},
	OnChange: (self: IStateManager, key: string, callback: StateChangeCallback) -> EventConnection,
	RemoveChangeListener: (self: IStateManager, key: string, connection: EventConnection) -> (),
	Clear: (self: IStateManager) -> (),
	Has: (self: IStateManager, key: string) -> boolean,
}

-- Error handling types
export type Result<T, E> = {
	success: true,
	value: T,
} | {
	success: false,
	error: E,
}

export type ErrorCode = string
export type ErrorMessage = string
export type GameError = {
	code: ErrorCode,
	message: ErrorMessage,
	context: {[string]: any}?,
	timestamp: number,
}

-- Utility types
export type Optional<T> = T?
export type ReadOnly<T> = T
export type Mutable<T> = T

-- Function types
export type VoidFunction = () -> ()
export type Predicate<T> = (value: T) -> boolean
export type Transform<T, U> = (input: T) -> U

return nil
