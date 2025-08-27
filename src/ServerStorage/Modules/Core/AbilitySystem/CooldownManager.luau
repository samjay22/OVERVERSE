--!strict

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Types = require(script.Parent.Types)

type AbilityInstance = Types.AbilityInstance
type ScalableValue = Types.ScalableValue

-- Cooldown Manager: Handles all cooldown-related functionality with dynamic modifiers
local CooldownManager = {}
CooldownManager.__index = CooldownManager

function CooldownManager.new()
    local self = setmetatable({}, CooldownManager)
    
    -- Active cooldowns per entity
    self.cooldowns = {} :: {[Instance]: {[string]: CooldownData}}
    
    -- Global cooldowns (affects all abilities)
    self.globalCooldowns = {} :: {[Instance]: number}
    
    -- Cooldown reduction effects
    self.cooldownReductions = {} :: {[Instance]: {[string]: CooldownReduction}}
    
    -- Charge-based abilities
    self.chargeData = {} :: {[Instance]: {[string]: ChargeData}}
    
    -- Cooldown reset triggers
    self.resetTriggers = {} :: {[string]: ResetTrigger}
    
    -- Statistics
    self.stats = {
        totalCooldownsStarted = 0,
        totalCooldownsCompleted = 0,
        totalResets = 0,
        totalChargesUsed = 0,
        activeCooldowns = 0
    }
    
    -- Configuration
    self.config = {
        updateRate = 0.1, -- Update cooldowns every 0.1 seconds
        minCooldown = 0.1, -- Minimum cooldown time
        maxCooldownReduction = 0.8, -- Maximum 80% CDR
        chargeReplenishRate = 1.0 -- Default charge replenish rate multiplier
    }
    
    -- Initialize
    self:_setupUpdateLoop()
    self:_registerDefaultTriggers()
    
    return self
end

type CooldownData = {
    abilityId: string,
    startTime: number,
    duration: number,
    originalDuration: number,
    endTime: number,
    isPaused: boolean,
    pausedTime: number?,
    modifiers: {CooldownModifier},
    metadata: {[string]: any}
}

type ChargeData = {
    abilityId: string,
    currentCharges: number,
    maxCharges: number,
    rechargeTime: number,
    lastUseTime: number,
    recharging: boolean,
    nextChargeTime: number?,
    sharedWith: {string}? -- Other abilities sharing these charges
}

type CooldownReduction = {
    id: string,
    source: string, -- Source of the reduction (ability, item, buff, etc.)
    amount: number, -- Percentage reduction (0-1)
    duration: number?, -- Duration of the reduction effect
    endTime: number?,
    isActive: boolean,
    affectsAbilities: {string}?, -- Specific abilities affected (nil = all)
    stackable: boolean,
    priority: number
}

type CooldownModifier = {
    type: "Flat" | "Percent" | "Reset" | "Pause" | "Extend",
    value: number,
    source: string,
    appliedTime: number
}

type ResetTrigger = {
    id: string,
    condition: "OnKill" | "OnAssist" | "OnDamage" | "OnHeal" | "OnCrit" | "Custom",
    chance: number, -- Chance to trigger (0-1)
    affectsAbilities: {string}?, -- Specific abilities to reset (nil = all)
    cooldown: number?, -- Cooldown for the trigger itself
    lastTriggerTime: number?,
    customCondition: ((entity: Instance, context: {[string]: any}) -> boolean)?
}

-- Core cooldown management

function CooldownManager:startCooldown(
    entity: Instance,
    abilityId: string,
    duration: number,
    metadata: {[string]: any}?
): boolean
    
    -- Debug logging
    print("[CooldownManager] Starting cooldown:", {
        entity = entity,
        entityName = entity and entity.Name or "nil",
        abilityId = abilityId,
        duration = duration
    })
    
    -- Apply cooldown reductions
    local modifiedDuration = self:_calculateModifiedCooldown(entity, abilityId, duration)
    
    -- Enforce minimum cooldown
    modifiedDuration = math.max(modifiedDuration, self.config.minCooldown)
    
    -- Create cooldown data
    local cooldownData: CooldownData = {
        abilityId = abilityId,
        startTime = os.clock(),
        duration = modifiedDuration,
        originalDuration = duration,
        endTime = os.clock() + modifiedDuration,
        isPaused = false,
        pausedTime = nil,
        modifiers = {},
        metadata = metadata or {}
    }
    
    -- Store cooldown
    if not self.cooldowns[entity] then
        self.cooldowns[entity] = {}
        print("[CooldownManager] Created new cooldown table for entity:", entity)
    end
    self.cooldowns[entity][abilityId] = cooldownData
    print("[CooldownManager] Stored cooldown for", abilityId, "duration:", modifiedDuration)
    
    -- Update stats
    self.stats.totalCooldownsStarted = self.stats.totalCooldownsStarted + 1
    self.stats.activeCooldowns = self.stats.activeCooldowns + 1
    
    -- Fire event
    self:_fireCooldownEvent("Started", entity, abilityId, cooldownData)
    
    return true
end

function CooldownManager:getCooldownRemaining(entity: Instance, abilityId: string): number
    -- Debug logging
    print("[CooldownManager] Checking cooldown remaining:", {
        entity = entity,
        entityName = entity and entity.Name or "nil",
        abilityId = abilityId,
        hasCooldownTable = self.cooldowns[entity] ~= nil,
        cooldownData = self.cooldowns[entity] and self.cooldowns[entity][abilityId] or nil
    })
    
    if not self.cooldowns[entity] then
        return 0
    end
    
    local cooldownData = self.cooldowns[entity][abilityId]
    if not cooldownData then
        return 0
    end
    
    if cooldownData.isPaused then
        return cooldownData.endTime - cooldownData.pausedTime
    end
    
    local remaining = cooldownData.endTime - os.clock()
    return math.max(0, remaining)
end

function CooldownManager:isOnCooldown(entity: Instance, abilityId: string): boolean
    local remaining = self:getCooldownRemaining(entity, abilityId)
    print("[CooldownManager] Is on cooldown:", abilityId, "remaining:", remaining, "result:", remaining > 0)
    return remaining > 0
end

function CooldownManager:resetCooldown(entity: Instance, abilityId: string, source: string?): boolean
    if not self.cooldowns[entity] or not self.cooldowns[entity][abilityId] then
        return false
    end
    
    local cooldownData = self.cooldowns[entity][abilityId]
    
    -- Apply reset modifier
    table.insert(cooldownData.modifiers, {
        type = "Reset",
        value = 0,
        source = source or "Unknown",
        appliedTime = os.clock()
    })
    
    -- Remove cooldown
    self.cooldowns[entity][abilityId] = nil
    
    -- Update stats
    self.stats.totalResets = self.stats.totalResets + 1
    self.stats.activeCooldowns = math.max(0, self.stats.activeCooldowns - 1)
    
    -- Fire event
    self:_fireCooldownEvent("Reset", entity, abilityId, cooldownData)
    
    return true
end

function CooldownManager:modifyCooldown(
    entity: Instance,
    abilityId: string,
    modifierType: "Flat" | "Percent" | "Extend",
    value: number,
    source: string
): boolean
    
    if not self.cooldowns[entity] or not self.cooldowns[entity][abilityId] then
        return false
    end
    
    local cooldownData = self.cooldowns[entity][abilityId]
    
    -- Apply modifier
    local modifier: CooldownModifier = {
        type = modifierType,
        value = value,
        source = source,
        appliedTime = os.clock()
    }
    
    table.insert(cooldownData.modifiers, modifier)
    
    -- Calculate new end time
    if modifierType == "Flat" then
        cooldownData.endTime = cooldownData.endTime - value
    elseif modifierType == "Percent" then
        local remaining = self:getCooldownRemaining(entity, abilityId)
        local reduction = remaining * value
        cooldownData.endTime = cooldownData.endTime - reduction
    elseif modifierType == "Extend" then
        cooldownData.endTime = cooldownData.endTime + value
    end
    
    -- Update duration
    cooldownData.duration = cooldownData.endTime - cooldownData.startTime
    
    return true
end

function CooldownManager:pauseCooldown(entity: Instance, abilityId: string): boolean
    if not self.cooldowns[entity] or not self.cooldowns[entity][abilityId] then
        return false
    end
    
    local cooldownData = self.cooldowns[entity][abilityId]
    
    if not cooldownData.isPaused then
        cooldownData.isPaused = true
        cooldownData.pausedTime = os.clock()
        
        -- Fire event
        self:_fireCooldownEvent("Paused", entity, abilityId, cooldownData)
        
        return true
    end
    
    return false
end

function CooldownManager:resumeCooldown(entity: Instance, abilityId: string): boolean
    if not self.cooldowns[entity] or not self.cooldowns[entity][abilityId] then
        return false
    end
    
    local cooldownData = self.cooldowns[entity][abilityId]
    
    if cooldownData.isPaused and cooldownData.pausedTime then
        local pauseDuration = os.clock() - cooldownData.pausedTime
        cooldownData.endTime = cooldownData.endTime + pauseDuration
        cooldownData.isPaused = false
        cooldownData.pausedTime = nil
        
        -- Fire event
        self:_fireCooldownEvent("Resumed", entity, abilityId, cooldownData)
        
        return true
    end
    
    return false
end

-- Global cooldown management

function CooldownManager:startGlobalCooldown(entity: Instance, duration: number)
    self.globalCooldowns[entity] = os.clock() + duration
end

function CooldownManager:isOnGlobalCooldown(entity: Instance): boolean
    local gcd = self.globalCooldowns[entity]
    return gcd and os.clock() < gcd or false
end

function CooldownManager:getGlobalCooldownRemaining(entity: Instance): number
    local gcd = self.globalCooldowns[entity]
    if not gcd then
        return 0
    end
    
    return math.max(0, gcd - os.clock())
end

-- Cooldown reduction management

function CooldownManager:applyCooldownReduction(
    entity: Instance,
    reduction: CooldownReduction
): string
    
    reduction.id = reduction.id or HttpService:GenerateGUID(false)
    
    if not self.cooldownReductions[entity] then
        self.cooldownReductions[entity] = {}
    end
    
    -- Handle stacking
    if not reduction.stackable then
        -- Remove existing reductions from same source
        for id, existingReduction in pairs(self.cooldownReductions[entity]) do
            if existingReduction.source == reduction.source then
                self:removeCooldownReduction(entity, id)
            end
        end
    end
    
    -- Set end time if duration is specified
    if reduction.duration then
        reduction.endTime = os.clock() + reduction.duration
    end
    
    reduction.isActive = true
    self.cooldownReductions[entity][reduction.id] = reduction
    
    -- Apply to active cooldowns immediately
    self:_applyReductionToActiveCooldowns(entity, reduction)
    
    return reduction.id
end

function CooldownManager:removeCooldownReduction(entity: Instance, reductionId: string): boolean
    if not self.cooldownReductions[entity] then
        return false
    end
    
    local reduction = self.cooldownReductions[entity][reductionId]
    if not reduction then
        return false
    end
    
    reduction.isActive = false
    self.cooldownReductions[entity][reductionId] = nil
    
    return true
end

function CooldownManager:_calculateModifiedCooldown(
    entity: Instance,
    abilityId: string,
    baseDuration: number
): number
    
    local modifiedDuration = baseDuration
    local totalReduction = 0
    
    -- Apply cooldown reductions
    if self.cooldownReductions[entity] then
        local reductions = {}
        
        for _, reduction in pairs(self.cooldownReductions[entity]) do
            if reduction.isActive then
                -- Check if this reduction affects this ability
                if not reduction.affectsAbilities or table.find(reduction.affectsAbilities, abilityId) then
                    table.insert(reductions, reduction)
                end
            end
        end
        
        -- Sort by priority
        table.sort(reductions, function(a, b)
            return a.priority > b.priority
        end)
        
        -- Apply reductions
        for _, reduction in ipairs(reductions) do
            if reduction.stackable then
                totalReduction = totalReduction + reduction.amount
            else
                totalReduction = math.max(totalReduction, reduction.amount)
            end
        end
    end
    
    -- Cap total reduction
    totalReduction = math.min(totalReduction, self.config.maxCooldownReduction)
    
    -- Apply reduction
    modifiedDuration = modifiedDuration * (1 - totalReduction)
    
    return modifiedDuration
end

function CooldownManager:_applyReductionToActiveCooldowns(entity: Instance, reduction: CooldownReduction)
    if not self.cooldowns[entity] then
        return
    end
    
    for abilityId, cooldownData in pairs(self.cooldowns[entity]) do
        -- Check if reduction affects this ability
        if not reduction.affectsAbilities or table.find(reduction.affectsAbilities, abilityId) then
            local remaining = self:getCooldownRemaining(entity, abilityId)
            local reducedRemaining = remaining * (1 - reduction.amount)
            cooldownData.endTime = os.clock() + reducedRemaining
        end
    end
end

-- Charge-based abilities

function CooldownManager:initializeCharges(
    entity: Instance,
    abilityId: string,
    maxCharges: number,
    rechargeTime: number,
    sharedWith: {string}?
)
    -- Safety check for nil entity
    if not entity then
        warn("[CooldownManager] Cannot initialize charges: entity is nil")
        return
    end
    
    if not self.chargeData[entity] then
        self.chargeData[entity] = {}
    end
    
    local charges: ChargeData = {
        abilityId = abilityId,
        currentCharges = maxCharges,
        maxCharges = maxCharges,
        rechargeTime = rechargeTime,
        lastUseTime = 0,
        recharging = false,
        nextChargeTime = nil,
        sharedWith = sharedWith
    }
    
    self.chargeData[entity][abilityId] = charges
    
    -- Initialize shared charges
    if sharedWith then
        for _, sharedAbility in ipairs(sharedWith) do
            self.chargeData[entity][sharedAbility] = charges
        end
    end
end

function CooldownManager:useCharge(entity: Instance, abilityId: string): boolean
    if not self.chargeData[entity] or not self.chargeData[entity][abilityId] then
        return false
    end
    
    local charges = self.chargeData[entity][abilityId]
    
    if charges.currentCharges <= 0 then
        return false
    end
    
    charges.currentCharges = charges.currentCharges - 1
    charges.lastUseTime = os.clock()
    
    -- Start recharging if not already
    if not charges.recharging then
        charges.recharging = true
        charges.nextChargeTime = os.clock() + charges.rechargeTime
    end
    
    -- Update stats
    self.stats.totalChargesUsed = self.stats.totalChargesUsed + 1
    
    -- Fire event
    self:_fireChargeEvent("Used", entity, abilityId, charges)
    
    return true
end

function CooldownManager:getCharges(entity: Instance, abilityId: string): (number?, number?)
    if not self.chargeData[entity] or not self.chargeData[entity][abilityId] then
        return nil, nil
    end
    
    local charges = self.chargeData[entity][abilityId]
    return charges.currentCharges, charges.maxCharges
end

function CooldownManager:addCharge(entity: Instance, abilityId: string, amount: number?): boolean
    if not self.chargeData[entity] or not self.chargeData[entity][abilityId] then
        return false
    end
    
    local charges = self.chargeData[entity][abilityId]
    local toAdd = amount or 1
    
    charges.currentCharges = math.min(charges.currentCharges + toAdd, charges.maxCharges)
    
    -- Stop recharging if at max
    if charges.currentCharges >= charges.maxCharges then
        charges.recharging = false
        charges.nextChargeTime = nil
    end
    
    -- Fire event
    self:_fireChargeEvent("Added", entity, abilityId, charges)
    
    return true
end

-- Reset triggers

function CooldownManager:registerResetTrigger(trigger: ResetTrigger)
    self.resetTriggers[trigger.id] = trigger
end

function CooldownManager:checkResetTriggers(
    entity: Instance,
    triggerType: string,
    context: {[string]: any}
)
    for _, trigger in pairs(self.resetTriggers) do
        if trigger.condition == triggerType or trigger.condition == "Custom" then
            -- Check cooldown on the trigger itself
            if trigger.cooldown and trigger.lastTriggerTime then
                if os.clock() - trigger.lastTriggerTime < trigger.cooldown then
                    continue
                end
            end
            
            -- Check chance
            if math.random() > trigger.chance then
                continue
            end
            
            -- Check custom condition
            if trigger.customCondition and not trigger.customCondition(entity, context) then
                continue
            end
            
            -- Reset abilities
            if trigger.affectsAbilities then
                for _, abilityId in ipairs(trigger.affectsAbilities) do
                    self:resetCooldown(entity, abilityId, `Trigger_{trigger.id}`)
                end
            else
                -- Reset all abilities
                if self.cooldowns[entity] then
                    for abilityId in pairs(self.cooldowns[entity]) do
                        self:resetCooldown(entity, abilityId, `Trigger_{trigger.id}`)
                    end
                end
            end
            
            -- Update trigger cooldown
            trigger.lastTriggerTime = os.clock()
        end
    end
end

function CooldownManager:_registerDefaultTriggers()
    -- Kill reset trigger
    self:registerResetTrigger({
        id = "KillReset",
        condition = "OnKill",
        chance = 1.0,
        affectsAbilities = nil, -- Reset all abilities
        cooldown = nil
    })
    
    -- Critical hit reset trigger
    self:registerResetTrigger({
        id = "CritReset",
        condition = "OnCrit",
        chance = 0.2, -- 20% chance
        affectsAbilities = {"M1", "M2"}, -- Only reset basic attacks
        cooldown = 5 -- Can only trigger once every 5 seconds
    })
end

-- Update loop

function CooldownManager:_setupUpdateLoop()
    local lastUpdate = os.clock()
    
    RunService.Heartbeat:Connect(function()
        local now = os.clock()
        
        if now - lastUpdate < self.config.updateRate then
            return
        end
        
        lastUpdate = now
        
        -- Update cooldowns
        for entity, cooldowns in pairs(self.cooldowns) do
            for abilityId, cooldownData in pairs(cooldowns) do
                if not cooldownData.isPaused and now >= cooldownData.endTime then
                    -- Cooldown completed
                    self:_completeCooldown(entity, abilityId, cooldownData)
                end
            end
        end
        
        -- Update charges
        for entity, chargeMap in pairs(self.chargeData) do
            local processedAbilities = {}
            
            for abilityId, charges in pairs(chargeMap) do
                -- Skip if already processed (shared charges)
                if processedAbilities[charges] then
                    continue
                end
                processedAbilities[charges] = true
                
                if charges.recharging and charges.nextChargeTime and now >= charges.nextChargeTime then
                    -- Add a charge
                    charges.currentCharges = charges.currentCharges + 1
                    
                    if charges.currentCharges >= charges.maxCharges then
                        -- Fully recharged
                        charges.recharging = false
                        charges.nextChargeTime = nil
                    else
                        -- Schedule next charge
                        charges.nextChargeTime = now + charges.rechargeTime
                    end
                    
                    -- Fire event
                    self:_fireChargeEvent("Recharged", entity, abilityId, charges)
                end
            end
        end
        
        -- Update cooldown reductions
        for entity, reductions in pairs(self.cooldownReductions) do
            for id, reduction in pairs(reductions) do
                if reduction.endTime and now >= reduction.endTime then
                    self:removeCooldownReduction(entity, id)
                end
            end
        end
        
        -- Clean up disconnected entities
        for entity in pairs(self.cooldowns) do
            if not entity.Parent then
                self:clearEntityCooldowns(entity)
            end
        end
    end)
end

function CooldownManager:_completeCooldown(entity: Instance, abilityId: string, cooldownData: CooldownData)
    -- Remove from active cooldowns
    if self.cooldowns[entity] then
        self.cooldowns[entity][abilityId] = nil
        
        -- Clean up empty tables
        if next(self.cooldowns[entity]) == nil then
            self.cooldowns[entity] = nil
        end
    end
    
    -- Update stats
    self.stats.totalCooldownsCompleted = self.stats.totalCooldownsCompleted + 1
    self.stats.activeCooldowns = math.max(0, self.stats.activeCooldowns - 1)
    
    -- Fire event
    self:_fireCooldownEvent("Completed", entity, abilityId, cooldownData)
end

-- Events

function CooldownManager:_fireCooldownEvent(
    eventType: string,
    entity: Instance,
    abilityId: string,
    cooldownData: CooldownData
)
    -- Fire event for other systems
    -- Implementation depends on event system
end

function CooldownManager:_fireChargeEvent(
    eventType: string,
    entity: Instance,
    abilityId: string,
    chargeData: ChargeData
)
    -- Fire event for other systems
    -- Implementation depends on event system
end

-- Public API

function CooldownManager:getAllCooldowns(entity: Instance): {[string]: CooldownData}?
    return self.cooldowns[entity]
end

function CooldownManager:clearEntityCooldowns(entity: Instance)
    print("[CooldownManager] Clearing all cooldowns for entity:", entity, entity and entity.Name or "nil")
    self.cooldowns[entity] = nil
    self.globalCooldowns[entity] = nil
    self.cooldownReductions[entity] = nil
    self.chargeData[entity] = nil
end

function CooldownManager:getStats(): {[string]: number}
    return self.stats
end

function CooldownManager:getCooldownProgress(entity: Instance, abilityId: string): number
    if not self.cooldowns[entity] or not self.cooldowns[entity][abilityId] then
        return 1 -- Fully available
    end
    
    local cooldownData = self.cooldowns[entity][abilityId]
    local elapsed = os.clock() - cooldownData.startTime
    local progress = elapsed / cooldownData.duration
    
    return math.min(1, progress)
end

-- Singleton
local manager = nil

function CooldownManager.get()
    if not manager then
        manager = CooldownManager.new()
    end
    return manager
end

return CooldownManager