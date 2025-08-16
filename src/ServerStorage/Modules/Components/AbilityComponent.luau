--!strict
-- Ability Component - wraps AbilityService

local AbilityService = require(game.ServerStorage.Modules.Services.AbilityService)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)
local AbilityRegistry = require(game.ServerStorage.Modules.registery.Abilities)

local _service = AbilityService.New()

local AbilityComponent = {}

function AbilityComponent.Initialize(characterData: AbilityTypes.CharacterRef, config: any?)
    local loadout: AbilityTypes.Loadout? = (config and (config :: any).AbilityLoadout) or nil
    _service:Initialize(characterData, loadout)
end

function AbilityComponent.Update(characterData: AbilityTypes.CharacterRef, dt: number)
    _service:Update(characterData, dt)
end

function AbilityComponent.Activate(player: Player, abilityId: string, ctxExtra: {[string]: any}?): boolean
    return _service:Activate(player, abilityId, ctxExtra)
end

function AbilityComponent.PrimaryAttack(player: Player, attackType: string?): boolean
    return _service:PrimaryAttack(player, attackType)
end

function AbilityComponent.GetRegistry(): typeof(AbilityRegistry)
    return AbilityRegistry
end

return AbilityComponent
