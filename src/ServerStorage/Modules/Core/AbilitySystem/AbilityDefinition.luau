--!strict

local Types = require(script.Parent.Types)

type AbilityDefinition = Types.AbilityDefinition
type ScalableValue = Types.ScalableValue
type ScalingType = Types.ScalingType
type EffectConfig = Types.EffectConfig

local AbilityDefinition = {}
AbilityDefinition.__index = AbilityDefinition

function AbilityDefinition.new(config: AbilityDefinition): AbilityDefinition
    local self = setmetatable({}, AbilityDefinition)
    
    -- Deep copy the configuration
    self.config = self:_deepCopy(config)
    
    -- Validate the definition
    self:_validate()
    
    -- Process and optimize the definition
    self:_process()
    
    return self.config
end

function AbilityDefinition:_deepCopy(obj: any): any
    if type(obj) ~= "table" then
        return obj
    end
    
    local copy = {}
    for key, value in pairs(obj) do
        copy[key] = self:_deepCopy(value)
    end
    
    return copy
end

function AbilityDefinition:_validate()
    local config = self.config
    
    -- Required fields
    assert(config.id, "AbilityDefinition: id is required")
    assert(config.name, "AbilityDefinition: name is required")
    assert(config.type, "AbilityDefinition: type is required")
    assert(config.cooldown, "AbilityDefinition: cooldown is required")
    assert(config.targeting, "AbilityDefinition: targeting is required")
    assert(config.effects, "AbilityDefinition: effects are required")
    
    -- Validate cooldown
    if type(config.cooldown) == "number" then
        config.cooldown = {
            base = config.cooldown,
            modifiable = true
        }
    end
    
    -- Validate targeting
    local targeting = config.targeting
    assert(targeting.type, "AbilityDefinition: targeting.type is required")
    
    -- Set defaults for targeting
    if not targeting.filter then
        targeting.filter = {
            team = "Enemy",
            type = "All",
            status = "Alive"
        }
    end
    
    -- Validate effects
    assert(#config.effects > 0, "AbilityDefinition: at least one effect is required")
    for i, effect in ipairs(config.effects) do
        self:_validateEffect(effect, `effect[{i}]`)
    end
    
    -- Validate resources if present
    if config.resources then
        for i, resource in ipairs(config.resources) do
            assert(resource.type, `AbilityDefinition: resources[{i}].type is required`)
            assert(resource.amount, `AbilityDefinition: resources[{i}].amount is required`)
        end
    end
    
    -- Validate combos if present
    if config.combos then
        for i, combo in ipairs(config.combos) do
            assert(combo.window, `AbilityDefinition: combos[{i}].window is required`)
            assert(combo.effects, `AbilityDefinition: combos[{i}].effects is required`)
        end
    end
end

function AbilityDefinition:_validateEffect(effect: EffectConfig, path: string)
    assert(effect.type, `{path}.type is required`)
    assert(effect.trigger, `{path}.trigger is required`)
    
    -- Validate effect-specific requirements
    local effectType = effect.type
    
    if effectType == "Damage" or effectType == "Heal" then
        assert(effect.amount, `{path}.amount is required for {effectType} effect`)
        if effectType == "Damage" then
            assert(effect.damageType, `{path}.damageType is required for Damage effect`)
        end
    elseif effectType == "Shield" or effectType == "Buff" or effectType == "Debuff" then
        assert(effect.duration, `{path}.duration is required for {effectType} effect`)
    elseif effectType == "Knockback" or effectType == "Pull" or effectType == "Dash" then
        assert(effect.distance, `{path}.distance is required for {effectType} effect`)
        assert(effect.speed, `{path}.speed is required for {effectType} effect`)
    elseif effectType == "Projectile" then
        assert(effect.speed, `{path}.speed is required for Projectile effect`)
    elseif effectType == "Channel" then
        assert(effect.duration, `{path}.duration is required for Channel effect`)
    end
    
    -- Validate child effects recursively
    if effect.effects then
        for i, childEffect in ipairs(effect.effects) do
            self:_validateEffect(childEffect, `{path}.effects[{i}]`)
        end
    end
end

function AbilityDefinition:_process()
    local config = self.config
    
    -- Process defaults
    config.activation = config.activation or "Press"
    config.description = config.description or ""
    config.tags = config.tags or {}
    config.category = config.category or "General"
    
    -- Process timing
    if config.type == "Instant" then
        config.castTime = config.castTime or { base = 0, modifiable = false }
    elseif config.type == "Channeled" then
        assert(config.channelTime, "AbilityDefinition: channelTime is required for Channeled abilities")
    end
    
    -- Process network settings
    if not config.network then
        config.network = {
            predictable = true,
            authoritative = "Server",
            syncRate = 10,
            interpolate = true
        }
    end
    
    -- Process AI settings
    if not config.ai then
        config.ai = {
            priority = 50,
            preferredRange = { min = 0, max = math.huge },
            targetPreference = "Closest",
            conditions = {}
        }
    end
    
    -- Index effects by trigger for faster lookup
    config._effectsByTrigger = {}
    self:_indexEffects(config.effects, config._effectsByTrigger)
    
    -- Calculate ability score for AI/auto-casting
    config._abilityScore = self:_calculateAbilityScore()
end

function AbilityDefinition:_indexEffects(effects: {EffectConfig}, index: {[string]: {EffectConfig}})
    for _, effect in ipairs(effects) do
        local trigger = effect.trigger
        if not index[trigger] then
            index[trigger] = {}
        end
        table.insert(index[trigger], effect)
        
        -- Recursively index child effects
        if effect.effects then
            self:_indexEffects(effect.effects, index)
        end
    end
end

function AbilityDefinition:_calculateAbilityScore(): number
    local config = self.config
    local score = 0
    
    -- Base score from cooldown (lower cooldown = higher score)
    local cooldownBase = type(config.cooldown) == "table" and config.cooldown.base or config.cooldown
    score = score + (60 / math.max(cooldownBase, 1)) * 10
    
    -- Score from damage/healing potential
    for _, effect in ipairs(config.effects) do
        if effect.type == "Damage" then
            local amount = self:_getEffectValue(effect.amount)
            score = score + amount * 0.5
        elseif effect.type == "Heal" then
            local amount = self:_getEffectValue(effect.amount)
            score = score + amount * 0.3
        elseif effect.type == "Stun" or effect.type == "Root" then
            score = score + 30
        elseif effect.type == "Shield" then
            local amount = self:_getEffectValue(effect.amount)
            score = score + amount * 0.4
        end
    end
    
    -- Score from targeting flexibility
    local targeting = config.targeting
    if targeting.type == "Area" or targeting.type == "Cone" then
        score = score + 20
    elseif targeting.type == "Chain" then
        score = score + 25
    end
    
    -- Score from resource efficiency
    if config.resources then
        local totalCost = 0
        for _, resource in ipairs(config.resources) do
            local amount = type(resource.amount) == "table" and resource.amount.base or resource.amount
            totalCost = totalCost + amount
        end
        score = score * (100 / math.max(totalCost, 1))
    end
    
    return score
end

function AbilityDefinition:_getEffectValue(value: any): number
    if type(value) == "number" then
        return value
    elseif type(value) == "table" then
        if value.base then
            return value.base
        elseif value.min and value.max then
            return (value.min + value.max) / 2
        end
    end
    return 0
end

-- Public methods for working with definitions

function AbilityDefinition.calculateScaledValue(value: ScalableValue | number, scaling: ScalingType?, stats: {[string]: number}?): number
    if type(value) == "number" then
        return value
    end
    
    local result = value.base
    
    if scaling and stats then
        for statName, multiplier in pairs(scaling) do
            if statName ~= "custom" and stats[statName] then
                result = result + stats[statName] * multiplier
            end
        end
        
        -- Handle custom scaling
        if scaling.custom and stats.custom then
            for customStat, multiplier in pairs(scaling.custom) do
                if stats.custom[customStat] then
                    result = result + stats.custom[customStat] * multiplier
                end
            end
        end
    end
    
    return result
end

function AbilityDefinition.getEffectsByTrigger(definition: AbilityDefinition, trigger: string): {EffectConfig}
    return definition._effectsByTrigger and definition._effectsByTrigger[trigger] or {}
end

function AbilityDefinition.hasTag(definition: AbilityDefinition, tag: string): boolean
    if not definition.tags then
        return false
    end
    
    for _, t in ipairs(definition.tags) do
        if t == tag then
            return true
        end
    end
    
    return false
end

function AbilityDefinition.meetsRequirements(definition: AbilityDefinition, character: Instance): boolean
    local requirements = definition.requirements
    if not requirements then
        return true
    end
    
    -- Check level requirement
    if requirements.level then
        local level = character:GetAttribute("Level") or 1
        if level < requirements.level then
            return false
        end
    end
    
    -- Check combat state
    if requirements.inCombat ~= nil then
        local inCombat = character:GetAttribute("InCombat") or false
        if inCombat ~= requirements.inCombat then
            return false
        end
    end
    
    -- Check custom requirement
    if requirements.custom then
        if not requirements.custom(character) then
            return false
        end
    end
    
    return true
end

-- Builder pattern for creating definitions programmatically

local DefinitionBuilder = {}
DefinitionBuilder.__index = DefinitionBuilder
type AbilityBuilder =  typeof(DefinitionBuilder)

function AbilityDefinition.builder() : AbilityBuilder
    local self = setmetatable({}, DefinitionBuilder)
    self.definition = {
        effects = {},
        tags = {},
        resources = {},
        combos = {}
    }
    return self :: any
end
    
function DefinitionBuilder:addEffect(effect : EffectConfig) : AbilityBuilder
    table.insert(self.definition.effects, effect)
    return self
end
function DefinitionBuilder:setId(id: string) : AbilityBuilder
    self.definition.id = id
    return self
end

function DefinitionBuilder:setName(name: string) : AbilityBuilder
    self.definition.name = name
    return self
end

function DefinitionBuilder:setType(type: Types.AbilityType) : AbilityBuilder
    self.definition.type = type
    return self
end

function DefinitionBuilder:setCooldown(cooldown: number | ScalableValue) : AbilityBuilder
    self.definition.cooldown = cooldown
    return self
end

function DefinitionBuilder:setTargeting(targeting: Types.TargetingConfig) : AbilityBuilder
    self.definition.targeting = targeting
    return self
end

function DefinitionBuilder:addResource(resource: Types.ResourceRequirement) : AbilityBuilder
    table.insert(self.definition.resources, resource)
    return self
end

function DefinitionBuilder:addTag(tag: string) : AbilityBuilder
    table.insert(self.definition.tags, tag)
    return self
end

function DefinitionBuilder:setCustomData(data: { [string]: any }) : AbilityBuilder
    self.definition.customData = data
    return self
end


function DefinitionBuilder:addCombo(combo: Types.ComboConfig) : AbilityBuilder
    table.insert(self.definition.combos, combo)
    return self
end

function DefinitionBuilder:build(): AbilityDefinition
    return AbilityDefinition.new(self.definition)
end

return AbilityDefinition