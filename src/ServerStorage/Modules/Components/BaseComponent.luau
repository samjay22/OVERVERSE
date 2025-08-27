--!strict
-- BaseComponent - Abstract base class for all character components

local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

export type BaseComponent = {
    Name: string,
    Initialize: (self: BaseComponent, characterData: CharacterTypes.internalCharacter, config: any?) -> (),
    Update: (self: BaseComponent, characterData: CharacterTypes.internalCharacter, dt: number) -> (),
    Cleanup: (self: BaseComponent, characterData: CharacterTypes.internalCharacter) -> (),
    IsEnabled: (self: BaseComponent, characterData: CharacterTypes.internalCharacter) -> boolean,
    Enable: (self: BaseComponent, characterData: CharacterTypes.internalCharacter) -> (),
    Disable: (self: BaseComponent, characterData: CharacterTypes.internalCharacter) -> (),
}

export type ComponentConstructor = {
    new: (name: string) -> BaseComponent,
    extend: (self: ComponentConstructor, name: string) -> ComponentConstructor,
    Initialize: (self: BaseComponent, characterData: CharacterTypes.internalCharacter, config: any?) -> (),
    Update: (self: BaseComponent, characterData: CharacterTypes.internalCharacter, dt: number) -> (),
    Cleanup: (self: BaseComponent, characterData: CharacterTypes.internalCharacter) -> (),
    IsEnabled: (self: BaseComponent, characterData: CharacterTypes.internalCharacter) -> boolean,
    Enable: (self: BaseComponent, characterData: CharacterTypes.internalCharacter) -> (),
    Disable: (self: BaseComponent, characterData: CharacterTypes.internalCharacter) -> (),
    __index : ComponentConstructor,
}

local BaseComponent = {} :: ComponentConstructor
BaseComponent.__index = BaseComponent

function BaseComponent.new(name: string): BaseComponent
    local self = setmetatable({}, BaseComponent)
    self.Name = name
    return self :: any
end

function BaseComponent:extend(name: string): ComponentConstructor
    local SubClass = setmetatable({}, { __index = self })
    SubClass.__index = SubClass
    SubClass.Name = name
    
    function SubClass.new(): BaseComponent
        local instance = setmetatable({}, SubClass)
        instance.Name = name
        return instance :: any
    end
    
    return SubClass :: any
end

function BaseComponent:Initialize(characterData: CharacterTypes.internalCharacter, config: any?)
    -- Override in subclasses
    characterData.Components[self.Name] = {
        Enabled = true,
        Config = config,
    }
end

function BaseComponent:Update(characterData: CharacterTypes.internalCharacter, dt: number)
    -- Override in subclasses
end

function BaseComponent:Cleanup(characterData: CharacterTypes.internalCharacter)
    -- Override in subclasses
    if characterData.Components and characterData.Components[self.Name] then
        characterData.Components[self.Name] = nil
    end
end

function BaseComponent:IsEnabled(characterData: CharacterTypes.internalCharacter): boolean
    local component = characterData.Components[self.Name]
    return component and component.Enabled == true
end

function BaseComponent:Enable(characterData: CharacterTypes.internalCharacter)
    local component = characterData.Components[self.Name]
    if component then
        component.Enabled = true
    end
end

function BaseComponent:Disable(characterData: CharacterTypes.internalCharacter)
    local component = characterData.Components[self.Name]
    if component then
        component.Enabled = false
    end
end

return BaseComponent