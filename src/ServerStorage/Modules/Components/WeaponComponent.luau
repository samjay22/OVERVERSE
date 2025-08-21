--!strict
-- WeaponComponent: wraps WeaponService and registers default handlers

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local WeaponService = require(game.ServerStorage.Modules.Services.WeaponService)
local WeaponRegistryInit = require(game.ServerStorage.Modules.registery.Weapons)
local EffectComponent = require(game.ServerStorage.Modules.Components.EffectComponent)
local EffectService = EffectComponent.GetService()

local _service = WeaponService.New()

-- Load weapon definitions from registry
WeaponRegistryInit(_service)

local WeaponComponent = {}

function WeaponComponent.Initialize(characterData, config)
    -- Equip default weapon on spawn (could read from config later)
    _service:Equip(characterData.PlayerId, Enums.WeaponId.Default)
end

function WeaponComponent.Update(characterData, dt)
    -- No per-tick logic by default; abilities or specialized weapons may need it
end

function WeaponComponent.Cleanup(characterData)
    -- no-op; keep simple stateless service for now
end

function WeaponComponent.Primary(player: Player, action: Enums.WeaponAction): boolean
    return _service:Primary(player, action)
end

function WeaponComponent.Hit(player: Player, target: Instance | Player, extra: {[string]: any}?): boolean
    return _service:Hit(player, target, extra)
end

function WeaponComponent.GetService()
    return _service
end

return WeaponComponent
