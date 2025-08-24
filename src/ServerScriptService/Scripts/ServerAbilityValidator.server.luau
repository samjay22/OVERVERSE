--!strict
-- Server-side ability validation orchestrator

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local _ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local _NetworkServer = require(game.ServerStorage.Modules.Core.NetworkServer)
local AbilityValidationRoot = ServerStorage:WaitForChild("Modules"):WaitForChild("AbilityValidation")
local Utils = require(AbilityValidationRoot:WaitForChild("Utils"))
local AbilityPackageTypes = require(game.ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local Types = require(AbilityValidationRoot:WaitForChild("Types"))
local ServerStateManager = require(AbilityValidationRoot:WaitForChild("State"):WaitForChild("ServerStateManager"))
local AntiCheatValidator = require(AbilityValidationRoot:WaitForChild("AntiCheat"):WaitForChild("AntiCheatValidator"))
local Remotes = require(AbilityValidationRoot:WaitForChild("Network"):WaitForChild("Remotes"))
local CategoryHandler = require(AbilityValidationRoot:WaitForChild("CategoryHandler"))
local CategoryValidator = require(AbilityValidationRoot:WaitForChild("CategoryValidator"))
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

-- Updated to use the new ServerAbilities loader system
local ServerAbilities = require(ReplicatedStorage.Modules.ClientAbilities)

local _ReplicateAbilityRequest : RemoteEvent = _NetworkServer:RegisterRemoteEvent("ReplicateAbilityRequest")

type AbilityId = Types.AbilityId
type StateSnapshot = Types.StateSnapshot
type AbilityResult = Types.AbilityResult
type SharedAbilityContext = Types.SharedAbilityContext
type ServerAbilityModule = AbilityPackageTypes.ServerAbility
type PredictionRequest = Types.PredictionRequest
type ValidationResult = Types.ValidationResult
type EntityRef = AbilityTypes.EntityRef

-- Cache ability modules to avoid repeated GetAbility calls
local abilityModuleCache: {[string]: ServerAbilityModule?} = {}

-- Performance tracking (optional - can be disabled in production)
local ENABLE_PERFORMANCE_TRACKING = true
local performanceStats = {
    totalRequests = 0,
    totalExecutionTime = 0,
    averageExecutionTime = 0
}

local function updatePerformanceStats(executionTime: number)
    if not ENABLE_PERFORMANCE_TRACKING then return end
    
    performanceStats.totalRequests += 1
    performanceStats.totalExecutionTime += executionTime
    performanceStats.averageExecutionTime = performanceStats.totalExecutionTime / performanceStats.totalRequests
    
    -- Log performance every 100 requests
    if performanceStats.totalRequests % 100 == 0 then
        print(`Ability Validator Performance: ${performanceStats.totalRequests} requests, avg: ${math.floor(performanceStats.averageExecutionTime * 1000)}ms`)
    end
end

-- Optimization: Pre-allocated EntityRef templates to reduce table creation overhead
local function createPlayerEntity(player: Player): EntityRef
    return {
        entityType = "Player",
        player = player,
        npcId = nil,
        name = player.Name,
        userId = player.UserId
    }
end

local function createNpcEntity(model: Model): EntityRef
    local playerId = model:FindFirstChild("PlayerId")
    local npcId = (playerId and playerId:IsA("IntValue") and playerId.Value) or -1
    return {
        entityType = "NPC",
        player = nil,
        npcId = model.Name,
        name = model.Name,
        userId = npcId
    }
end

-- Optimized target position resolution
local function getEntityPosition(entity: EntityRef): Vector3?
    if entity.entityType == "Player" and entity.player and entity.player.Character then
        local humanoidRootPart = entity.player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        return humanoidRootPart and humanoidRootPart.Position
    elseif entity.entityType == "NPC" then
        -- Optimized NPC position lookup - direct workspace search
        for _, model in workspace:GetChildren() do
            if model:IsA("Model") and model.Name == entity.name then
                local humanoidRootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
                if humanoidRootPart then
                    return humanoidRootPart.Position
                end
            end
        end
    end
    return nil
end

-- Utility functions for entity handling
local function _getEntityFromPlayerId(playerId: number): EntityRef?
    local player = Players:GetPlayerByUserId(playerId)
    if player then
        return {
            entityType = "Player",
            player = player,
            npcId = nil,
            name = player.Name,
            userId = player.UserId
        }
    end
    
    -- TODO: Add NPC lookup by ID when NPC system is implemented
    -- For now, we can check if it's an NPC by looking in some registry
    -- This would be expanded when we have a proper NPC management system
    
    return nil
end

local function _getEntityUserId(entity: EntityRef): number?
    if entity.entityType == "Player" and entity.player then
        return entity.player.UserId
    elseif entity.entityType == "NPC" then
        return entity.userId
    end
    return nil
end

local function _getPlayerFromEntity(entity: EntityRef): Player?
    if entity.entityType == "Player" then
        return entity.player
    end
    return nil
end

-- Pre-create validation results to reduce table allocations
local function createValidationResult(predictionId: string, success: boolean, reason: string?, correctedState: StateSnapshot?, authorizedEffects: any?): ValidationResult
    return {
        predictionId = predictionId,
        success = success,
        reason = reason,
        correctedState = correctedState,
        authorizedEffects = authorizedEffects,
    }
end

local ServerAbilityValidator = {}
ServerAbilityValidator.__index = ServerAbilityValidator

function ServerAbilityValidator.new()
    local self = setmetatable({}, ServerAbilityValidator)

    self.stateManager = ServerStateManager.new()
    self.antiCheat = AntiCheatValidator.new()

    self.predictionRemote, self.validationRemote = Remotes.init()

    self.predictionRemote.OnServerEvent:Connect(function(player, requestData)
        self:HandlePredictionRequest(player, requestData)
    end)
    
    -- Register reload remote event for R key reload functionality
    self.reloadRemote = _NetworkServer:RegisterRemoteEvent("AbilityReload")
    self.reloadRemote.OnServerEvent:Connect(function(player, reloadData)
        self:HandleReloadRequest(player, reloadData)
    end)

    return self
end

function ServerAbilityValidator:SendValidationResult(player: Player, result: ValidationResult)
    self.validationRemote:FireClient(player, result)
end

-- Cache and validate ability modules using new loader system
function ServerAbilityValidator:GetAbilityModule(abilityId: string): ServerAbilityModule?
    local cached = abilityModuleCache[abilityId]
    if cached ~= nil then
        return cached
    end

    -- Use the new ServerAbilities loader system
    local abilityModule = ServerAbilities.GetAbility(abilityId)
    if not abilityModule then
        abilityModuleCache[abilityId] = nil
        return nil
    end

    -- Validate that it has the required server methods
    if type(abilityModule) == "table" then
        local validModule = abilityModule :: ServerAbilityModule
        abilityModuleCache[abilityId] = validModule
        return validModule
    end

    abilityModuleCache[abilityId] = nil
    return nil
end

-- Get player's target based on targetKey attribute (updated to work with EntityRef)
function ServerAbilityValidator:GetEntityTarget(entity: EntityRef): EntityRef?
    local targetKey: string? = nil
    
    if entity.entityType == "Player" and entity.player then
        targetKey = entity.player:GetAttribute("targetKey") :: string?
    else
        -- For NPCs, we might need a different targeting system
        -- For now, return nil as NPCs don't have targeting implemented
        return nil
    end
    
    if not targetKey or type(targetKey) ~= "string" then
        return nil
    end

    local taggedObjects = CollectionService:GetTagged(targetKey)
    if #taggedObjects > 0 then
        local targetObject = taggedObjects[1]
        if targetObject:IsA("Model") then
            -- Try to determine if this is a player or NPC
            local player = Players:GetPlayerFromCharacter(targetObject)
            if player then
                -- This is a player character (optimized)
                return createPlayerEntity(player)
            else
                -- This is likely an NPC (optimized)
                return createNpcEntity(targetObject)
            end
        end
    end

    return nil
end

-- Legacy method for backward compatibility
function ServerAbilityValidator:GetPlayerTarget(player: Player): Model?
    local entity: EntityRef = {
        entityType = "Player",
        player = player,
        npcId = nil,
        name = player.Name,
        userId = player.UserId
    }
    
    local targetEntity = self:GetEntityTarget(entity)
    if targetEntity and targetEntity.entityType == "Player" and targetEntity.player then
        return targetEntity.player.Character
    elseif targetEntity and targetEntity.entityType == "NPC" then
        -- Find NPC model in workspace
        for _, model in workspace:GetChildren() do
            if model:IsA("Model") and model.Name == targetEntity.name then
                return model
            end
        end
    end
    
    return nil
end

-- Cooldown Management Methods
function ServerAbilityValidator:_validateCooldownData(cooldowns: any): {[string]: number}?
    if type(cooldowns) ~= "table" then
        return nil
    end
    
    local validCooldowns = {}
    local currentTime = Utils.now()
    
    for abilityId, cooldownTime in pairs(cooldowns) do
        if type(abilityId) == "string" and type(cooldownTime) == "number" then
            -- Only accept cooldowns that are in the future
            if cooldownTime > currentTime then
                validCooldowns[abilityId] = cooldownTime
            end
        end
    end
    
    return validCooldowns
end

function ServerAbilityValidator:_applyCooldowns(player: Player, cooldowns: {[string]: number}, currentState: StateSnapshot): StateSnapshot
    local newState = Utils.shallowClone(currentState)
    if not newState.cooldowns then
        newState.cooldowns = {}
    end
    local stateCooldowns = newState.cooldowns :: {[string]: number}
    
    -- Apply each cooldown
    for abilityId, cooldownTime in pairs(cooldowns) do
        stateCooldowns[abilityId] = cooldownTime
        
        -- Update anti-cheat system
        self.antiCheat:UpdateCooldown(player, abilityId :: AbilityId, cooldownTime)
    end
    
    return newState
end

function ServerAbilityValidator:_processCooldownResult(player: Player, predictionId: string, abilityResult: AbilityResult, currentState: StateSnapshot)
    local validCooldowns = self:_validateCooldownData(abilityResult.cooldowns)
    
    if not validCooldowns or next(validCooldowns) == nil then
        -- No valid cooldowns to apply
        self:SendValidationResult(player, createValidationResult(predictionId, true))
        return
    end
    
    -- Apply cooldowns and update state
    local newState = self:_applyCooldowns(player, validCooldowns, currentState)
    self.stateManager:ApplyState(player, newState, { applyTransform = false })
    self:SendValidationResult(player, createValidationResult(
        predictionId, true, nil, newState, nil
    ))
end

function ServerAbilityValidator:_processAbilitySuccess(player: Player, predictionId: string, abilityResult: AbilityResult, currentState: StateSnapshot)
    if abilityResult.cooldowns then
        self:_processCooldownResult(player, predictionId, abilityResult, currentState)
    else
        self:SendValidationResult(player, createValidationResult(predictionId, true))
    end
end

function ServerAbilityValidator:_processAbilityFailure(player: Player, predictionId: string, abilityResult: AbilityResult, currentState: StateSnapshot)
    self:SendValidationResult(player, createValidationResult(
        predictionId, false, abilityResult.reason, currentState
    ))
end

function ServerAbilityValidator:HandlePredictionRequest(player: Player, requestData: any)
    local startTime = tick() -- Performance tracking
    
    -- Early validation with single allocation
    if type(requestData) ~= "table" then
        return self:SendValidationResult(player, createValidationResult("", false, "Invalid request"))
    end

    -- Extract and validate request data
    local predictionId = tostring(requestData.predictionId or "")
    local abilityId = tostring(requestData.abilityId or "") :: AbilityId
    local inputData = (type(requestData.inputData) == "table") and requestData.inputData or {}
    local timestamp = (type(requestData.timestamp) == "number") and requestData.timestamp or Utils.now()
    local serverState = self.stateManager:GetPlayerState(player)
    local originalState: StateSnapshot = requestData.originalState or serverState

    local request: PredictionRequest = {
        predictionId = predictionId,
        abilityId = abilityId,
        inputData = inputData,
        timestamp = timestamp,
        originalState = originalState,
    }

    -- Anti-cheat validation
    local okRequest, reason = self.antiCheat:ValidateRequest(player, request)
    if not okRequest then
        return self:SendValidationResult(player, createValidationResult(predictionId, false, reason))
    end

    -- State validation
    if not self.stateManager:ValidateState(request.originalState, serverState) then
        return self:SendValidationResult(player, createValidationResult(
            predictionId, false, "State desync detected", serverState
        ))
    end

    -- Get cached ability module using new system
    local abilityModule = self:GetAbilityModule(abilityId)
    if not abilityModule then
        return self:SendValidationResult(player, createValidationResult(
            predictionId, false, "Ability not found", serverState
        ))
    end

    local sharedModule = abilityModule.GetSharedModule()
    local configs = sharedModule.GetConfig()
    -- Check if ability requires target (updated method name)
    local requiresTarget: boolean = configs.REQUIRES_TARGET

    -- Create EntityRef for the player (optimized)
    local playerEntity = createPlayerEntity(player)

    -- Get entity target (if any) using updated method
    local entityTarget = self:GetEntityTarget(playerEntity)
    
    -- Optimized target position resolution
    local targetPosition: Vector3? = nil
    if inputData.target and type(inputData.target) == "userdata" then
        -- Client sent target position (Vector3) - highest priority
        targetPosition = inputData.target
    elseif entityTarget then
        -- Use entity target position (optimized helper function)
        targetPosition = getEntityPosition(entityTarget)
    elseif inputData.mouseHit and type(inputData.mouseHit) == "userdata" then
        -- Fallback to mouse hit position
        targetPosition = inputData.mouseHit
    end

    -- Validate target requirement
    if requiresTarget and not targetPosition then
        return self:SendValidationResult(player, createValidationResult(
            predictionId, false, "Target required but not found", serverState
        ))
    end

    local range = configs.ATTACK_RANGE or 0
    local playerCharacter = player.Character
    if playerCharacter and playerCharacter:FindFirstChild("HumanoidRootPart") then
        local humanoidRootPart = playerCharacter:FindFirstChild("HumanoidRootPart") :: BasePart
        local playerPosition = humanoidRootPart.Position

        -- Check range if we have a target position
        if targetPosition then
            local distance = (playerPosition - targetPosition).Magnitude
            if distance > range then
                return self:SendValidationResult(player, createValidationResult(
                    predictionId, false, "Target out of range", serverState
                ))
            end
        end
    end

    -- Create context (reuse inputData structure to reduce allocations)
    local context: SharedAbilityContext = {
        playerId = player.UserId,
        abilityId = abilityId :: any,
        timestamp = Utils.now(),
        inputData = {
            position = serverState.position,
            direction = inputData.direction,
            target = targetPosition, -- Use resolved target position
            mouseHit = inputData.mouseHit,
            extraData = inputData.extraData,
        },
        characterState = serverState,
    }

    -- Category-based validation before execution
    local validationResult = CategoryValidator.ValidateAbility(abilityModule, context)
    if not validationResult.success then
        return self:SendValidationResult(player, createValidationResult(
            predictionId, false, validationResult.reason or "Category validation failed", serverState
        ))
    end
    
    -- Execute ability using category-based dispatcher with error handling
    local success, result = pcall(function()
        return CategoryHandler.ExecuteAbility(abilityModule, context)
    end)
    
    if not success or type(result) ~= "table" or result.success == nil then
        return self:SendValidationResult(player, createValidationResult(
            predictionId, false, "Ability execution error: " .. tostring(result), serverState
        ))
    end

    local abilityResult = result :: AbilityResult

    -- Process ability result based on success/failure
    if abilityResult.success then
        -- Fire replication to other clients using the new system
        _NetworkServer:FireAllClientsExcept("ReplicateAbilityRequest", player, context)
        self:_processAbilitySuccess(player, predictionId, abilityResult, serverState)
    else
        self:_processAbilityFailure(player, predictionId, abilityResult, serverState)
    end
    
    -- Performance tracking
    updatePerformanceStats(tick() - startTime)
end

-- Handle R key reload requests
function ServerAbilityValidator:HandleReloadRequest(player: Player, reloadData: any)
    -- Basic validation
    if type(reloadData) ~= "table" then
        warn("Invalid reload request from", player.Name)
        return
    end
    
    local playerId = reloadData.playerId
    local abilityId = reloadData.abilityId
    
    -- Validate that the player is who they claim to be
    if playerId ~= player.UserId then
        warn("Player ID mismatch in reload request from", player.Name)
        return
    end
    
    -- Validate ability ID
    if type(abilityId) ~= "number" then
        warn("Invalid ability ID in reload request from", player.Name)
        return
    end
    
    -- Use CategoryHandler to handle the reload
    local success = CategoryHandler.HandleReload(playerId, abilityId)
    
    if success then
        print("Reload successful for player", player.Name, "ability", abilityId)
        -- Optionally, send confirmation back to client
        local reloadConfirmRemote = _NetworkServer:RegisterRemoteEvent("AbilityReloadConfirm")
        reloadConfirmRemote:FireClient(player, {
            abilityId = abilityId,
            success = true,
            timestamp = tick()
        })
    else
        print("Reload failed for player", player.Name, "ability", abilityId)
        local reloadConfirmRemote = _NetworkServer:RegisterRemoteEvent("AbilityReloadConfirm")
        reloadConfirmRemote:FireClient(player, {
            abilityId = abilityId,
            success = false,
            reason = "Cannot reload this ability",
            timestamp = tick()
        })
    end
end

local globalValidator = ServerAbilityValidator.new()
return globalValidator