--!strict
-- Abilities Registry - Stores ability definitions

export type AbilityDefinition = {
    id: string,
    name: string,
    description: string?,
    cooldown: number?,
    duration: number?,
    cost: number?,
    range: number?,
    damage: number?,
    effects: {string}?,
}

local abilities: {[string]: AbilityDefinition} = {}

local AbilityRegistry = {}

function AbilityRegistry.Register(ability: AbilityDefinition)
    abilities[ability.id] = ability
end

function AbilityRegistry.GetAbility(abilityId: string): AbilityDefinition?
    return abilities[abilityId]
end

function AbilityRegistry.GetAllAbilities(): {[string]: AbilityDefinition}
    return table.clone(abilities)
end

-- Register some default abilities
AbilityRegistry.Register({
    id = "M1",
    name = "Basic Attack",
    description = "A basic melee attack",
    cooldown = 0.5,
})

AbilityRegistry.Register({
    id = "M2",
    name = "Block",
    description = "Block incoming attacks",
    cooldown = 0.3,
})

return AbilityRegistry