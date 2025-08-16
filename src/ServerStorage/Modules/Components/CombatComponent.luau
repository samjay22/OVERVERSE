--!strict
-- Combat Component - delegates to CombatService

local CombatService = require(game.ServerStorage.Modules.Services.CombatService)

local _service = CombatService.New()

local CombatComponent = {}

function CombatComponent.Initialize(characterData, config)
    _service:Initialize(characterData, config)
end

function CombatComponent.Update(characterData, dt: number)
    _service:Update(characterData, dt)
end

function CombatComponent.PerformAttack(characterData, attackType: string?): boolean
    return _service:PerformAttack(characterData, attackType)
end

function CombatComponent.PerformBlock(characterData, shouldBlock: boolean): boolean
    return _service:PerformBlock(characterData, shouldBlock)
end

function CombatComponent.TakeDamage(characterData, damage: number, canBlock: boolean?): number
    return _service:TakeDamage(characterData, damage, canBlock)
end

function CombatComponent.ApplyDamage(attackerCharacter, targetCharacter, baseDamage: number, canBlock: boolean?): number
    return _service:ApplyDamage(attackerCharacter, targetCharacter, baseDamage, canBlock)
end

function CombatComponent.Cleanup(characterData)
    if characterData.Components and characterData.Components.Combat then
        characterData.Components.Combat = nil
    end
end

function CombatComponent.GetEventBus(characterData)
    -- Internal detail: event buses are kept in service; expose access if needed.
    if _service and (_service :: any)._buses then
        return (_service :: any)._buses[characterData.PlayerId]
    end
    return nil
end

return CombatComponent