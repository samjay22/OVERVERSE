--!nonstrict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Types = require(script.Parent.Types)

-- Performance optimizations - cache frequently used functions
local mathFloor = math.floor

-- Targeting System: Handles target acquisition and validation for abilities
local TargetingSystem = {}
TargetingSystem.__index = TargetingSystem

function TargetingSystem.new()
    local self = setmetatable({}, TargetingSystem)
    
    -- Targeting configurations
    self.targetingStrategies = {}
    
    -- Target validation cache
    self.validationCache = {}
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
    
    -- Initialize spatial indexing properties
    self._spatialGrid = nil
    self._targetCache = nil
    self._lastCacheUpdate = 0
    self._cacheTimeout = 0.5 -- Cache timeout in seconds
    self._gridSize = 50 -- Grid cell size
    
    -- Initialize
    self:_registerTargetingStrategies()
    self:_setupCacheCleanup()
    
    return self
end

-- Core targeting functions

function TargetingSystem:acquireTargets(caster, config, inputData)
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

function TargetingSystem:validateTarget(caster, target, config)
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
            local position = self:_getPosition(caster)
            local direction = inputData and inputData.direction or self:_getLookDirection(caster)
            local range = config.range or 50

            local targets = {}

            -- Cast ray in direction to find targets
            local rayOrigin = position
            local rayDirection = direction * range

            -- Create raycast params
            local raycastParams = RaycastParams.new()
            raycastParams.FilterDescendantsInstances = {caster}
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude

            local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

            if rayResult then
                local hitModel = rayResult.Instance:FindFirstAncestorWhichIsA("Model")
                if hitModel and hitModel:FindFirstChildWhichIsA("Humanoid") then
                    table.insert(targets, hitModel)
                end
            end

            return targets
        end,
        validateTarget = function(self, caster, target, config)
            local casterPos = self:_getPosition(caster)
            local targetPos = self:_getPosition(target)
            if not casterPos or not targetPos then
                return false
            end

            local distance = (targetPos - casterPos).Magnitude
            local maxRange = config.range or 50

            return distance <= maxRange
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
end

-- Helper methods

function TargetingSystem:_filterTargets(targets, caster, config)
    local filtered = {}

    for _, target in ipairs(targets) do
        local isValid, _ = self:validateTarget(caster, target, config)
        if isValid then
            table.insert(filtered, target)
        end
    end

    return filtered
end

function TargetingSystem:_selectBestTargets(targets, caster, count)
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

function TargetingSystem:_scoreTarget(caster, target)
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

    -- Player vs NPC (players are higher priority)
    if Players:GetPlayerFromCharacter(target) then
        score = score + 25
    end

    return score
end

function TargetingSystem:_getAllPotentialTargets(caster, config)
    local maxRange = config.range or 100
    local casterPos = self:_getPosition(caster)
    if not casterPos then return {} end

    local potentialTargets = self:_getSpatialTargets(casterPos, maxRange)
    local targets = {}

    for _, target in ipairs(potentialTargets) do
        if target ~= caster then
            if not config.filter or self:_passesFilter(target, config.filter, caster) then
                table.insert(targets, target)
            end
        end
    end

    return targets
end

function TargetingSystem:_getTargetsInRadius(center, radius, config)
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

-- Utility functions

function TargetingSystem:_getPosition(instance)
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

function TargetingSystem:_getDistance(from, to)
    local fromPos = self:_getPosition(from)
    local toPos = self:_getPosition(to)

    if fromPos and toPos then
        return (toPos - fromPos).Magnitude
    end

    return math.huge
end

function TargetingSystem:_getDistanceFromPoint(point, target)
    local targetPos = self:_getPosition(target)

    if targetPos then
        return (targetPos - point).Magnitude
    end

    return math.huge
end

function TargetingSystem:_getLookDirection(instance)
    if instance:IsA("Model") then
        local rootPart = instance:FindFirstChild("HumanoidRootPart")
        if rootPart and rootPart:IsA("BasePart") then
            return rootPart.CFrame.LookVector
        end
    end

    return Vector3.new(0, 0, -1)
end

function TargetingSystem:_hasLineOfSight(from, to)
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

function TargetingSystem:_passesFilter(target, filter, caster)
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

    return true
end

function TargetingSystem:_getTeam(instance)
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

function TargetingSystem:_cacheValidation(key, isValid, reason)
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

-- Spatial indexing for performance (with proper nil checks)

function TargetingSystem:_getSpatialTargets(position, range)
    local currentTime = os.clock()

    -- Initialize properties if not set
    if not self._lastCacheUpdate then
        self._lastCacheUpdate = 0
    end
    if not self._cacheTimeout then
        self._cacheTimeout = 0.5
    end

    -- Check cache first
    local cacheKey = `{mathFloor(position.X/10)}_{mathFloor(position.Y/10)}_{mathFloor(position.Z/10)}_{range}`
    if self._targetCache and self._targetCache[cacheKey] and (currentTime - self._lastCacheUpdate) < self._cacheTimeout then
        return self._targetCache[cacheKey]
    end

    -- Build spatial grid if needed
    if not self._spatialGrid or (currentTime - self._lastCacheUpdate) > self._cacheTimeout then
        self:_buildSpatialGrid()
        self._lastCacheUpdate = currentTime
    end

    -- Get targets from spatial grid
    local targets = {}
    local gridX = mathFloor(position.X / self._gridSize)
    local gridY = mathFloor(position.Y / self._gridSize)
    local gridZ = mathFloor(position.Z / self._gridSize)
    local gridRange = math.ceil(range / self._gridSize)

    for x = gridX - gridRange, gridX + gridRange do
        for y = gridY - gridRange, gridY + gridRange do
            for z = gridZ - gridRange, gridZ + gridRange do
                local gridKey = `{x}_{y}_{z}`
                local gridTargets = self._spatialGrid and self._spatialGrid[gridKey]

                if gridTargets then
                    for _, target in ipairs(gridTargets) do
                        local targetPos = self:_getPosition(target)
                        if targetPos and (targetPos - position).Magnitude <= range then
                            table.insert(targets, target)
                        end
                    end
                end
            end
        end
    end

    -- Cache result
    if not self._targetCache then
        self._targetCache = {}
    end
    self._targetCache[cacheKey] = targets

    return targets
end

function TargetingSystem:_buildSpatialGrid()
    self._spatialGrid = {}

    -- Get all characters in workspace
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child:FindFirstChild("Humanoid") then
            local position = self:_getPosition(child)
            if position then
                local gridX = mathFloor(position.X / self._gridSize)
                local gridY = mathFloor(position.Y / self._gridSize)
                local gridZ = mathFloor(position.Z / self._gridSize)
                local gridKey = `{gridX}_{gridY}_{gridZ}`

                if not self._spatialGrid[gridKey] then
                    self._spatialGrid[gridKey] = {}
                end

                table.insert(self._spatialGrid[gridKey], child)
            end
        end
    end
end

return TargetingSystem.new()
