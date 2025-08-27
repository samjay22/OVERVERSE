--!strict

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Types)

type ComboConfig = Types.ComboConfig
type AbilityInstance = Types.AbilityInstance
type EffectConfig = Types.EffectConfig

-- Ability Combo System: Manages ability combinations and chaining
local AbilityComboSystem = {}
AbilityComboSystem.__index = AbilityComboSystem

function AbilityComboSystem.new()
    local self = setmetatable({}, AbilityComboSystem)
    
    -- Combo tracking per entity
    self.comboStates = {} :: {[Instance]: ComboState}
    
    -- Registered combo patterns
    self.comboPatterns = {} :: {[string]: ComboPattern}
    
    -- Combo chains (sequences)
    self.comboChains = {} :: {[string]: ComboChain}
    
    -- Statistics
    self.stats = {
        totalCombosTriggered = 0,
        totalChainsCompleted = 0,
        highestComboCount = 0,
        activeComboStates = 0
    }
    
    -- Configuration
    self.config = {
        defaultComboWindow = 2.0,
        maxComboLength = 10,
        comboBonusPerHit = 0.1, -- 10% damage bonus per combo
        comboDecayTime = 3.0
    }
    
    -- Initialize
    self:_registerDefaultCombos()
    self:_setupUpdateLoop()
    
    return self
end

type ComboState = {
    entity: Instance,
    currentCombo: {string}, -- Ability IDs in order
    comboCount: number,
    lastAbilityTime: number,
    comboMultiplier: number,
    activeWindow: number,
    targetEntity: Instance?, -- For targeted combos
    comboData: {[string]: any},
    chainProgress: {[string]: number} -- Progress for each chain
}

type ComboPattern = {
    id: string,
    name: string,
    sequence: {string}, -- Required ability sequence
    window: number, -- Time window for each step
    requirements: {
        targetSame: boolean?, -- All abilities must hit same target
        minDamage: number?, -- Minimum damage to continue combo
        maxDistance: number?, -- Max distance between casts
        customCheck: ((state: ComboState) -> boolean)?
    }?,
    effects: {EffectConfig}, -- Effects when combo completes
    bonuses: {
        damageMultiplier: number?,
        cooldownReduction: number?,
        resourceRefund: number?,
        custom: {[string]: any}?
    }?,
    visualization: {
        progressBar: boolean?,
        particleEffect: string?,
        soundEffect: string?,
        screenEffect: string?
    }?
}

type ComboChain = {
    id: string,
    name: string,
    branches: {ComboChainNode},
    rewards: {[number]: ComboReward}, -- Rewards at different chain lengths
    maxLength: number,
    resetOnMiss: boolean
}

type ComboChainNode = {
    abilityId: string,
    next: {ComboChainNode}?,
    alternates: {string}?, -- Alternative abilities that can continue the chain
    window: number?,
    bonusEffects: {EffectConfig}?
}

type ComboReward = {
    effects: {EffectConfig}?,
    modifiers: {Types.AbilityModifier}?,
    resources: {[Types.ResourceType]: number}?,
    customReward: ((entity: Instance) -> ())?
}

-- Core combo tracking

function AbilityComboSystem:onAbilityUsed(
    entity: Instance,
    abilityId: string,
    target: Instance?,
    context: {[string]: any}?
)
    -- Get or create combo state
    local state = self:_getOrCreateComboState(entity)
    
    -- Update combo timing
    local now = os.clock()
    local timeSinceLastAbility = now - state.lastAbilityTime
    
    -- Check if combo window expired
    if timeSinceLastAbility > state.activeWindow then
        self:resetCombo(entity, "WindowExpired")
    end
    
    -- Add ability to combo sequence
    table.insert(state.currentCombo, abilityId)
    state.lastAbilityTime = now
    
    -- Update combo count and multiplier
    state.comboCount = state.comboCount + 1
    state.comboMultiplier = 1 + (state.comboCount - 1) * self.config.comboBonusPerHit
    
    -- Track highest combo
    if state.comboCount > self.stats.highestComboCount then
        self.stats.highestComboCount = state.comboCount
    end
    
    -- Check for combo patterns
    self:_checkComboPatterns(state)
    
    -- Update combo chains
    self:_updateComboChains(state, abilityId)
    
    -- Store context data
    if context then
        for key, value in pairs(context) do
            state.comboData[key] = value
        end
    end
    
    -- Update target for targeted combos
    if target then
        if state.targetEntity and state.targetEntity ~= target then
            -- Target changed, might break some combos
            self:_handleTargetChange(state, target)
        end
        state.targetEntity = target
    end
    
    -- Fire combo event
    self:_fireComboEvent("AbilityAdded", entity, abilityId, state)
end

function AbilityComboSystem:resetCombo(entity: Instance, reason: string?)
    local state = self.comboStates[entity]
    if not state then
        return
    end
    
    -- Fire event before reset
    if state.comboCount > 0 then
        self:_fireComboEvent("ComboReset", entity, reason or "Manual", state)
    end
    
    -- Reset state
    state.currentCombo = {}
    state.comboCount = 0
    state.comboMultiplier = 1
    state.activeWindow = self.config.defaultComboWindow
    state.targetEntity = nil
    state.comboData = {}
    state.chainProgress = {}
end

function AbilityComboSystem:getComboMultiplier(entity: Instance): number
    local state = self.comboStates[entity]
    return state and state.comboMultiplier or 1
end

function AbilityComboSystem:getComboCount(entity: Instance): number
    local state = self.comboStates[entity]
    return state and state.comboCount or 0
end

-- Combo pattern matching

function AbilityComboSystem:registerComboPattern(pattern: ComboPattern)
    self.comboPatterns[pattern.id] = pattern
end

function AbilityComboSystem:_checkComboPatterns(state: ComboState)
    for patternId, pattern in pairs(self.comboPatterns) do
        if self:_matchesPattern(state, pattern) then
            self:_triggerComboPattern(state, pattern)
        end
    end
end

function AbilityComboSystem:_matchesPattern(state: ComboState, pattern: ComboPattern): boolean
    local sequence = pattern.sequence
    local currentCombo = state.currentCombo
    
    -- Check if current combo ends with the pattern sequence
    if #currentCombo < #sequence then
        return false
    end
    
    local startIndex = #currentCombo - #sequence + 1
    for i = 1, #sequence do
        if currentCombo[startIndex + i - 1] ~= sequence[i] then
            return false
        end
    end
    
    -- Check additional requirements
    if pattern.requirements then
        local reqs = pattern.requirements
        
        if reqs.targetSame and not state.targetEntity then
            return false
        end
        
        if reqs.minDamage then
            local totalDamage = state.comboData.totalDamage or 0
            if totalDamage < reqs.minDamage then
                return false
            end
        end
        
        if reqs.customCheck and not reqs.customCheck(state) then
            return false
        end
    end
    
    return true
end

function AbilityComboSystem:_triggerComboPattern(state: ComboState, pattern: ComboPattern)
    -- Apply combo effects
    if pattern.effects then
        local effectComposer = self:_getEffectComposer()
        if effectComposer then
            for _, effect in ipairs(pattern.effects) do
                effectComposer:executeEffect(effect, state.entity, state.targetEntity)
            end
        end
    end
    
    -- Apply bonuses
    if pattern.bonuses then
        self:_applyComboBonus(state, pattern.bonuses)
    end
    
    -- Trigger visualization
    if pattern.visualization then
        self:_showComboVisualization(state, pattern.visualization)
    end
    
    -- Update stats
    self.stats.totalCombosTriggered = self.stats.totalCombosTriggered + 1
    
    -- Fire event
    self:_fireComboEvent("PatternTriggered", state.entity, pattern.id, state)
    
    -- Remove pattern from current combo to allow re-triggering
    for _ = 1, #pattern.sequence do
        table.remove(state.currentCombo, #state.currentCombo - #pattern.sequence + 1)
    end
end

-- Combo chains

function AbilityComboSystem:registerComboChain(chain: ComboChain)
    self.comboChains[chain.id] = chain
end

function AbilityComboSystem:_updateComboChains(state: ComboState, abilityId: string)
    for chainId, chain in pairs(self.comboChains) do
        local progress = state.chainProgress[chainId] or 0
        
        -- Check if ability continues the chain
        local nextNode = self:_findNextChainNode(chain, progress, abilityId)
        if nextNode then
            progress = progress + 1
            state.chainProgress[chainId] = progress
            
            -- Check for rewards
            local reward = chain.rewards[progress]
            if reward then
                self:_grantChainReward(state, reward)
            end
            
            -- Apply bonus effects
            if nextNode.bonusEffects then
                local effectComposer = self:_getEffectComposer()
                if effectComposer then
                    for _, effect in ipairs(nextNode.bonusEffects) do
                        effectComposer:executeEffect(effect, state.entity, state.targetEntity)
                    end
                end
            end
            
            -- Check if chain completed
            if progress >= chain.maxLength then
                self:_completeChain(state, chain)
            end
        elseif chain.resetOnMiss then
            state.chainProgress[chainId] = 0
        end
    end
end

function AbilityComboSystem:_findNextChainNode(
    chain: ComboChain,
    currentProgress: number,
    abilityId: string
): ComboChainNode?
    
    -- Start from root if no progress
    if currentProgress == 0 then
        for _, node in ipairs(chain.branches) do
            if node.abilityId == abilityId then
                return node
            end
            if node.alternates then
                for _, alt in ipairs(node.alternates) do
                    if alt == abilityId then
                        return node
                    end
                end
            end
        end
    else
        -- Find current node and check next
        -- This would require a more complex tree traversal
        -- Simplified for this implementation
    end
    
    return nil
end

function AbilityComboSystem:_completeChain(state: ComboState, chain: ComboChain)
    -- Grant final reward
    local finalReward = chain.rewards[chain.maxLength]
    if finalReward then
        self:_grantChainReward(state, finalReward)
    end
    
    -- Reset chain progress
    state.chainProgress[chain.id] = 0
    
    -- Update stats
    self.stats.totalChainsCompleted = self.stats.totalChainsCompleted + 1
    
    -- Fire event
    self:_fireComboEvent("ChainCompleted", state.entity, chain.id, state)
end

function AbilityComboSystem:_grantChainReward(state: ComboState, reward: ComboReward)
    -- Apply effects
    if reward.effects then
        local effectComposer = self:_getEffectComposer()
        if effectComposer then
            for _, effect in ipairs(reward.effects) do
                effectComposer:executeEffect(effect, state.entity, state.targetEntity)
            end
        end
    end
    
    -- Apply modifiers
    if reward.modifiers then
        local modifierSystem = self:_getModifierSystem()
        if modifierSystem then
            for _, modifier in ipairs(reward.modifiers) do
                modifierSystem:applyModifier(state.entity, modifier)
            end
        end
    end
    
    -- Grant resources
    if reward.resources then
        -- Implementation depends on resource system
    end
    
    -- Custom reward
    if reward.customReward then
        reward.customReward(state.entity)
    end
end

-- Default combos

function AbilityComboSystem:_registerDefaultCombos()
    -- Basic attack combo
    self:registerComboPattern({
        id = "TripleStrike",
        name = "Triple Strike",
        sequence = {"M1", "M1", "M1"},
        window = 1.5,
        requirements = {
            targetSame = true
        },
        effects = {
            {
                type = "Damage",
                trigger = "OnCast",
                amount = { base = 100 },
                damageType = "Physical"
            }
        },
        bonuses = {
            damageMultiplier = 1.5
        },
        visualization = {
            particleEffect = "ComboTripleStrike",
            soundEffect = "ComboComplete"
        }
    })
    
    -- Spell combo
    self:registerComboPattern({
        id = "ElementalFusion",
        name = "Elemental Fusion",
        sequence = {"fireball", "frostbolt", "lightning"},
        window = 3.0,
        effects = {
            {
                type = "Area",
                trigger = "OnCast",
                radius = 20,
                effects = {
                    {
                        type = "Damage",
                        trigger = "OnHit",
                        amount = { base = 200 },
                        damageType = "Magical"
                    }
                }
            }
        },
        bonuses = {
            cooldownReduction = 0.5
        }
    })
    
    -- Movement combo
    self:registerComboPattern({
        id = "DashStrike",
        name = "Dash Strike",
        sequence = {"dash", "M1"},
        window = 0.5,
        effects = {
            {
                type = "Buff",
                trigger = "OnCast",
                duration = 3,
                customData = {
                    modifier = {
                        id = "DashStrikeBuff",
                        statModifiers = {
                            damage = { percent = 0.3 }
                        }
                    }
                }
            }
        }
    })
    
    -- Defense combo
    self:registerComboPattern({
        id = "PerfectGuard",
        name = "Perfect Guard",
        sequence = {"block", "parry"},
        window = 0.3,
        effects = {
            {
                type = "Shield",
                trigger = "OnCast",
                amount = { base = 500 },
                duration = 5
            },
            {
                type = "Buff",
                trigger = "OnCast",
                duration = 5,
                customData = {
                    modifier = {
                        id = "PerfectGuardBuff",
                        behaviorModifiers = {
                            custom = {
                                damageReflection = 0.5
                            }
                        }
                    }
                }
            }
        }
    })
    
    -- Ultimate combo
    self:registerComboPattern({
        id = "DevastatingCombo",
        name = "Devastating Combo",
        sequence = {"Q", "E", "R"},
        window = 2.0,
        requirements = {
            minDamage = 500
        },
        effects = {
            {
                type = "Execute",
                trigger = "OnCast",
                customData = {
                    threshold = 0.3 -- Execute at 30% health
                }
            }
        },
        bonuses = {
            resourceRefund = 0.5
        },
        visualization = {
            screenEffect = "DevastatingComboScreen",
            particleEffect = "DevastatingComboParticles"
        }
    })
    
    -- Register combo chains
    self:_registerDefaultChains()
end

function AbilityComboSystem:_registerDefaultChains()
    -- Basic attack chain
    self:registerComboChain({
        id = "BasicAttackChain",
        name = "Basic Attack Chain",
        branches = {
            {
                abilityId = "M1",
                next = {
                    {
                        abilityId = "M1",
                        alternates = {"M2"},
                        window = 1.0,
                        next = {
                            {
                                abilityId = "M1",
                                alternates = {"M2", "E"},
                                window = 1.0,
                                bonusEffects = {
                                    {
                                        type = "Buff",
                                        trigger = "OnCast",
                                        duration = 5,
                                        customData = {
                                            modifier = {
                                                id = "AttackChainBuff",
                                                statModifiers = {
                                                    damage = { percent = 0.2 }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        },
        rewards = {
            [3] = {
                resources = {
                    Stamina = 20
                }
            },
            [5] = {
                effects = {
                    {
                        type = "Heal",
                        trigger = "OnCast",
                        amount = { base = 100 }
                    }
                }
            },
            [10] = {
                modifiers = {
                    {
                        id = "ChainMastery",
                        duration = 30,
                        statModifiers = {
                            cooldown = { percent = -0.5 }
                        }
                    }
                }
            }
        },
        maxLength = 10,
        resetOnMiss = false
    })
end

-- Helper methods

function AbilityComboSystem:_getOrCreateComboState(entity: Instance): ComboState
    if not self.comboStates[entity] then
        self.comboStates[entity] = {
            entity = entity,
            currentCombo = {},
            comboCount = 0,
            lastAbilityTime = 0,
            comboMultiplier = 1,
            activeWindow = self.config.defaultComboWindow,
            targetEntity = nil,
            comboData = {},
            chainProgress = {}
        }
        
        self.stats.activeComboStates = self.stats.activeComboStates + 1
    end
    
    return self.comboStates[entity]
end

function AbilityComboSystem:_handleTargetChange(state: ComboState, newTarget: Instance)
    -- Check which patterns require same target
    for patternId, pattern in pairs(self.comboPatterns) do
        if pattern.requirements and pattern.requirements.targetSame then
            -- This pattern might be broken
            -- Could implement partial reset logic here
        end
    end
end

function AbilityComboSystem:_applyComboBonus(state: ComboState, bonuses: {[string]: any})
    -- Apply damage multiplier
    if bonuses.damageMultiplier then
        state.comboMultiplier = state.comboMultiplier * bonuses.damageMultiplier
    end
    
    -- Apply cooldown reduction
    if bonuses.cooldownReduction then
        -- Implementation depends on cooldown system
    end
    
    -- Refund resources
    if bonuses.resourceRefund then
        -- Implementation depends on resource system
    end
    
    -- Apply custom bonuses
    if bonuses.custom then
        for key, value in pairs(bonuses.custom) do
            state.comboData[`bonus_{key}`] = value
        end
    end
end

function AbilityComboSystem:_showComboVisualization(state: ComboState, visualization: {[string]: any})
    -- Show progress bar
    if visualization.progressBar then
        -- Implementation depends on UI system
    end
    
    -- Play particle effect
    if visualization.particleEffect then
        -- Implementation depends on effect system
    end
    
    -- Play sound effect
    if visualization.soundEffect then
        -- Implementation depends on audio system
    end
    
    -- Show screen effect
    if visualization.screenEffect then
        -- Implementation depends on camera system
    end
end

function AbilityComboSystem:_fireComboEvent(eventType: string, entity: Instance, data: any, state: ComboState)
    warn("Combo event fired:", eventType, entity, data, state)
end

function AbilityComboSystem:_setupUpdateLoop()
    -- Decay combos over time
    RunService.Heartbeat:Connect(function()
        local now = os.clock()
        
        for entity, state in pairs(self.comboStates) do
            if state.comboCount > 0 then
                local timeSinceLastAbility = now - state.lastAbilityTime
                
                if timeSinceLastAbility > self.config.comboDecayTime then
                    self:resetCombo(entity, "Timeout")
                end
            end
            
            -- Clean up inactive states
            if not entity.Parent then
                self.comboStates[entity] = nil
                self.stats.activeComboStates = self.stats.activeComboStates - 1
            end
        end
    end)
end

-- Service references

function AbilityComboSystem:_getEffectComposer()
    -- Return reference to effect composer
    local EffectComposer = require(script.Parent.EffectComposer)
    return EffectComposer.get()
end

function AbilityComboSystem:_getModifierSystem()
    -- Return reference to modifier system
    local AbilityModifierSystem = require(script.Parent.AbilityModifierSystem)
    return AbilityModifierSystem.get()
end

-- Public API

function AbilityComboSystem:getComboState(entity: Instance): ComboState?
    return self.comboStates[entity]
end

function AbilityComboSystem:getStats(): {[string]: number}
    return self.stats
end

function AbilityComboSystem:clearComboState(entity: Instance)
    self.comboStates[entity] = nil
    self.stats.activeComboStates = math.max(0, self.stats.activeComboStates - 1)
end

-- Singleton
local system = nil

function AbilityComboSystem.get()
    if not system then
        system = AbilityComboSystem.new()
    end
    return system
end

return AbilityComboSystem