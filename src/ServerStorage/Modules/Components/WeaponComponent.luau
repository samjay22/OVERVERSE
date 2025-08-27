--!strict
-- WeaponComponent - Manages character weapons and weapon actions

local BaseComponent = require(script.Parent.BaseComponent)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local WeaponService = require(game.ServerStorage.Modules.Services.WeaponService)

type WeaponComponentData = {
    Service: any,
    CurrentWeapon: string?,
    WeaponStats: {[string]: any},
    AttackCooldown: number,
    LastAttackTime: number,
    ComboWindow: number,
    ComboCount: number,
}

export type WeaponComponent = BaseComponent.BaseComponent & {
    Equip: (self: WeaponComponent, characterData: CharacterTypes.internalCharacter, weaponId: string) -> boolean,
    Unequip: (self: WeaponComponent, characterData: CharacterTypes.internalCharacter) -> (),
    Primary: (self: WeaponComponent, player: Player, action: Enums.WeaponAction) -> boolean,
    Hit: (self: WeaponComponent, player: Player, target: Instance | Player, extra: {[string]: any}?) -> boolean,
    GetCurrentWeapon: (self: WeaponComponent, characterData: CharacterTypes.internalCharacter) -> string?,
    GetWeaponStats: (self: WeaponComponent, characterData: CharacterTypes.internalCharacter) -> {[string]: any},
    CanAttack: (self: WeaponComponent, characterData: CharacterTypes.internalCharacter) -> boolean,
    GetService: (self: WeaponComponent) -> any,
}

local DEFAULT_COMBO_WINDOW = 1.5 -- Seconds to chain combos
local DEFAULT_ATTACK_COOLDOWN = 0.3 -- Base attack cooldown

local WeaponComponent = BaseComponent:extend("Weapon") :: any

function WeaponComponent:Initialize(characterData: CharacterTypes.internalCharacter, config: any?)
    BaseComponent.Initialize(self, characterData, config)
    
    local service = WeaponService.New()
    
    -- Initialize weapon registry
    local WeaponRegistryInit = require(game.ServerStorage.Modules.registry.Weapons)
    WeaponRegistryInit(service)
    
    local componentData: WeaponComponentData = {
        Service = service,
        CurrentWeapon = nil,
        WeaponStats = {},
        AttackCooldown = 0,
        LastAttackTime = 0,
        ComboWindow = DEFAULT_COMBO_WINDOW,
        ComboCount = 0,
    }
    
    characterData.Components.Weapon = componentData :: any
    
    -- Equip default weapon
    local defaultWeapon = (config and config.DefaultWeapon) or Enums.WeaponId.Default
    self:Equip(characterData, defaultWeapon)
end

function WeaponComponent:Update(characterData: CharacterTypes.internalCharacter, dt: number)
    if not self:IsEnabled(characterData) then
        return
    end
    
    local component = characterData.Components.Weapon :: WeaponComponentData
    if not component then
        return
    end
    
    -- Update attack cooldown
    if component.AttackCooldown > 0 then
        component.AttackCooldown = math.max(0, component.AttackCooldown - dt)
    end
    
    -- Reset combo if window expired
    local currentTime = tick()
    if component.ComboCount > 0 and (currentTime - component.LastAttackTime) > component.ComboWindow then
        component.ComboCount = 0
        characterData.StateManager:Set("WeaponCombo", 0)
    end
end

function WeaponComponent:Cleanup(characterData: CharacterTypes.internalCharacter)
    self:Unequip(characterData)
    
    local component = characterData.Components.Weapon :: WeaponComponentData
    if component and component.Service then
        if component.Service.Cleanup then
            component.Service:Cleanup(characterData)
        end
    end
    
    BaseComponent.Cleanup(self, characterData)
end

function WeaponComponent:Equip(characterData: CharacterTypes.internalCharacter, weaponId: string): boolean
    local component = characterData.Components.Weapon :: WeaponComponentData
    if not component or not component.Service then
        return false
    end
    
    -- Unequip current weapon if any
    if component.CurrentWeapon then
        self:Unequip(characterData)
    end
    
    -- Equip new weapon
    local success = component.Service:Equip(characterData.PlayerId, weaponId)
    if success then
        component.CurrentWeapon = weaponId
        component.ComboCount = 0
        
        -- Load weapon stats
        local weaponRegistry = component.Service.GetWeaponData and component.Service:GetWeaponData(weaponId)
        if weaponRegistry then
            component.WeaponStats = weaponRegistry
            component.AttackCooldown = weaponRegistry.AttackCooldown or DEFAULT_ATTACK_COOLDOWN
        end
        
        characterData.StateManager:Set("EquippedWeapon", weaponId)
        characterData.StateManager:Set("WeaponCombo", 0)
    end
    
    return success
end

function WeaponComponent:Unequip(characterData: CharacterTypes.internalCharacter)
    local component = characterData.Components.Weapon :: WeaponComponentData
    if not component or not component.CurrentWeapon then
        return
    end
    
    if component.Service and component.Service.Unequip then
        component.Service:Unequip(characterData.PlayerId)
    end
    
    component.CurrentWeapon = nil
    component.WeaponStats = {}
    component.ComboCount = 0
    
    characterData.StateManager:Set("EquippedWeapon", nil)
    characterData.StateManager:Set("WeaponCombo", 0)
end

function WeaponComponent:Primary(player: Player, action: Enums.WeaponAction): boolean
    local characterData = self:_GetCharacterData(player)
    if not characterData then
        return false
    end
    
    local component = characterData.Components.Weapon :: WeaponComponentData
    if not component or not component.Service then
        return false
    end
    
    if not self:CanAttack(characterData) then
        return false
    end
    
    local success = component.Service:Primary(player, action)
    if success then
        component.LastAttackTime = tick()
        component.ComboCount = component.ComboCount + 1
        component.AttackCooldown = component.WeaponStats.AttackCooldown or DEFAULT_ATTACK_COOLDOWN
        
        characterData.StateManager:Set("WeaponCombo", component.ComboCount)
    end
    
    return success
end

function WeaponComponent:Hit(player: Player, target: Instance | Player, extra: {[string]: any}?): boolean
    local characterData = self:_GetCharacterData(player)
    if not characterData then
        return false
    end
    
    local component = characterData.Components.Weapon :: WeaponComponentData
    if not component or not component.Service then
        return false
    end
    
    -- Add combo damage multiplier to extra data
    local enhancedExtra = extra or {}
    enhancedExtra.ComboMultiplier = 1 + (component.ComboCount * 0.1) -- 10% per combo
    
    return component.Service:Hit(player, target, enhancedExtra)
end

function WeaponComponent:GetCurrentWeapon(characterData: CharacterTypes.internalCharacter): string?
    local component = characterData.Components.Weapon :: WeaponComponentData
    return component and component.CurrentWeapon
end

function WeaponComponent:GetWeaponStats(characterData: CharacterTypes.internalCharacter): {[string]: any}
    local component = characterData.Components.Weapon :: WeaponComponentData
    return component and table.clone(component.WeaponStats) or {}
end

function WeaponComponent:CanAttack(characterData: CharacterTypes.internalCharacter): boolean
    if not self:IsEnabled(characterData) then
        return false
    end
    
    local component = characterData.Components.Weapon :: WeaponComponentData
    if not component or not component.CurrentWeapon then
        return false
    end
    
    if component.AttackCooldown > 0 then
        return false
    end
    
    local stateManager = characterData.StateManager
    return not stateManager:Get("IsDead")
        and not stateManager:Get("IsStunned")
end

function WeaponComponent:GetService()
    -- Return a new service instance for compatibility
    local service = WeaponService.New()
    local WeaponRegistryInit = require(game.ServerStorage.Modules.registry.Weapons)
    WeaponRegistryInit(service)
    return service
end

function WeaponComponent:_GetCharacterData(player: Player): CharacterTypes.internalCharacter?
    -- Use CharacterManager singleton to get character data
    local CharacterManager = require(game.ServerStorage.Modules.Entities.Character.CharacterManager)
    return CharacterManager:GetCharacterData(player) :: any
end

-- Create singleton instance for backward compatibility
local instance = WeaponComponent.new()

-- Export both instance methods and static interface for backward compatibility
local exports = {
    -- Instance (for new usage)
    Instance = instance,
    
    -- Static methods (for backward compatibility)
    Initialize = function(characterData, config)
        return instance:Initialize(characterData, config)
    end,
    
    Update = function(characterData, dt)
        return instance:Update(characterData, dt)
    end,
    
    Cleanup = function(characterData)
        return instance:Cleanup(characterData)
    end,
    
    Primary = function(player, action)
        return instance:Primary(player, action)
    end,
    
    Hit = function(player, target, extra)
        return instance:Hit(player, target, extra)
    end,
    
    GetService = function()
        return instance:GetService()
    end,
}

return exports