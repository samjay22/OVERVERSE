--!strict
-- Server-side ability validation orchestrator

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local _NetworkServer = require(game.ServerStorage.Modules.Core.NetworkServer)
local AbilityValidationRoot = ServerStorage:WaitForChild("Modules"):WaitForChild("AbilityValidation")
local Utils = require(AbilityValidationRoot:WaitForChild("Utils"))
local Types = require(AbilityValidationRoot:WaitForChild("Types"))
local ServerStateManager = require(AbilityValidationRoot:WaitForChild("State"):WaitForChild("ServerStateManager"))
local AntiCheatValidator = require(AbilityValidationRoot:WaitForChild("AntiCheat"):WaitForChild("AntiCheatValidator"))
local Remotes = require(AbilityValidationRoot:WaitForChild("Network"):WaitForChild("Remotes"))

local ReplicateAbilityRequest : RemoteEvent = _NetworkServer:RegisterRemoteEvent("ReplicateAbilityRequest")

type AbilityId = Types.AbilityId
type StateSnapshot = Types.StateSnapshot
type AbilityResult = Types.AbilityResult
type SharedAbilityContext = Types.SharedAbilityContext
type ClientAbilityModule = Types.ClientAbilityModule
type PredictionRequest = Types.PredictionRequest
type ValidationResult = Types.ValidationResult

-- Cache ability modules to avoid repeated FindFirstChild calls
local abilityModuleCache: {[string]: ClientAbilityModule?} = {}
local clientAbilities = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ClientAbilities")

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

    return self
end

function ServerAbilityValidator:SendValidationResult(player: Player, result: ValidationResult)
    self.validationRemote:FireClient(player, result)
end

-- Cache and validate ability modules
function ServerAbilityValidator:GetAbilityModule(abilityId: string): ClientAbilityModule?
    local cached = abilityModuleCache[abilityId]
    if cached ~= nil then
        return cached
    end

    local mod = clientAbilities:FindFirstChild(abilityId)
    if not mod or not mod:IsA("ModuleScript") then
        abilityModuleCache[abilityId] = nil
        return nil
    end

    local ok, moduleOrErr = Utils.safeRequire(mod)
    if ok and type(moduleOrErr) == "table" and type(moduleOrErr.onRequest) == "function" then
        local validModule = moduleOrErr :: ClientAbilityModule
        abilityModuleCache[abilityId] = validModule
        return validModule
    end

    abilityModuleCache[abilityId] = nil
    return nil
end

-- Get player's target based on targetKey attribute
function ServerAbilityValidator:GetPlayerTarget(player: Player): Model?
    local targetKey = player:GetAttribute("targetKey")
    if not targetKey or type(targetKey) ~= "string" then
        return nil
    end

    local taggedObjects = CollectionService:GetTagged(targetKey)
    if #taggedObjects > 0 then
        local target = taggedObjects[1]
        if target:IsA("Model") then
            return target
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
    newState.cooldowns = newState.cooldowns or {}
    
    -- Apply each cooldown
    for abilityId, cooldownTime in pairs(cooldowns) do
        newState.cooldowns[abilityId] = cooldownTime
        
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

    -- Get cached ability module
    local abilityModule = self:GetAbilityModule(abilityId)
    if not abilityModule then
        return self:SendValidationResult(player, createValidationResult(
            predictionId, false, "Ability not found", serverState
        ))
    end

    -- Check if ability requires target
    local requiresTarget = false
    if type(abilityModule.getRequiresTarget) == "function" then
        local ok, result = pcall(abilityModule.getRequiresTarget)
        if ok and type(result) == "boolean" then
            requiresTarget = result
        end
    end

    -- Validate target requirement
    local target = self:GetPlayerTarget(player)
    if requiresTarget and not target then
        return self:SendValidationResult(player, createValidationResult(
            predictionId, false, "Target required but not found", serverState
        ))
    end

    -- Validate range if ability has getAbilityRange function
    if type(abilityModule.getAbilityRange) == "function" then
        local ok, range = pcall(abilityModule.getAbilityRange)
        if ok and type(range) == "number" and range > 0 then
            local playerCharacter = player.Character
            if playerCharacter and playerCharacter:FindFirstChild("HumanoidRootPart") then
                local playerPosition = playerCharacter.HumanoidRootPart.Position
                local targetPosition = nil

                -- Determine target position based on input
                if target and target:FindFirstChild("HumanoidRootPart") then
                    targetPosition = target.HumanoidRootPart.Position
                elseif inputData.mouseHit and type(inputData.mouseHit) == "userdata" then
                    targetPosition = inputData.mouseHit.Position
                elseif inputData.position and type(inputData.position) == "userdata" then
                    targetPosition = inputData.position
                end

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
            target = target or inputData.target,
            mouseHit = inputData.mouseHit,
            extraData = inputData.extraData,
        },
        characterState = serverState,
    }

    -- Execute ability with error handling
    local success, result = pcall(abilityModule.onRequest, context)
    if not success or type(result) ~= "table" or result.success == nil then
        return self:SendValidationResult(player, createValidationResult(
            predictionId, false, "Ability execution error", serverState
        ))
    end

    local abilityResult = result :: AbilityResult

    -- Process ability result based on success/failure
    if abilityResult.success then
        _NetworkServer:FireAllClientsExcept("ReplicateAbilityRequest", player, context)
        self:_processAbilitySuccess(player, predictionId, abilityResult, serverState)
    else
        self:_processAbilityFailure(player, predictionId, abilityResult, serverState)
    end
end

local globalValidator = ServerAbilityValidator.new()
return globalValidator
