--!strict

local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")

local Types = require(script.Parent.Types)

type EffectConfig = Types.EffectConfig
type EffectType = Types.EffectType
type DamageType = Types.DamageType
type ScalableValue = Types.ScalableValue

-- Effect Composer: Handles composition and execution of ability effects
local EffectComposer = {}
EffectComposer.__index = EffectComposer

-- Effect handlers registry
local effectHandlers = {} :: {[EffectType]: (any) -> ()}

function EffectComposer.new()
    local self = setmetatable({}, EffectComposer)
    
    -- Active effects tracking
    self.activeEffects = {} :: {[Instance]: {ActiveEffect}}
    self.effectsByType = {} :: {[EffectType]: {ActiveEffect}}
    self.periodicEffects = {} :: {ActiveEffect}
    
    -- Effect pools for performance
    self.effectPools = {} :: {[EffectType]: {any}}
    
    -- Statistics
    self.stats = {
        totalEffectsCreated = 0,
        totalEffectsCompleted = 0,
        activeEffectCount = 0,
        pooledEffectCount = 0
    }
    
    -- Initialize
    self:_registerDefaultHandlers()
    self:_startUpdateLoop()
    
    return self
end

type ActiveEffect = {
    id: string,
    config: EffectConfig,
    caster: Instance,
    target: Instance?,
    startTime: number,
    duration: number?,
    tickRate: number?,
    lastTick: number?,
    stacks: number,
    data: {[string]: any},
    children: {ActiveEffect}?,
    parent: ActiveEffect?,
    onComplete: (() -> ())?,
    onTick: ((effect: ActiveEffect) -> ())?
}

-- Core effect execution

function EffectComposer:executeEffect(
    config: EffectConfig, 
    caster: Instance, 
    target: Instance?, 
    context: {[string]: any}?
): ActiveEffect?
    
    -- Check trigger condition
    if not self:_shouldTrigger(config, caster, target, context) then
        return nil
    end
    
    -- Create active effect
    local effect = self:_createActiveEffect(config, caster, target)
    
    -- Apply effect data from context
    if context then
        for key, value in pairs(context) do
            effect.data[key] = value
        end
    end
    
    -- Execute based on effect type
    local handler = effectHandlers[config.type]
    if handler then
        local success, result = pcall(handler, self, effect, config, caster, target)
        if not success then
            warn(`[EffectComposer] Failed to execute effect {config.type}: {result}`)
            return nil
        end
    else
        warn(`[EffectComposer] No handler for effect type: {config.type}`)
        return nil
    end
    
    -- Track the effect
    self:_trackEffect(effect)
    
    -- Execute child effects if any
    if config.effects then
        effect.children = {}
        for _, childConfig in ipairs(config.effects) do
            local childEffect = self:executeEffect(childConfig, caster, target, effect.data)
            if childEffect then
                childEffect.parent = effect
                table.insert(effect.children, childEffect)
            end
        end
    end
    
    -- Handle duration-based effects
    if config.duration then
        effect.duration = config.duration
        
        -- Setup periodic ticks if needed
        if config.tickRate then
            effect.tickRate = config.tickRate
            effect.lastTick = os.clock()
            table.insert(self.periodicEffects, effect)
        end
        
        -- Schedule cleanup
        task.delay(config.duration, function()
            self:completeEffect(effect)
        end)
    end
    
    self.stats.totalEffectsCreated = self.stats.totalEffectsCreated + 1
    self.stats.activeEffectCount = self.stats.activeEffectCount + 1
    
    return effect
end

function EffectComposer:completeEffect(effect: ActiveEffect)
    -- Remove from tracking
    self:_untrackEffect(effect)
    
    -- Complete child effects
    if effect.children then
        for _, child in ipairs(effect.children) do
            self:completeEffect(child)
        end
    end
    
    -- Call completion callback
    if effect.onComplete then
        effect.onComplete()
    end
    
    -- Return to pool if applicable
    self:_returnToPool(effect)
    
    self.stats.totalEffectsCompleted = self.stats.totalEffectsCompleted + 1
    self.stats.activeEffectCount = self.stats.activeEffectCount - 1
end

-- Effect stacking and modification

function EffectComposer:stackEffect(effect: ActiveEffect, additionalStacks: number)
    local config = effect.config
    local maxStacks = config.maxStacks or math.huge
    
    effect.stacks = math.min(effect.stacks + additionalStacks, maxStacks)
    
    -- Refresh duration if configured
    if config.refreshable and config.duration then
        effect.startTime = os.clock()
    end
    
    -- Trigger stack change handler if defined
    if effect.data.onStackChange then
        effect.data.onStackChange(effect)
    end
end

function EffectComposer:modifyEffect(effect: ActiveEffect, modifications: {[string]: any})
    for key, value in pairs(modifications) do
        if key == "duration" and effect.duration then
            effect.duration = value
        elseif key == "tickRate" and effect.tickRate then
            effect.tickRate = value
        elseif key == "stacks" then
            self:stackEffect(effect, value - effect.stacks)
        else
            effect.data[key] = value
        end
    end
end

-- Default effect handlers

function EffectComposer:_registerDefaultHandlers()
    -- Damage effect
    effectHandlers.Damage = function(self, effect, config, caster, target)
        if not target then 
            print("[EffectComposer] No target for damage effect")
            return 
        end
        
        print("[EffectComposer] Applying damage effect to:", target, target and target.Name or "nil")
        
        local amount = self:_calculateValue(config.amount, effect.data.stats)
        local damageType = config.damageType or "Physical"
        
        print("[EffectComposer] Damage amount:", amount, "Type:", damageType)
        
        -- Apply damage directly to humanoid
        local humanoid = target:FindFirstChildOfClass("Humanoid")
        if humanoid then
            print("[EffectComposer] Found humanoid, applying damage:", amount)
            -- For now, apply damage directly
            -- Later this can be enhanced with damage types, resistances, etc.
            humanoid:TakeDamage(amount)
            
            -- Fire damage event for other systems to listen to
            local ReplicatedStorage = game:GetService("ReplicatedStorage")
            local EventBus = ReplicatedStorage:FindFirstChild("EventBus")
            if EventBus then
                local DamageEvent = EventBus:FindFirstChild("DamageEvent")
                if DamageEvent and DamageEvent:IsA("BindableEvent") then
                    DamageEvent:Fire({
                        target = target,
                        damage = amount,
                        damageType = damageType,
                        source = caster,
                        canCrit = config.canCrit,
                        critMultiplier = config.critMultiplier,
                        effectId = effect.id
                    })
                end
            end
        else
            print("[EffectComposer] No humanoid found in target!")
            -- List all children for debugging
            local children = {}
            for _, child in ipairs(target:GetChildren()) do
                table.insert(children, child.Name .. " (" .. child.ClassName .. ")")
            end
            print("[EffectComposer] Target children:", table.concat(children, ", "))
        end
        
        effect.data.damageDealt = amount
    end
    
    -- Heal effect
    effectHandlers.Heal = function(self, effect, config, caster, target)
        if not target then return end
        
        local amount = self:_calculateValue(config.amount, effect.data.stats)
        
        local healthComponent = target:FindFirstChild("HealthComponent")
        if healthComponent then
            healthComponent:Heal(amount, caster)
        end
        
        effect.data.healingDone = amount
    end
    
    -- Shield effect
    effectHandlers.Shield = function(self, effect, config, caster, target)
        if not target then return end
        
        local amount = self:_calculateValue(config.amount, effect.data.stats)
        local duration = config.duration or 10
        
        local healthComponent = target:FindFirstChild("HealthComponent")
        if healthComponent and healthComponent.AddShield then
            local shieldId = healthComponent:AddShield(amount, duration, effect.id)
            effect.data.shieldId = shieldId
            effect.data.shieldAmount = amount
        end
    end
    
    -- Stun effect
    effectHandlers.Stun = function(self, effect, config, caster, target)
        if not target then return end
        
        local movementComponent = target:FindFirstChild("MovementComponent")
        if movementComponent and movementComponent.SetStunned then
            movementComponent:SetStunned(true, config.duration or 1)
            
            effect.onComplete = function()
                if movementComponent and movementComponent.SetStunned then
                    movementComponent:SetStunned(false)
                end
            end
        end
    end
    
    -- Slow effect
    effectHandlers.Slow = function(self, effect, config, caster, target)
        if not target then return end
        
        local amount = config.amount or 0.5 -- 50% slow by default
        
        local movementComponent = target:FindFirstChild("MovementComponent")
        if movementComponent and movementComponent.ApplySpeedModifier then
            local modifierId = movementComponent:ApplySpeedModifier(1 - amount, config.duration)
            effect.data.modifierId = modifierId
        end
    end
    
    -- Knockback effect
    effectHandlers.Knockback = function(self, effect, config, caster, target)
        if not target then return end
        
        local distance = config.distance or 20
        local speed = config.speed or 50
        local direction = self:_getDirection(config.direction, caster, target)
        
        -- Server should only update physics/game state, not create visual effects
        -- The client will handle visual representation of knockback
        local character = target:IsA("Model") and target or target:FindFirstAncestorOfClass("Model")
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                -- Only apply physics forces for gameplay, not visuals
                local bodyVelocity = Instance.new("BodyVelocity")
                bodyVelocity.MaxForce = Vector3.new(4000, 4000, 4000)
                bodyVelocity.Velocity = direction * speed
                bodyVelocity.Parent = rootPart
                
                Debris:AddItem(bodyVelocity, distance / speed)
            end
        end
    end
    
    -- Projectile effect
    effectHandlers.Projectile = function(self, effect, config, caster, target)
        -- Server should not create visual projectiles
        -- Only handle hit detection and damage calculation
        -- Visual effects should be handled by client
        
        -- Just calculate hit timing and trigger damage
        local casterPos = self:_getPosition(caster)
        local targetPos = target and self:_getPosition(target) or effect.data.targetPosition
        
        if targetPos then
            local distance = (targetPos - casterPos).Magnitude
            local speed = config.speed or 50
            local travelTime = distance / speed
            
            -- Simulate projectile travel time then apply effects
            task.delay(travelTime, function()
                -- Trigger on-hit effects
                if config.effects then
                    for _, childConfig in ipairs(config.effects) do
                        if childConfig.trigger == "OnHit" then
                            self:executeEffect(childConfig, caster, target, effect.data)
                        end
                    end
                end
            end)
        end
    end
    
    -- Area effect
    effectHandlers.Area = function(self, effect, config, caster, target)
        local position = target and self:_getPosition(target) or effect.data.position
        if not position then return end
        
        local radius = config.radius or 10
        local targets = self:_getTargetsInArea(position, radius, config.filter)
        
        -- Apply child effects to all targets
        if config.effects then
            for _, target in ipairs(targets) do
                for _, childConfig in ipairs(config.effects) do
                    self:executeEffect(childConfig, caster, target, effect.data)
                end
            end
        end
        
        effect.data.targetsHit = targets
    end
    
    -- Dash effect
    effectHandlers.Dash = function(self, effect, config, caster, target)
        local distance = config.distance or 20
        local speed = config.speed or 100
        local direction = self:_getDirection(config.direction or "Forward", caster, target)
        
        local character = caster:IsA("Model") and caster or caster:FindFirstAncestorOfClass("Model")
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                -- Disable movement during dash
                local humanoid = character:FindFirstChild("Humanoid")
                if humanoid then
                    local oldWalkSpeed = humanoid.WalkSpeed
                    humanoid.WalkSpeed = 0
                    
                    -- Apply physics-based movement only (no visuals)
                    local bodyPosition = Instance.new("BodyPosition")
                    bodyPosition.MaxForce = Vector3.new(4000, 0, 4000)
                    bodyPosition.Position = rootPart.Position + direction * distance
                    bodyPosition.Parent = rootPart
                    
                    local dashTime = distance / speed
                    
                    task.delay(dashTime, function()
                        if bodyPosition and bodyPosition.Parent then
                            bodyPosition:Destroy()
                        end
                        if humanoid then
                            humanoid.WalkSpeed = oldWalkSpeed
                        end
                    end)
                    
                    effect.data.dashStartPos = rootPart.Position
                    effect.data.dashEndPos = rootPart.Position + direction * distance
                end
            end
        end
    end
    
    -- Channel effect
    effectHandlers.Channel = function(self, effect, config, caster, target)
        local channelTime = config.duration or 3
        local onChannel = config.callbacks and config.callbacks.onChannel
        
        effect.data.channeling = true
        effect.data.channelProgress = 0
        
        -- Update channel progress
        local startTime = os.clock()
        local connection
        connection = RunService.Heartbeat:Connect(function()
            local elapsed = os.clock() - startTime
            local progress = math.min(elapsed / channelTime, 1)
            
            effect.data.channelProgress = progress
            
            if onChannel then
                onChannel(caster, progress)
            end
            
            if progress >= 1 then
                connection:Disconnect()
                effect.data.channeling = false
                
                -- Trigger completion effects
                if config.effects then
                    for _, childConfig in ipairs(config.effects) do
                        if childConfig.trigger == "OnEnd" then
                            self:executeEffect(childConfig, caster, target, effect.data)
                        end
                    end
                end
            end
        end)
        
        effect.data.channelConnection = connection
        
        effect.onComplete = function()
            if connection then
                connection:Disconnect()
            end
            effect.data.channeling = false
        end
    end
    
    -- Add more effect handlers...
    self:_registerAdvancedHandlers()
end

function EffectComposer:_registerAdvancedHandlers()
    -- Buff/Debuff effects
    effectHandlers.Buff = function(self, effect, config, caster, target)
        if not target then return end
        
        local modifierSystem = self:_getModifierSystem()
        if modifierSystem then
            local modifier = config.customData and config.customData.modifier
            if modifier then
                modifierSystem:ApplyModifier(target, modifier, config.duration)
                effect.data.modifierId = modifier.id
            end
        end
    end
    
    effectHandlers.Debuff = effectHandlers.Buff -- Same logic, different data
    
    -- Transform effect
    effectHandlers.Transform = function(self, effect, config, caster, target)
        if not target then return end
        
        local transformModel = config.customData and config.customData.model
        if transformModel then
            -- Store original appearance
            effect.data.originalAppearance = {}
            
            -- Apply transformation
            -- Implementation depends on how characters are structured
        end
    end
    
    -- Summon effect
    effectHandlers.Summon = function(self, effect, config, caster, target)
        local summonType = config.customData and config.customData.summonType
        local position = target and self:_getPosition(target) or effect.data.position
        
        if summonType and position then
            -- Create summoned unit
            -- Implementation depends on entity system
            
            effect.data.summonedUnit = nil -- placeholder
        end
    end
    
    -- More advanced effects can be added here...
end

-- Helper methods

function EffectComposer:_createActiveEffect(config: EffectConfig, caster: Instance, target: Instance?): ActiveEffect
    return {
        id = HttpService:GenerateGUID(false),
        config = config,
        caster = caster,
        target = target,
        startTime = os.clock(),
        duration = nil,
        tickRate = nil,
        lastTick = nil,
        stacks = 1,
        data = {},
        children = nil,
        parent = nil,
        onComplete = nil,
        onTick = nil
    }
end

function EffectComposer:_shouldTrigger(config: EffectConfig, caster: Instance, target: Instance?, context: {[string]: any}?): boolean
    -- Check chance
    if config.chance and config.chance < 1 then
        if math.random() > config.chance then
            return false
        end
    end
    
    -- Check condition
    if config.condition then
        local success, result = pcall(config.condition, caster, target)
        if not success or not result then
            return false
        end
    end
    
    return true
end

function EffectComposer:_calculateValue(value: number | ScalableValue | Types.ValueRange | nil, stats: {[string]: number}?): number
    if not value then
        return 0
    end
    
    if type(value) == "number" then
        return value
    elseif type(value) == "table" then
        if value.base then
            -- ScalableValue
            local result = value.base
            if value.scaling and stats then
                for stat, multiplier in pairs(value.scaling) do
                    if stats[stat] then
                        result = result + stats[stat] * multiplier
                    end
                end
            end
            return result
        elseif value.min and value.max then
            -- ValueRange
            return math.random(value.min, value.max)
        end
    end
    
    return 0
end

function EffectComposer:_getPosition(instance: Instance): Vector3?
    if instance:IsA("BasePart") then
        return instance.Position
    elseif instance:IsA("Model") then
        local primaryPart = instance.PrimaryPart or instance:FindFirstChild("HumanoidRootPart")
        if primaryPart then
            return primaryPart.Position
        end
    elseif instance:IsA("Humanoid") then
        local rootPart = instance.RootPart
        if rootPart then
            return rootPart.Position
        end
    end
    return nil
end

function EffectComposer:_getDirection(directionType: string, caster: Instance, target: Instance?): Vector3
    local casterPos = self:_getPosition(caster)
    if not casterPos then
        return Vector3.new(0, 0, 1)
    end
    
    if directionType == "ToTarget" and target then
        local targetPos = self:_getPosition(target)
        if targetPos then
            return (targetPos - casterPos).Unit
        end
    elseif directionType == "FromTarget" and target then
        local targetPos = self:_getPosition(target)
        if targetPos then
            return (casterPos - targetPos).Unit
        end
    elseif directionType == "Backward" then
        -- Get look direction and reverse
        if caster:IsA("Model") then
            local rootPart = caster:FindFirstChild("HumanoidRootPart")
            if rootPart then
                return -rootPart.CFrame.LookVector
            end
        end
    elseif directionType == "Random" then
        return Vector3.new(
            math.random() * 2 - 1,
            0,
            math.random() * 2 - 1
        ).Unit
    end
    
    -- Default to forward
    if caster:IsA("Model") then
        local rootPart = caster:FindFirstChild("HumanoidRootPart")
        if rootPart then
            return rootPart.CFrame.LookVector
        end
    end
    
    return Vector3.new(0, 0, 1)
end

function EffectComposer:_getTargetsInArea(position: Vector3, radius: number, filter: Types.TargetFilter?): {Instance}
    local targets = {}
    
    -- Find all characters in range
    for _, character in ipairs(workspace:GetDescendants()) do
        if character:IsA("Model") and character:FindFirstChild("Humanoid") then
            local charPos = self:_getPosition(character)
            if charPos and (charPos - position).Magnitude <= radius then
                if self:_passesFilter(character, filter) then
                    table.insert(targets, character)
                end
            end
        end
    end
    
    return targets
end

function EffectComposer:_passesFilter(target: Instance, filter: Types.TargetFilter?): boolean
    if not filter then
        return true
    end
    
    -- Check team
    if filter.team and filter.team ~= "All" then
        -- Implementation depends on team system
    end
    
    -- Check type
    if filter.type and filter.type ~= "All" then
        if filter.type == "Player" then
            if not game.Players:GetPlayerFromCharacter(target) then
                return false
            end
        elseif filter.type == "NPC" then
            if game.Players:GetPlayerFromCharacter(target) then
                return false
            end
        end
    end
    
    -- Check status
    if filter.status and filter.status ~= "All" then
        local humanoid = target:FindFirstChild("Humanoid")
        if humanoid then
            if filter.status == "Alive" and humanoid.Health <= 0 then
                return false
            elseif filter.status == "Dead" and humanoid.Health > 0 then
                return false
            end
        end
    end
    
    -- Check custom filter
    if filter.custom then
        local success, result = pcall(filter.custom, target)
        if not success or not result then
            return false
        end
    end
    
    return true
end

function EffectComposer:_createProjectile(model: string?): Part?
    -- Server should not create visual projectiles
    -- This function is deprecated - visual effects handled by client
    return nil
end

function EffectComposer:_trackEffect(effect: ActiveEffect)
    -- Track by target
    if effect.target then
        if not self.activeEffects[effect.target] then
            self.activeEffects[effect.target] = {}
        end
        table.insert(self.activeEffects[effect.target], effect)
    end
    
    -- Track by type
    local effectType = effect.config.type
    if not self.effectsByType[effectType] then
        self.effectsByType[effectType] = {}
    end
    table.insert(self.effectsByType[effectType], effect)
end

function EffectComposer:_untrackEffect(effect: ActiveEffect)
    -- Remove from target tracking
    if effect.target and self.activeEffects[effect.target] then
        local index = table.find(self.activeEffects[effect.target], effect)
        if index then
            table.remove(self.activeEffects[effect.target], index)
        end
    end
    
    -- Remove from type tracking
    local effectType = effect.config.type
    if self.effectsByType[effectType] then
        local index = table.find(self.effectsByType[effectType], effect)
        if index then
            table.remove(self.effectsByType[effectType], index)
        end
    end
    
    -- Remove from periodic effects
    local index = table.find(self.periodicEffects, effect)
    if index then
        table.remove(self.periodicEffects, index)
    end
end

function EffectComposer:_returnToPool(effect: ActiveEffect)
    -- Object pooling for performance
    local effectType = effect.config.type
    
    if not self.effectPools[effectType] then
        self.effectPools[effectType] = {}
    end
    
    -- Clear effect data
    table.clear(effect.data)
    effect.children = nil
    effect.parent = nil
    effect.onComplete = nil
    effect.onTick = nil
    
    -- Add to pool
    table.insert(self.effectPools[effectType], effect)
    
    self.stats.pooledEffectCount = self.stats.pooledEffectCount + 1
end

function EffectComposer:_startUpdateLoop()
    RunService.Heartbeat:Connect(function(deltaTime)
        local now = os.clock()
        
        -- Update periodic effects
        for i = #self.periodicEffects, 1, -1 do
            local effect = self.periodicEffects[i]
            
            if effect.lastTick and effect.tickRate then
                local timeSinceLastTick = now - effect.lastTick
                
                if timeSinceLastTick >= effect.tickRate then
                    effect.lastTick = now
                    
                    -- Execute periodic trigger effects
                    if effect.config.effects then
                        for _, childConfig in ipairs(effect.config.effects) do
                            if childConfig.trigger == "Periodic" then
                                self:executeEffect(childConfig, effect.caster, effect.target, effect.data)
                            end
                        end
                    end
                    
                    -- Call tick callback
                    if effect.onTick then
                        effect.onTick(effect)
                    end
                end
            end
        end
    end)
end

-- Service references (implement based on your service architecture)

function EffectComposer:_getModifierSystem()
    -- Return reference to modifier system
    return nil -- Placeholder
end

-- Public API

function EffectComposer:getActiveEffects(target: Instance): {ActiveEffect}
    return self.activeEffects[target] or {}
end

function EffectComposer:getActiveEffectsByType(effectType: EffectType): {ActiveEffect}
    return self.effectsByType[effectType] or {}
end

function EffectComposer:removeAllEffects(target: Instance)
    local effects = self:getActiveEffects(target)
    for _, effect in ipairs(effects) do
        self:completeEffect(effect)
    end
end

function EffectComposer:getStats(): {[string]: number}
    return self.stats
end

-- Singleton
local composer = nil

function EffectComposer.get()
    if not composer then
        composer = EffectComposer.new()
    end
    return composer
end

return EffectComposer