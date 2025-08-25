--!strict
-- ComponentFactory - Creates and manages component instances

local BaseComponent = require(script.Parent.BaseComponent)

type BaseComponentType = BaseComponent.BaseComponent

export type ComponentFactory = {
    CreateComponent: (componentModule: any) -> BaseComponentType | any,
    IsBaseComponent: (component: any) -> boolean,
}

local ComponentFactory = {}

function ComponentFactory.CreateComponent(componentModule: any): BaseComponentType | any
    -- Check if it's already an instance (new-style components return instances)
    if componentModule and typeof(componentModule) == "table" then
        -- Check if it has BaseComponent methods
        if componentModule.Name and componentModule.Initialize and componentModule.Update then
            return componentModule
        end
        
        -- Check if it has a new() constructor (class-style)
        if componentModule.new and typeof(componentModule.new) == "function" then
            return componentModule.new()
        end
    end
    
    -- Return as-is for old-style components
    return componentModule
end

function ComponentFactory.IsBaseComponent(component: any): boolean
    if not component or typeof(component) ~= "table" then
        return false
    end
    
    -- Check for BaseComponent properties and methods
    return component.Name ~= nil
        and component.Initialize ~= nil
        and component.Update ~= nil
        and component.Cleanup ~= nil
        and component.IsEnabled ~= nil
        and component.Enable ~= nil
        and component.Disable ~= nil
end

return ComponentFactory