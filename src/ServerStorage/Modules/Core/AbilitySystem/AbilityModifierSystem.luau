--!strict

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Types = require(script.Parent.Types)

type AbilityModifier = Types.AbilityModifier
type AbilityInstance = Types.AbilityInstance

-- Ability Modifier System: Manages runtime modifications to abilities
local AbilityModifierSystem = {}
AbilityModifierSystem.__index = AbilityModifierSystem

function AbilityModifierSystem.new()
    local self = setmetatable({}, AbilityModifierSystem)
    
    -- Active modifiers per entity
    self.activeModifiers = {} :: {[Instance]: {[string]: ModifierInstance}}
    
    -- Global modifiers that affect all abilities
    self.globalModifiers = {} :: {ModifierInstance}
    
    -- Modifier templates for common effects
    self.modifierTemplates = {} :: {[string]: AbilityModifier}
    
    -- Modifier interaction rules
    self.interactionRules = {} :: {[string]: ModifierRule}
    
    -- Statistics
    self.stats = {
        totalModifiersApplied = 0,
        totalModifiersRemoved = 0,
        activeModifierCount = 0
    }
    
    -- Initialize
    self:_registerDefaultTemplates()
    self:_setupUpdateLoop()
    
    return self
end

type ModifierInstance = {
    modifier: AbilityModifier,
    target: Instance,
    appliedTime: number,
    expiryTime: number?,
    isActive: boolean,
    stackCount: number,
    sourceAbility: string?,
    metadata: {[string]: any}
}

type ModifierRule = {
    id: string,
    type: "Stack" | "Replace" | "Refresh" | "Block" | "Combine",
    priority: number,
    condition: ((existing: ModifierInstance, new: AbilityModifier) -> boolean)?,
    combineFunction: ((existing: ModifierInstance, new: AbilityModifier) -> AbilityModifier)?
}

-- Core modifier application

function AbilityModifierSystem:applyModifier(
    target: Instance,
    modifier: AbilityModifier,
    sourceAbility: string?
): string
    
    -- Generate unique ID if not provided
    if not modifier.id then
        modifier.id = HttpService:GenerateGUID(false)
    end
    
    -- Check interaction rules
    local existingModifier = self:getModifier(target, modifier.id)
    if existingModifier then
        local rule = self:_getInteractionRule(modifier.id)
        if rule then
            return self:_handleModifierInteraction(target, existingModifier, modifier, rule)
        end
    end
    
    -- Create modifier instance
    local instance: ModifierInstance = {
        modifier = self:_deepCopyModifier(modifier),
        target = target,
        appliedTime = os.clock(),
        expiryTime = modifier.duration and (os.clock() + modifier.duration) or nil,
        isActive = true,
        stackCount = modifier.stacks or 1,
        sourceAbility = sourceAbility,
        metadata = {}
    }
    
    -- Store modifier
    if not self.activeModifiers[target] then
        self.activeModifiers[target] = {}
    end
    self.activeModifiers[target][modifier.id] = instance
    
    -- Apply immediate effects
    self:_applyModifierEffects(target, instance)
    
    -- Update stats
    self.stats.totalModifiersApplied = self.stats.totalModifiersApplied + 1
    self.stats.activeModifierCount = self.stats.activeModifierCount + 1
    
    -- Fire event
    self:_fireModifierEvent("Applied", target, modifier)
    
    return modifier.id
end

function AbilityModifierSystem:removeModifier(target: Instance, modifierId: string): boolean
    if not self.activeModifiers[target] then
        return false
    end
    
    local instance = self.activeModifiers[target][modifierId]
    if not instance then
        return false
    end
    
    -- Remove effects
    self:_removeModifierEffects(target, instance)
    
    -- Remove from storage
    self.activeModifiers[target][modifierId] = nil
    
    -- Clean up empty tables
    if next(self.activeModifiers[target]) == nil then
        self.activeModifiers[target] = nil
    end
    
    -- Update stats
    self.stats.totalModifiersRemoved = self.stats.totalModifiersRemoved + 1
    self.stats.activeModifierCount = self.stats.activeModifierCount - 1
    
    -- Fire event
    self:_fireModifierEvent("Removed", target, instance.modifier)
    
    return true
end

function AbilityModifierSystem:getModifier(target: Instance, modifierId: string): ModifierInstance?
    if not self.activeModifiers[target] then
        return nil
    end
    
    return self.activeModifiers[target][modifierId]
end

function AbilityModifierSystem:getModifiers(target: Instance): {ModifierInstance}
    local modifiers = {}
    
    if self.activeModifiers[target] then
        for _, instance in pairs(self.activeModifiers[target]) do
            table.insert(modifiers, instance)
        end
    end
    
    return modifiers
end

function AbilityModifierSystem:hasModifier(target: Instance, modifierId: string): boolean
    return self:getModifier(target, modifierId) ~= nil
end

-- Modifier calculation for abilities

function AbilityModifierSystem:calculateModifiedStats(
    ability: AbilityInstance,
    baseStats: {[string]: any}
): {[string]: any}
    
    local modifiedStats = {}
    
    -- Start with base stats
    for key, value in pairs(baseStats) do
        modifiedStats[key] = value
    end
    
    -- Get all applicable modifiers
    local modifiers = self:_getApplicableModifiers(ability)
    
    -- Sort by priority
    table.sort(modifiers, function(a, b)
        return (a.modifier.priority or 0) > (b.modifier.priority or 0)
    end)
    
    -- Apply modifiers in order
    for _, instance in ipairs(modifiers) do
        self:_applyStatModifiers(modifiedStats, instance.modifier.statModifiers)
    end
    
    return modifiedStats
end

function AbilityModifierSystem:_applyStatModifiers(
    stats: {[string]: any},
    statModifiers: {[string]: {flat: number?, percent: number?}}?
)
    if not statModifiers then
        return
    end
    
    for statName, modifiers in pairs(statModifiers) do
        local currentValue = stats[statName]
        
        if type(currentValue) == "number" then
            -- Apply flat modifier first
            if modifiers.flat then
                currentValue = currentValue + modifiers.flat
            end
            
            -- Then apply percentage modifier
            if modifiers.percent then
                currentValue = currentValue * (1 + modifiers.percent)
            end
            
            stats[statName] = currentValue
        elseif statName == "custom" and type(currentValue) == "table" then
            -- Handle custom stat modifiers
            for customStat, customModifiers in pairs(modifiers) do
                if currentValue[customStat] and type(currentValue[customStat]) == "number" then
                    local value = currentValue[customStat]
                    
                    if customModifiers.flat then
                        value = value + customModifiers.flat
                    end
                    
                    if customModifiers.percent then
                        value = value * (1 + customModifiers.percent)
                    end
                    
                    currentValue[customStat] = value
                end
            end
        end
    end
end

-- Modifier stacking and interaction

function AbilityModifierSystem:_handleModifierInteraction(
    target: Instance,
    existing: ModifierInstance,
    new: AbilityModifier,
    rule: ModifierRule
): string
    
    if rule.type == "Stack" then
        -- Add stacks to existing modifier
        existing.stackCount = math.min(
            existing.stackCount + (new.stacks or 1),
            existing.modifier.stacks or math.huge
        )
        
        -- Refresh duration if specified
        if rule.condition and rule.condition(existing, new) then
            existing.expiryTime = new.duration and (os.clock() + new.duration) or existing.expiryTime
        end
        
        return existing.modifier.id
        
    elseif rule.type == "Replace" then
        -- Remove old and apply new
        self:removeModifier(target, existing.modifier.id)
        return self:applyModifier(target, new)
        
    elseif rule.type == "Refresh" then
        -- Refresh duration only
        if new.duration then
            existing.expiryTime = os.clock() + new.duration
        end
        return existing.modifier.id
        
    elseif rule.type == "Block" then
        -- Don't apply new modifier
        return existing.modifier.id
        
    elseif rule.type == "Combine" and rule.combineFunction then
        -- Combine modifiers into a new one
        local combined = rule.combineFunction(existing, new)
        self:removeModifier(target, existing.modifier.id)
        return self:applyModifier(target, combined)
    end
    
    return new.id
end

-- Modifier templates for common effects

function AbilityModifierSystem:_registerDefaultTemplates()
    -- Haste modifier
    self.modifierTemplates["Haste"] = {
        id = "Haste",
        priority = 50,
        duration = 10,
        statModifiers = {
            castTime = { percent = -0.25 },
            cooldown = { percent = -0.20 }
        },
        behaviorModifiers = {
            canCastWhileMoving = true
        }
    }
    
    -- Power modifier
    self.modifierTemplates["Power"] = {
        id = "Power",
        priority = 60,
        duration = 15,
        statModifiers = {
            damage = { percent = 0.30 },
            healing = { percent = 0.30 }
        }
    }
    
    -- Efficiency modifier
    self.modifierTemplates["Efficiency"] = {
        id = "Efficiency",
        priority = 40,
        duration = 20,
        statModifiers = {
            cost = { percent = -0.50 }
        }
    }
    
    -- Reach modifier
    self.modifierTemplates["Reach"] = {
        id = "Reach",
        priority = 30,
        duration = 10,
        statModifiers = {
            range = { flat = 20, percent = 0.25 },
            radius = { flat = 5, percent = 0.25 }
        }
    }
    
    -- Multicast modifier
    self.modifierTemplates["Multicast"] = {
        id = "Multicast",
        priority = 70,
        behaviorModifiers = {
            splitting = 2,
            custom = {
                multicastChance = 0.30
            }
        }
    }
    
    -- Vampiric modifier
    self.modifierTemplates["Vampiric"] = {
        id = "Vampiric",
        priority = 45,
        effectModifiers = {
            add = {
                {
                    type = "Heal",
                    trigger = "OnHit",
                    amount = { base = 0, scaling = { damage = 0.20 } }
                }
            }
        }
    }
    
    -- Echo modifier (repeat ability)
    self.modifierTemplates["Echo"] = {
        id = "Echo",
        priority = 80,
        behaviorModifiers = {
            custom = {
                echoCount = 1,
                echoDelay = 0.5
            }
        }
    }
    
    -- Penetration modifier
    self.modifierTemplates["Penetration"] = {
        id = "Penetration",
        priority = 55,
        behaviorModifiers = {
            piercing = true,
            custom = {
                armorPenetration = 0.30
            }
        }
    }
    
    -- Critical modifier
    self.modifierTemplates["Critical"] = {
        id = "Critical",
        priority = 65,
        statModifiers = {
            custom = {
                critChance = { flat = 0.25 },
                critDamage = { flat = 0.50 }
            }
        }
    }
    
    -- Silence immunity
    self.modifierTemplates["Unsilenceable"] = {
        id = "Unsilenceable",
        priority = 90,
        behaviorModifiers = {
            canCastWhileStunned = true,
            ignoreGlobalCooldown = true
        }
    }
end

function AbilityModifierSystem:createFromTemplate(templateName: string, overrides: {[string]: any}?): AbilityModifier?
    local template = self.modifierTemplates[templateName]
    if not template then
        warn(`[AbilityModifierSystem] Template not found: {templateName}`)
        return nil
    end
    
    local modifier = self:_deepCopyModifier(template)
    
    -- Apply overrides
    if overrides then
        for key, value in pairs(overrides) do
            modifier[key] = value
        end
    end
    
    return modifier
end

-- Mutation system for permanent ability changes

function AbilityModifierSystem:mutateAbility(
    ability: AbilityInstance,
    mutation: AbilityModifier
): boolean
    
    -- Apply as permanent modifier (no duration)
    mutation.duration = nil
    
    -- Store in ability's permanent modifiers
    if not ability.modifiers then
        ability.modifiers = {}
    end
    
    table.insert(ability.modifiers, mutation)
    
    -- Recalculate ability stats
    self:_recalculateAbilityStats(ability)
    
    -- Fire event
    self:_fireModifierEvent("Mutated", ability.owner, mutation)
    
    return true
end

function AbilityModifierSystem:evolveAbility(
    ability: AbilityInstance,
    evolutionPath: string
): boolean
    
    -- Evolution paths define major ability transformations
    local evolutions = {
        -- Fireball evolutions
        ["fireball_multishot"] = {
            statModifiers = {
                damage = { percent = -0.20 }
            },
            behaviorModifiers = {
                splitting = 3
            }
        },
        ["fireball_meteor"] = {
            statModifiers = {
                radius = { percent = 1.00 },
                damage = { percent = 0.50 }
            },
            effectModifiers = {
                add = {
                    {
                        type = "Area",
                        trigger = "OnHit",
                        radius = 10,
                        effects = {
                            {
                                type = "Damage",
                                trigger = "OnHit",
                                amount = { base = 50 },
                                damageType = "Fire"
                            }
                        }
                    }
                }
            }
        },
        ["fireball_seeking"] = {
            behaviorModifiers = {
                custom = {
                    homing = true,
                    turnSpeed = 2
                }
            }
        }
    }
    
    local evolution = evolutions[evolutionPath]
    if not evolution then
        warn(`[AbilityModifierSystem] Evolution path not found: {evolutionPath}`)
        return false
    end
    
    return self:mutateAbility(ability, evolution)
end

-- Global modifiers

function AbilityModifierSystem:applyGlobalModifier(modifier: AbilityModifier): string
    modifier.id = modifier.id or HttpService:GenerateGUID(false)
    
    local instance: ModifierInstance = {
        modifier = self:_deepCopyModifier(modifier),
        target = workspace, -- Use workspace as a placeholder
        appliedTime = os.clock(),
        expiryTime = modifier.duration and (os.clock() + modifier.duration) or nil,
        isActive = true,
        stackCount = 1,
        sourceAbility = nil,
        metadata = { isGlobal = true }
    }
    
    table.insert(self.globalModifiers, instance)
    
    return modifier.id
end

function AbilityModifierSystem:removeGlobalModifier(modifierId: string): boolean
    for i, instance in ipairs(self.globalModifiers) do
        if instance.modifier.id == modifierId then
            table.remove(self.globalModifiers, i)
            return true
        end
    end
    
    return false
end

-- Helper methods

function AbilityModifierSystem:_deepCopyModifier(modifier: AbilityModifier): AbilityModifier
    local copy = {}
    
    for key, value in pairs(modifier) do
        if type(value) == "table" then
            copy[key] = self:_deepCopyTable(value)
        else
            copy[key] = value
        end
    end
    
    return copy
end

function AbilityModifierSystem:_deepCopyTable(tbl: {[any]: any}): {[any]: any}
    local copy = {}
    
    for key, value in pairs(tbl) do
        if type(value) == "table" then
            copy[key] = self:_deepCopyTable(value)
        else
            copy[key] = value
        end
    end
    
    return copy
end

function AbilityModifierSystem:_getApplicableModifiers(ability: AbilityInstance): {ModifierInstance}
    local modifiers = {}
    
    -- Get target's modifiers
    if self.activeModifiers[ability.owner] then
        for _, instance in pairs(self.activeModifiers[ability.owner]) do
            if instance.isActive then
                table.insert(modifiers, instance)
            end
        end
    end
    
    -- Add global modifiers
    for _, instance in ipairs(self.globalModifiers) do
        if instance.isActive then
            table.insert(modifiers, instance)
        end
    end
    
    -- Add ability's permanent modifiers
    if ability.modifiers then
        for _, modifier in ipairs(ability.modifiers) do
            table.insert(modifiers, {
                modifier = modifier,
                target = ability.owner,
                appliedTime = 0,
                expiryTime = nil,
                isActive = true,
                stackCount = 1,
                sourceAbility = ability.definition.id,
                metadata = { isPermanent = true }
            })
        end
    end
    
    return modifiers
end

function AbilityModifierSystem:_applyModifierEffects(target: Instance, instance: ModifierInstance)
    -- Apply visual effects if specified
    if instance.modifier.visualModifiers then
        -- Implementation depends on visual system
    end
    
    -- Apply immediate stat changes if needed
    -- This would integrate with the character's stat system
end

function AbilityModifierSystem:_removeModifierEffects(target: Instance, instance: ModifierInstance)
    -- Remove visual effects
    -- Remove stat changes
    -- Clean up any other effects
end

function AbilityModifierSystem:_recalculateAbilityStats(ability: AbilityInstance)
    -- Recalculate all computed stats based on modifiers
    local baseStats = {
        cooldown = ability.definition.cooldown.base,
        castTime = ability.definition.castTime and ability.definition.castTime.base or 0,
        range = ability.definition.targeting.range or 0,
        radius = ability.definition.targeting.radius or 0,
        damage = 0, -- Would be calculated from effects
        cost = {}
    }
    
    -- Calculate costs
    if ability.definition.resources then
        for _, resource in ipairs(ability.definition.resources) do
            local amount = type(resource.amount) == "table" and resource.amount.base or resource.amount
            baseStats.cost[resource.type] = amount
        end
    end
    
    -- Apply modifiers
    ability.computedStats = self:calculateModifiedStats(ability, baseStats)
end

function AbilityModifierSystem:_getInteractionRule(modifierId: string): ModifierRule?
    return self.interactionRules[modifierId]
end

function AbilityModifierSystem:_fireModifierEvent(eventType: string, target: Instance, modifier: AbilityModifier)
    -- Fire event for other systems to react to
    -- Implementation depends on event system
end

function AbilityModifierSystem:_setupUpdateLoop()
    -- Check for expired modifiers periodically
    RunService.Heartbeat:Connect(function()
        local now = os.clock()
        
        -- Check entity modifiers
        for target, modifiers in pairs(self.activeModifiers) do
            for id, instance in pairs(modifiers) do
                if instance.expiryTime and now >= instance.expiryTime then
                    self:removeModifier(target, id)
                end
            end
        end
        
        -- Check global modifiers
        for i = #self.globalModifiers, 1, -1 do
            local instance = self.globalModifiers[i]
            if instance.expiryTime and now >= instance.expiryTime then
                table.remove(self.globalModifiers, i)
                self.stats.activeModifierCount = self.stats.activeModifierCount - 1
            end
        end
    end)
end

-- Interaction rules

function AbilityModifierSystem:registerInteractionRule(rule: ModifierRule)
    self.interactionRules[rule.id] = rule
end

function AbilityModifierSystem:createStackingRule(modifierId: string, maxStacks: number, refreshDuration: boolean)
    self:registerInteractionRule({
        id = modifierId,
        type = "Stack",
        priority = 50,
        condition = function(existing, new)
            return refreshDuration and existing.stackCount < maxStacks
        end
    })
end

function AbilityModifierSystem:createReplaceRule(modifierId: string, priority: number)
    self:registerInteractionRule({
        id = modifierId,
        type = "Replace",
        priority = priority
    })
end

function AbilityModifierSystem:createBlockRule(modifierId: string)
    self:registerInteractionRule({
        id = modifierId,
        type = "Block",
        priority = 100
    })
end

-- Public API

function AbilityModifierSystem:getStats(): {[string]: number}
    return self.stats
end

function AbilityModifierSystem:clearAllModifiers(target: Instance)
    if not self.activeModifiers[target] then
        return
    end
    
    for id in pairs(self.activeModifiers[target]) do
        self:removeModifier(target, id)
    end
end

function AbilityModifierSystem:getActiveModifierCount(): number
    return self.stats.activeModifierCount
end

-- Singleton
local system = nil

function AbilityModifierSystem.get()
    if not system then
        system = AbilityModifierSystem.new()
    end
    return system
end

return AbilityModifierSystem