--!strict
-- Ability Component - wraps AbilityService

local AbilityService = require(game.ServerStorage.Modules.Services.AbilityService)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

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

function AbilityComponent.M1(player: Player, attackType: string?): boolean
    return (_service :: any):M1(player, attackType)
end

function AbilityComponent.M2(player: Player, isDown: boolean): boolean
    return (_service :: any):M2(player, isDown)
end

-- Registry removed

function AbilityComponent.GetLoadout(playerId: number)
    return (_service :: any):GetLoadout(playerId)
end

function AbilityComponent.SetLoadout(characterData: AbilityTypes.CharacterRef, loadout: AbilityTypes.Loadout)
    (_service :: any):SetLoadout(characterData, loadout)
end

function AbilityComponent.HandleInput(player: Player, action: string, isDown: boolean, meta: {[string]: any}?)
    return (_service :: any):HandleInput(player, action, isDown, meta)
end

function AbilityComponent.RemapBinding(player: Player, binding: string, abilityId: string?)
    return (_service :: any):RemapBinding(player, binding, abilityId)
end

return AbilityComponent
