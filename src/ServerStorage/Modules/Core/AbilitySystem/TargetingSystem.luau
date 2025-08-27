--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Types = require(script.Parent.Types)

type TargetingConfig = Types.TargetingConfig
type TargetFilter = Types.TargetFilter
type TargetingType = Types.TargetingType

-- Targeting System: Handles target acquisition and validation for abilities
export type TargetingSystem = {
    targetingStrategies: {[TargetingType]: TargetingStrategy},
    validationCache: {[string]: ValidationResult},
    cacheExpiry: number,
    lineOfSightParams: RaycastParams,
    stats: {
        totalTargetingAttempts: number,
        successfulTargetings: number,
        failedTargetings: number,
        cacheHits: number,
        cacheMisses: number
    },
    config: {
        maxTargetDistance: number,
        defaultTargetPriority: string,
        includeInvisible: boolean,
        includeInvulnerable: boolean,
        smartTargeting: boolean
    },
    currentInputData: {[string]: any}?,
    [string]: any
}

local TargetingSystem = {} :: TargetingSystem & {__index: TargetingSystem}
TargetingSystem.__index = TargetingSystem

function TargetingSystem.new(): TargetingSystem
    local self = setmetatable({} :: TargetingSystem, TargetingSystem)
    
    -- Targeting configurations
    self.targetingStrategies = {} :: {[TargetingType]: TargetingStrategy}
    
    -- Target validation cache
    self.validationCache = {} :: {[string]: ValidationResult}
    self.cacheExpiry = 0.1 -- Cache expires after 0.1 seconds
    
    -- Line of sight settings
    self.lineOfSightParams = RaycastParams.new()
    self.lineOfSightParams.FilterType = Enum.RaycastFilterType.Exclude
    self.lineOfSightParams.IgnoreWater = true
    
    -- Statistics
    self.stats = {
        totalTargetingAttempts = 0,
        successfulTargetings = 0,
        failedTargetings = 0,
        cacheHits = 0,
        cacheMisses = 0
    }
    
    -- Configuration
    self.config = {
        maxTargetDistance = 1000,
        defaultTargetPriority = "Closest",
        includeInvisible = false,
        includeInvulnerable = false,
        smartTargeting = true -- AI-assisted targeting
    }
    
    -- Initialize
    self:_registerTargetingStrategies()
    self:_setupCacheCleanup()
    
    return self
end

type TargetingStrategy = {
    id: TargetingType,
    acquireTargets: (self: TargetingSystem, caster: Instance, config: TargetingConfig) -> {Instance},
    validateTarget: (self: TargetingSystem, caster: Instance, target: Instance, config: TargetingConfig) -> (boolean, string?),
    getPriority: (self: TargetingSystem, caster: Instance, target: Instance) -> number,
    getIndicator: (config: TargetingConfig) -> Instance?
}

type ValidationResult = {
    isValid: boolean,
    reason: string?,
    timestamp: number
}

type TargetScore = {
    target: Instance,
    score: number,
    distance: number,
    angle: number,
    health: number,
    threat: number
}

-- Core targeting functions

function TargetingSystem:acquireTargets(
    caster: Instance,
    config: TargetingConfig,
    inputData: {[string]: any}?
): {Instance}
    
    self.stats.totalTargetingAttempts = self.stats.totalTargetingAttempts + 1
    
    -- Get targeting strategy
    local strategy = self.targetingStrategies[config.type]
    if not strategy then
        warn(`[TargetingSystem] Unknown targeting type: {config.type}`)
        self.stats.failedTargetings = self.stats.failedTargetings + 1
        return {}
    end
    
    -- Store input data for strategies to use
    self.currentInputData = inputData
    
    -- Acquire targets using strategy
    local targets = strategy.acquireTargets(self, caster, config)
    
    -- Apply filters
    targets = self:_filterTargets(targets, caster, config)
    
    -- Apply max targets limit
    if config.maxTargets and #targets > config.maxTargets then
        targets = self:_selectBestTargets(targets, caster, config.maxTargets)
    end
    
    if #targets > 0 then
        self.stats.successfulTargetings = self.stats.successfulTargetings + 1
    else
        self.stats.failedTargetings = self.stats.failedTargetings + 1
    end
    
    return targets
end

function TargetingSystem:validateTarget(
    caster: Instance,
    target: Instance?,
    config: TargetingConfig
): (boolean, string?)
    
    -- Check cache (only if target exists)
    local cacheKey
    if target then
        cacheKey = `{tostring(caster)}_{tostring(target)}_{config.type}`
    else
        cacheKey = `{tostring(caster)}_nil_{config.type}`
    end
    local cached = self.validationCache[cacheKey]
    
    if cached and (os.clock() - cached.timestamp) < self.cacheExpiry then
        self.stats.cacheHits = self.stats.cacheHits + 1
        return cached.isValid, cached.reason
    end
    
    self.stats.cacheMisses = self.stats.cacheMisses + 1
    
    -- Basic validation
    if not target or not target.Parent then
        return false, "Invalid target"
    end
    
    -- Check distance
    if config.range then
        local distance = self:_getDistance(caster, target)
        if distance > config.range then
            self:_cacheValidation(cacheKey, false, "Out of range")
            return false, "Out of range"
        end
    end
    
    -- Check line of sight
    if config.requireLineOfSight then
        if not self:_hasLineOfSight(caster, target) then
            self:_cacheValidation(cacheKey, false, "No line of sight")
            return false, "No line of sight"
        end
    end
    
    -- Check filter
    if config.filter then
        if not self:_passesFilter(target, config.filter, caster) then
            self:_cacheValidation(cacheKey, false, "Failed filter")
            return false, "Failed filter"
        end
    end
    
    -- Strategy-specific validation
    local strategy = self.targetingStrategies[config.type]
    if strategy and strategy.validateTarget then
        local isValid, reason = strategy.validateTarget(self, caster, target, config)
        self:_cacheValidation(cacheKey, isValid, reason)
        return isValid, reason
    end
    
    self:_cacheValidation(cacheKey, true, nil)
    return true
end

-- Targeting strategies

function TargetingSystem:_registerTargetingStrategies()
    -- Self targeting
    self.targetingStrategies.Self = {
        id = "Self",
        acquireTargets = function(self, caster, config)
            return {caster}
        end,
        validateTarget = function(self, caster, target, config)
            return target == caster, "Must target self"
        end,
        getPriority = function(self, caster, target)
            return 100
        end
    }
    
    -- Targeted (single target)
    self.targetingStrategies.Targeted = {
        id = "Targeted",
        acquireTargets = function(self, caster, config)
            local inputData = self.currentInputData
            if inputData and inputData.target then
                return {inputData.target}
            end
            
            -- Fallback to nearest valid target
            local allTargets = self:_getAllPotentialTargets(caster, config)
            if #allTargets > 0 then
                return {allTargets[1]}
            end
            
            return {}
        end,
        validateTarget = function(self, caster, target, config)
            return true
        end,
        getPriority = function(self, caster, target)
            return 50
        end
    }
    
    -- Aimed (direction-based)
    self.targetingStrategies.Aimed = {
        id = "Aimed",
        acquireTargets = function(self, caster, config)
            local inputData = self.currentInputData
            -- Cast ray or cone in direction
            return {inputData.target}
        end,
        validateTarget = function(self, caster, target, config)
            return true
        end,
        getPriority = function(self, caster, target)
            return 40
        end
    }
    
    -- Area (radius around point)
    self.targetingStrategies.Area = {
        id = "Area",
        acquireTargets = function(self, caster, config)
            local inputData = self.currentInputData
            local position = inputData and inputData.position
            
            if not position then
                position = self:_getPosition(caster)
            end
            
            return self:_getTargetsInRadius(position, config.radius or 10, config)
        end,
        validateTarget = function(self, caster, target, config)
            return true
        end,
        getPriority = function(self, caster, target)
            return 30
        end
    }
    
    -- Cone (cone in front of caster)
    self.targetingStrategies.Cone = {
        id = "Cone",
        acquireTargets = function(self, caster, config)
            local position = self:_getPosition(caster)
            local direction = self:_getLookDirection(caster)
            local angle = config.angle or 45
            local range = config.range or 20
            
            return self:_getTargetsInCone(position, direction, angle, range, config)
        end,
        validateTarget = function(self, caster, target, config)
            return true
        end,
        getPriority = function(self, caster, target)
            return 35
        end
    }
    
    -- Line (line from caster)
    self.targetingStrategies.Line = {
        id = "Line",
        acquireTargets = function(self, caster, config)
            local position = self:_getPosition(caster)
            local direction = self:_getLookDirection(caster)
            local length = config.range or 30
            local width = config.width or 5
            
            return self:_getTargetsInLine(position, direction, length, width, config)
        end,
        validateTarget = function(self, caster, target, config)
            return true
        end,
        getPriority = function(self, caster, target)
            return 35
        end
    }
    
    -- Chain (bouncing between targets)
    self.targetingStrategies.Chain = {
        id = "Chain",
        acquireTargets = function(self, caster, config)
            local inputData = self.currentInputData
            local firstTarget = inputData and inputData.target
            
            if not firstTarget then
                -- Get nearest target as first
                local allTargets = self:_getAllPotentialTargets(caster, config)
                if #allTargets > 0 then
                    firstTarget = allTargets[1]
                else
                    return {}
                end
            end
            
            return self:_getChainTargets(firstTarget, config)
        end,
        validateTarget = function(self, caster, target, config)
            return true
        end,
        getPriority = function(self, caster, target)
            return 45
        end
    }
    
    -- Random
    self.targetingStrategies.Random = {
        id = "Random",
        acquireTargets = function(self, caster, config)
            local allTargets = self:_getAllPotentialTargets(caster, config)
            
            if #allTargets == 0 then
                return {}
            end
            
            local count = config.maxTargets or 1
            local selected = {}
            
            for i = 1, math.min(count, #allTargets) do
                local index = math.random(1, #allTargets)
                table.insert(selected, allTargets[index])
                table.remove(allTargets, index)
            end
            
            return selected
        end,
        validateTarget = function(self, caster, target, config)
            return true
        end,
        getPriority = function(self, caster, target)
            return 10
        end
    }
    
    -- All (all valid targets)
    self.targetingStrategies.All = {
        id = "All",
        acquireTargets = function(self, caster, config)
            return self:_getAllPotentialTargets(caster, config)
        end,
        validateTarget = function(self, caster, target, config)
            return true
        end,
        getPriority = function(self, caster, target)
            return 20
        end
    }
end

-- Target acquisition helpers

function TargetingSystem:_getAllPotentialTargets(caster: Instance, config: TargetingConfig): {Instance}
    local targets = {}
    local casterPos = self:_getPosition(caster)
    
    if not casterPos then
        return targets
    end
    
    -- Find all characters in range
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj:FindFirstChild("Humanoid") then
            local humanoid = obj:FindFirstChild("Humanoid")
            
            -- Skip dead targets unless filter allows
            if humanoid.Health <= 0 and (not config.filter or config.filter.status ~= "Dead") then
                continue
            end
            
            -- Check distance
            local targetPos = self:_getPosition(obj)
            if targetPos then
                local distance = (targetPos - casterPos).Magnitude
                
                if config.range and distance > config.range then
                    continue
                end
                
                -- Check filter
                if config.filter and not self:_passesFilter(obj, config.filter, caster) then
                    continue
                end
                
                table.insert(targets, obj)
            end
        end
    end
    
    -- Sort by distance
    table.sort(targets, function(a, b)
        local distA = self:_getDistance(caster, a)
        local distB = self:_getDistance(caster, b)
        return distA < distB
    end)
    
    return targets
end

function TargetingSystem:_getTargetsInRadius(center: Vector3, radius: number, config: TargetingConfig): {Instance}
    local targets = {}
    
    local region = Region3.new(center - Vector3.new(radius, radius, radius), center + Vector3.new(radius, radius, radius))
    region = region:ExpandToGrid(4)
    
    local parts = workspace:FindPartsInRegion3(region, nil, math.huge)
    local processedModels = {}
    
    for _, part in ipairs(parts) do
        local model = part:FindFirstAncestorOfClass("Model")
        
        if model and not processedModels[model] and model:FindFirstChild("Humanoid") then
            processedModels[model] = true
            
            local distance = self:_getDistanceFromPoint(center, model)
            if distance <= radius then
                if not config.filter or self:_passesFilter(model, config.filter) then
                    table.insert(targets, model)
                end
            end
        end
    end
    
    return targets
end

function TargetingSystem:_getTargetsInCone(
    origin: Vector3,
    direction: Vector3,
    angle: number,
    range: number,
    config: TargetingConfig
): {Instance}
    
    local targets = {}
    local halfAngle = math.rad(angle / 2)
    
    -- Get all potential targets in range
    local potentialTargets = self:_getTargetsInRadius(origin, range, config)
    
    for _, target in ipairs(potentialTargets) do
        local targetPos = self:_getPosition(target)
        if targetPos then
            local toTarget = (targetPos - origin).Unit
            local dotProduct = direction:Dot(toTarget)
            local targetAngle = math.acos(math.clamp(dotProduct, -1, 1))
            
            if targetAngle <= halfAngle then
                table.insert(targets, target)
            end
        end
    end
    
    return targets
end

function TargetingSystem:_getTargetsInLine(
    origin: Vector3,
    direction: Vector3,
    length: number,
    width: number,
    config: TargetingConfig
): {Instance}
    
    local targets = {}
    local _endPoint = origin + direction * length
    
    -- Get all potential targets
    local potentialTargets = self:_getTargetsInRadius(origin, length, config)
    
    for _, target in ipairs(potentialTargets) do
        local targetPos = self:_getPosition(target)
        if targetPos then
            -- Calculate distance from point to line
            local toTarget = targetPos - origin
            local lineProjection = toTarget:Dot(direction)
            
            if lineProjection >= 0 and lineProjection <= length then
                local closestPoint = origin + direction * lineProjection
                local distanceToLine = (targetPos - closestPoint).Magnitude
                
                if distanceToLine <= width / 2 then
                    table.insert(targets, target)
                end
            end
        end
    end
    
    return targets
end

function TargetingSystem:_getTargetsInDirection(
    caster: Instance,
    direction: Vector3,
    config: TargetingConfig
): {Instance}
    
    local origin = self:_getPosition(caster)
    if not origin then
        return {}
    end
    
    local range = config.range or 50
    local rayResult = workspace:Raycast(origin, direction * range, self.lineOfSightParams)
    
    if rayResult and rayResult.Instance then
        local model = rayResult.Instance:FindFirstAncestorOfClass("Model")
        if model and model:FindFirstChild("Humanoid") then
            if not config.filter or self:_passesFilter(model, config.filter, caster) then
                return {model}
            end
        end
    end
    
    return {}
end

function TargetingSystem:_getChainTargets(firstTarget: Instance, config: TargetingConfig): {Instance}
    local targets = {firstTarget}
    local lastTarget = firstTarget
    local bounces = config.bounces or 3
    local bounceRange = config.radius or 15
    
    for i = 1, bounces do
        local lastPos = self:_getPosition(lastTarget)
        if not lastPos then
            break
        end
        
        -- Find next target
        local nearbyTargets = self:_getTargetsInRadius(lastPos, bounceRange, config)
        local nextTarget = nil
        
        for _, target in ipairs(nearbyTargets) do
            -- Don't chain back to previous targets
            if not table.find(targets, target) then
                nextTarget = target
                break
            end
        end
        
        if not nextTarget then
            break
        end
        
        table.insert(targets, nextTarget)
        lastTarget = nextTarget
    end
    
    return targets
end

-- Target filtering

function TargetingSystem:_filterTargets(
    targets: {Instance},
    caster: Instance,
    config: TargetingConfig
): {Instance}
    
    local filtered = {}
    
    for _, target in ipairs(targets) do
        local isValid, _ = self:validateTarget(caster, target, config)
        if isValid then
            table.insert(filtered, target)
        end
    end
    
    return filtered
end

function TargetingSystem:_passesFilter(target: Instance, filter: TargetFilter, caster: Instance?): boolean
    -- Check team
    if filter.team and filter.team ~= "All" then
        local targetTeam = self:_getTeam(target)
        local casterTeam = caster and self:_getTeam(caster)
        
        if filter.team == "Ally" then
            if targetTeam ~= casterTeam then
                return false
            end
        elseif filter.team == "Enemy" then
            if targetTeam == casterTeam then
                return false
            end
        elseif filter.team == "Neutral" then
            if targetTeam ~= nil then
                return false
            end
        end
    end
    
    -- Check type
    if filter.type and filter.type ~= "All" then
        if filter.type == "Player" then
            if not Players:GetPlayerFromCharacter(target) then
                return false
            end
        elseif filter.type == "NPC" then
            if Players:GetPlayerFromCharacter(target) then
                return false
            end
        elseif filter.type == "Object" then
            if target:FindFirstChild("Humanoid") then
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
    
    -- Check effects
    if filter.hasEffect then
        if not self:_hasEffect(target, filter.hasEffect) then
            return false
        end
    end
    
    if filter.notHasEffect then
        if self:_hasEffect(target, filter.notHasEffect) then
            return false
        end
    end
    
    -- Check health percent
    if filter.healthPercent then
        local humanoid = target:FindFirstChild("Humanoid")
        if humanoid then
            local healthPercent = humanoid.Health / humanoid.MaxHealth
            
            if filter.healthPercent.min and healthPercent < filter.healthPercent.min then
                return false
            end
            
            if filter.healthPercent.max and healthPercent > filter.healthPercent.max then
                return false
            end
        end
    end
    
    -- Custom filter
    if filter.custom then
        local success, result = pcall(filter.custom, target)
        if not success or not result then
            return false
        end
    end
    
    return true
end

-- Smart targeting

function TargetingSystem:_selectBestTargets(targets: {Instance}, caster: Instance, count: number): {Instance}
    if not self.config.smartTargeting then
        -- Just take first N targets
        local selected = {}
        for i = 1, math.min(count, #targets) do
            table.insert(selected, targets[i])
        end
        return selected
    end
    
    -- Score each target
    local scores = {}
    
    for _, target in ipairs(targets) do
        local score = self:_scoreTarget(caster, target)
        table.insert(scores, {
            target = target,
            score = score
        })
    end
    
    -- Sort by score
    table.sort(scores, function(a, b)
        return a.score > b.score
    end)
    
    -- Select top N
    local selected = {}
    for i = 1, math.min(count, #scores) do
        table.insert(selected, scores[i].target)
    end
    
    return selected
end

function TargetingSystem:_scoreTarget(caster: Instance, target: Instance): number
    local score = 0
    
    -- Distance score (closer = better)
    local distance = self:_getDistance(caster, target)
    score = score + (100 - math.min(distance, 100))
    
    -- Health score (lower health = higher priority)
    local humanoid = target:FindFirstChild("Humanoid")
    if humanoid then
        local healthPercent = humanoid.Health / humanoid.MaxHealth
        score = score + (1 - healthPercent) * 50
    end
    
    -- Threat score (based on target's damage potential)
    -- This would require integration with combat system
    
    -- Player vs NPC (players are higher priority)
    if Players:GetPlayerFromCharacter(target) then
        score = score + 25
    end
    
    -- Debuff score (debuffed enemies are higher priority)
    -- This would require integration with effect system
    
    return score
end

-- Utility functions

function TargetingSystem:_getPosition(instance: Instance): Vector3?
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

function TargetingSystem:_getDistance(from: Instance, to: Instance): number
    local fromPos = self:_getPosition(from)
    local toPos = self:_getPosition(to)
    
    if fromPos and toPos then
        return (toPos - fromPos).Magnitude
    end
    
    return math.huge
end

function TargetingSystem:_getDistanceFromPoint(point: Vector3, target: Instance): number
    local targetPos = self:_getPosition(target)
    
    if targetPos then
        return (targetPos - point).Magnitude
    end
    
    return math.huge
end

function TargetingSystem:_getLookDirection(instance: Instance): Vector3
    if instance:IsA("Model") then
        local rootPart = instance:FindFirstChild("HumanoidRootPart")
        if rootPart and rootPart:IsA("BasePart") then
            return rootPart.CFrame.LookVector
        end
    end
    
    return Vector3.new(0, 0, -1)
end

function TargetingSystem:_hasLineOfSight(from: Instance, to: Instance): boolean
    local fromPos = self:_getPosition(from)
    local toPos = self:_getPosition(to)
    
    if not fromPos or not toPos then
        return false
    end
    
    -- Setup raycast params
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {from, to}
    
    local result = workspace:Raycast(fromPos, toPos - fromPos, params)
    
    -- If no hit or hit the target, we have line of sight
    return result == nil or result.Instance:IsDescendantOf(to)
end

function TargetingSystem:_getTeam(instance: Instance): string?
    -- Check for Team attribute
    local team = instance:GetAttribute("Team")
    if team then
        return tostring(team)
    end
    
    -- Check for player team
    local player = Players:GetPlayerFromCharacter(instance)
    if player and player.Team then
        return player.Team.Name
    end
    
    -- Check for team value
    local teamValue = instance:FindFirstChild("Team")
    if teamValue and teamValue:IsA("StringValue") then
        return teamValue.Value
    end
    
    return nil
end

function TargetingSystem:_hasEffect(target: Instance, effectName: string): boolean
    -- Check for effect component
    local effectComponent = target:FindFirstChild("EffectComponent")
    if effectComponent then
        -- This would integrate with the effect system
        return false
    end
    
    -- Check for effect folder
    local effects = target:FindFirstChild("Effects")
    if effects then
        return effects:FindFirstChild(effectName) ~= nil
    end
    
    return false
end

function TargetingSystem:_cacheValidation(key: string, isValid: boolean, reason: string?)
    self.validationCache[key] = {
        isValid = isValid,
        reason = reason,
        timestamp = os.clock()
    }
end

function TargetingSystem:_setupCacheCleanup()
    RunService.Heartbeat:Connect(function()
        local now = os.clock()
        local toRemove = {}
        
        for key, result in pairs(self.validationCache) do
            if now - result.timestamp > self.cacheExpiry * 10 then
                table.insert(toRemove, key)
            end
        end
        
        for _, key in ipairs(toRemove) do
            self.validationCache[key] = nil
        end
    end)
end

-- Target indicators

function TargetingSystem:createTargetIndicator(config: TargetingConfig): Instance?
    local indicator = nil
    
    if config.type == "Area" then
        indicator = self:_createAreaIndicator(config.radius or 10)
    elseif config.type == "Cone" then
        indicator = self:_createConeIndicator(config.angle or 45, config.range or 20)
    elseif config.type == "Line" then
        indicator = self:_createLineIndicator(config.range or 30, config.width or 5)
    end
    
    return indicator
end

function TargetingSystem:_createAreaIndicator(radius: number): Part
    local indicator = Instance.new("Part")
    indicator.Name = "AreaIndicator"
    indicator.Shape = Enum.PartType.Cylinder
    indicator.Size = Vector3.new(0.5, radius * 2, radius * 2)
    indicator.Transparency = 0.7
    indicator.BrickColor = BrickColor.new("Bright red")
    indicator.CanCollide = false
    indicator.Anchored = true
    
    return indicator
end

function TargetingSystem:_createConeIndicator(angle: number, range: number): Model
    local model = Instance.new("Model")
    model.Name = "ConeIndicator"
    
    -- Create wedge parts to form cone
    -- Implementation would create visual cone
    
    return model
end

function TargetingSystem:_createLineIndicator(length: number, width: number): Part
    local indicator = Instance.new("Part")
    indicator.Name = "LineIndicator"
    indicator.Size = Vector3.new(width, 0.5, length)
    indicator.Transparency = 0.7
    indicator.BrickColor = BrickColor.new("Bright red")
    indicator.CanCollide = false
    indicator.Anchored = true
    
    return indicator
end

-- Public API

function TargetingSystem:getStats(): {[string]: number}
    return self.stats
end

function TargetingSystem:clearCache()
    self.validationCache = {}
end

-- Singleton
local system = nil

function TargetingSystem.get()
    if not system then
        system = TargetingSystem.new()
    end
    return system
end

return TargetingSystem