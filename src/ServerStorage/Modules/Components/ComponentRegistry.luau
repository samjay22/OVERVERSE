--!strict
-- ComponentRegistry - Centralized component registration and management

local BaseComponent = require(script.Parent.BaseComponent)

export type ComponentRegistry = {
    Register: (name: string, componentModule: any) -> boolean,
    Get: (name: string) -> any?,
    GetAll: () -> {[string]: any},
    CreateInstance: (componentModule: any) -> any,
}

local ComponentRegistry = {}
ComponentRegistry.__index = ComponentRegistry

local registry = {}
local instances = {}

function ComponentRegistry.Register(name: string, componentModule: any): boolean
    if registry[name] then
        warn(`Component {name} already registered`)
        return false
    end
    
    -- Store the module
    registry[name] = componentModule
    
    -- Create and cache singleton instance if it's a new-style component
    if componentModule.Instance then
        instances[name] = componentModule.Instance
    else
        instances[name] = componentModule
    end
    
    return true
end

function ComponentRegistry.Get(name: string): any?
    return instances[name]
end

function ComponentRegistry.GetAll(): {[string]: any}
    return table.clone(instances)
end

function ComponentRegistry.CreateInstance(componentModule: any): any
    -- Check if it's already an instance with new-style exports
    if componentModule.Instance then
        return componentModule.Instance
    end
    
    -- Check if it has a new() constructor
    if componentModule.new and typeof(componentModule.new) == "function" then
        return componentModule.new()
    end
    
    -- Return as-is for old-style components
    return componentModule
end

return ComponentRegistry