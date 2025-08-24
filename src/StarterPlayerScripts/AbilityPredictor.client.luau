--!strict
-- Client Ability Predictor with enhanced validation and optimization
-- Config-based system that dynamically loads ability configurations from ClientAbilities
-- Instant local response with server validation and rollback (PivotTo-based)
-- Updated for new ability package system with dynamic config loading

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local ClientAbilities = require(game.ReplicatedStorage.Modules.ClientAbilities)
local ClientCategoryHandler = require(game.ReplicatedStorage.Modules.Utility.ClientCategoryHandler)
local ClientCategoryValidator = require(game.ReplicatedStorage.Modules.Utility.ClientCategoryValidator)
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local _AbilityConstants = require(game.ReplicatedStorage.Modules.Utility.AbilityConstants)

local Types = require(game.ReplicatedStorage.Modules.Types.ClientAbilityTypes)
type StateSnapshot = Types.StateSnapshot
type SharedAbilityContext = Types.SharedAbilityContext
type AbilityResult = Types.AbilityResult
type AbilityId = Enums.AbilityId

-- Performance Constants
local _PERFORMANCE_CHECK_INTERVAL = 10  -- Reduced frequency
local PREDICTION_TIMEOUT = 15  -- Shorter timeout for faster cleanup
local HOLD_LOOP_MIN_WAIT = 0.033  -- ~30 FPS, reduces CPU load while maintaining responsiveness
local MAX_PENDING_PREDICTIONS = 5  -- Limit concurrent predictions
local PREDICTION_POOL_SIZE = 16  -- Object pool size

-- Ability ID mapping for inputs (updated for new system)
local INPUT_ABILITY_MAP: {[EnumItem]: string} = {
    [Enum.UserInputType.MouseButton1] = Enums.AbilityId.RemM1,
    [Enum.UserInputType.MouseButton2] = Enums.AbilityId.RemM2,
}

-- Additional keyboard mapping (separate to handle different enum types)
local KEYBOARD_ABILITY_MAP: {[Enum.KeyCode]: string} = {
    [Enum.KeyCode.Q] = Enums.AbilityId.Dash,
    [Enum.KeyCode.E] = "RemE", -- Placeholder until proper enum exists
    [Enum.KeyCode.R] = "RemR", -- Placeholder until proper enum exists  
    [Enum.KeyCode.T] = "RemT", -- Placeholder until proper enum exists
    [Enum.KeyCode.F] = "RemF", -- Placeholder until proper enum exists
}

-- Ability configuration cache and utilities
local AbilityConfigCache = {}
local AbilityHandlerCache = {}  -- Cache handler instances

-- Ability ID utilities for new system
local AbilityUtils = {}

-- Maps string ability IDs to numeric IDs for the new system
local ABILITY_ID_MAP: {[string]: number} = {
    [Enums.AbilityId.RemM1] = 1,
    [Enums.AbilityId.RemM2] = 2,
    [Enums.AbilityId.Dash] = 3,
    RemE = 4,
    RemR = 5,
    RemT = 6,
    RemF = 7,
}

-- Reverse mapping for numeric to string conversion
local NUMERIC_TO_STRING_MAP: {[number]: string} = {}
for stringId, numericId in pairs(ABILITY_ID_MAP) do
    NUMERIC_TO_STRING_MAP[numericId] = stringId
end

function AbilityUtils.getNumericId(stringId: string): number
    return ABILITY_ID_MAP[stringId] or 0
end

function AbilityUtils.getStringId(numericId: number): string?
    return NUMERIC_TO_STRING_MAP[numericId]
end

-- Get ability config from ClientAbilities (with caching)
function AbilityUtils.getAbilityConfig(abilityId: string): any?
    local cached = AbilityConfigCache[abilityId]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end
    
    local ability = AbilityHandlerCache[abilityId] or ClientAbilities.GetAbility(abilityId)
    if ability then
        AbilityHandlerCache[abilityId] = ability
        if ability.GetSharedModule then
            local sharedModule = ability.GetSharedModule()
            if sharedModule and sharedModule.GetConfig then
                local config = sharedModule.GetConfig()
                AbilityConfigCache[abilityId] = config or false
                return config
            end
        end
    end
    
    AbilityConfigCache[abilityId] = false  -- Cache negative result
    return nil
end

-- Get cooldown time for an ability from its config
function AbilityUtils.getCooldownTime(abilityId: string): number
    local config = AbilityUtils.getAbilityConfig(abilityId)
    if config and config.COOLDOWN_TIME then
        return config.COOLDOWN_TIME
    end
    -- Fallback values if config is not available
    local fallbacks: {[string]: number} = {
        [Enums.AbilityId.RemM1] = 1.6,
        [Enums.AbilityId.RemM2] = 1.0,
        [Enums.AbilityId.Dash] = 3.0,
        RemE = 12.0,
        RemR = 20.0,
        RemT = 15.0,
        RemF = 25.0,
    }
    return fallbacks[abilityId] or 1.0
end

-- Get attack range for an ability from its config
function AbilityUtils.getAttackRange(abilityId: string): number
    local config = AbilityUtils.getAbilityConfig(abilityId)
    if config and config.ATTACK_RANGE then
        return config.ATTACK_RANGE
    end
    -- Default fallback range
    return 100
end

-- Check if ability requires a target
function AbilityUtils.requiresTarget(abilityId: string): boolean
    local config = AbilityUtils.getAbilityConfig(abilityId)
    if config and config.REQUIRES_TARGET ~= nil then
        return config.REQUIRES_TARGET
    end
    -- Default to not requiring target
    return false
end

-- Get all available abilities from the mapping
function AbilityUtils.getAllAbilityIds(): {string}
    local abilities = {}
    for abilityId in pairs(ABILITY_ID_MAP) do
        table.insert(abilities, abilityId)
    end
    return abilities
end

-- Preload all ability configs for faster access
function AbilityUtils.preloadConfigs()
    local abilities = AbilityUtils.getAllAbilityIds()
    for _, abilityId in abilities do
        AbilityUtils.getAbilityConfig(abilityId) -- This caches the config
    end
end

-- Get ability category from config
function AbilityUtils.getAbilityCategory(abilityId: string): string?
    local config = AbilityUtils.getAbilityConfig(abilityId)
    if config and config.ABILITY_CATEGORY then
        return config.ABILITY_CATEGORY
    end
    return nil
end

-- Check if ability is available (has a valid handler and config)
function AbilityUtils.isAbilityAvailable(abilityId: string): boolean
    local ability = ClientAbilities.GetAbility(abilityId)
    local config = AbilityUtils.getAbilityConfig(abilityId)
    local available = ability ~= nil and config ~= nil
    
    if not available then
        print("[AbilityUtils] Ability", abilityId, "not available - Ability:", ability ~= nil, "Config:", config ~= nil)
    end
    
    return available
end

-- Validation Module
local AbilityValidator = {}

function AbilityValidator.validateTarget(player: any, targetPosition: Vector3?, abilityId: string): (boolean, string?)
    local requiresTarget = AbilityUtils.requiresTarget(abilityId)
    
    if requiresTarget and not targetPosition then
        return false, "No target position provided for targeting ability"
    end
    
    local character = player.Character
    if not character or not character.PrimaryPart then
        return false, "Invalid character state"
    end
    
    return true, nil
end

function AbilityValidator.validateDistance(character: Model?, targetPosition: Vector3?, maxRange: number): (boolean, string?)
    if not character or not character.PrimaryPart then
        return false, "Invalid character"
    end
    
    if not targetPosition then
        return false, "No target position"
    end
    
    local distance = (character.PrimaryPart.Position - targetPosition).Magnitude
    if distance > maxRange then
        return false, `Target too far (${math.floor(distance)} > ${maxRange})`
    end
    
    return true, nil
end

function AbilityValidator.findTarget(player: any): (Model?, BasePart?)
    local targetKey = player:GetAttribute("targetKey") :: string?
    if not targetKey then
        return nil, nil
    end
    
    local targets = CollectionService:GetTagged(targetKey)
    local target = targets[1]
    if not target then
        return nil, nil
    end
    
    local targetModel = target :: Model & {PrimaryPart: BasePart?}
    return targetModel, targetModel.PrimaryPart
end

function AbilityValidator.validateAbilityRequirements(
    handler: any, 
    character: Model?, 
    targetPosition: Vector3?,
    abilityId: string
): (boolean, string?)
    if not handler then
        return false, "No ability handler found"
    end
    
    -- Check range with ability-specific range from config
    if targetPosition then
        local maxRange = AbilityUtils.getAttackRange(abilityId)
        local success, reason = AbilityValidator.validateDistance(character, targetPosition, maxRange)
        if not success then
            return false, reason
        end
    end
    
    return true, nil
end

-- Utility Functions
local Utils = {}

function Utils.now(): number
    return workspace:GetServerTimeNow()
end

function Utils.shallowClone<T>(t: {[any]: T}?): {[any]: T}
    local r: {[any]: T} = {}
    if t then
        for k, v in pairs(t) do
            r[k] = v
        end
    end
    return r
end

function Utils.getCharacterRootPart(character: Model?): BasePart?
    if not character then return nil end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then
        return hrp
    end
    return character.PrimaryPart
end

function Utils.getTargetPosition(player: any, input: AbilityInput): Vector3?
    -- Try to find targeted entity first
    local _targetModel, targetPart = AbilityValidator.findTarget(player)
    if targetPart then
        return targetPart.Position
    end
    
    -- Fallback to input target position (mouse hit)
    return input.target
end

-- Cooldown Manager - Centralized cooldown handling
local CooldownManager = {}
CooldownManager.__index = CooldownManager

function CooldownManager.new()
    local self = setmetatable({}, CooldownManager)
    
    -- Store end times for each ability (when they become usable again)
    self.cooldownEndTimes = {} :: {[string]: number}
    
    return self
end

function CooldownManager:getRemainingTime(abilityId: string, currentTime: number?): number
    local now = currentTime or Utils.now()
    local endTime: number? = self.cooldownEndTimes[abilityId]
    
    if not endTime then
        return 0
    end
    
    local remaining = endTime - now
    return math.max(0, remaining)
end

function CooldownManager:isOnCooldown(abilityId: string, currentTime: number?): boolean
    return self:getRemainingTime(abilityId, currentTime) > 0
end

function CooldownManager:startCooldown(abilityId: string, duration: number?, currentTime: number?)
    local now = currentTime or Utils.now()
    local cooldownDuration = duration or AbilityUtils.getCooldownTime(abilityId)
    
    -- Only extend cooldown if new end time is later than current
    local newEndTime = now + cooldownDuration
    local currentEndTime = self.cooldownEndTimes[abilityId] or 0
    
    self.cooldownEndTimes[abilityId] = math.max(newEndTime, currentEndTime)
end

function CooldownManager:setCooldownEndTime(abilityId: string, endTime: number)
    local currentEndTime = self.cooldownEndTimes[abilityId] or 0
    self.cooldownEndTimes[abilityId] = math.max(endTime, currentEndTime)
end

function CooldownManager:applyCooldowns(cooldowns: {[string]: number})
    for abilityId, endTime in pairs(cooldowns) do
        self:setCooldownEndTime(abilityId, endTime)
    end
end

function CooldownManager:clearCooldown(abilityId: string)
    self.cooldownEndTimes[abilityId] = nil
end

function CooldownManager:clearAllCooldowns()
    table.clear(self.cooldownEndTimes)
end

function CooldownManager:getActiveCooldowns(): {[string]: number}
    local now = Utils.now()
    local active = {}
    
    for abilityId, endTime: number in pairs(self.cooldownEndTimes) do
        local remaining = endTime - now
        if remaining > 0 then
            active[abilityId] = remaining
        end
    end
    
    return active
end

-- Types and Interfaces
type SmoothState = {
    active: boolean,
    startCF: CFrame?,
    targetCF: CFrame?,
    startTime: number,
    duration: number,
    startVel: Vector3?,
    targetVel: Vector3?,
}

type PredictionData = {
    id: string,
    timestamp: number,
    originalState: StateSnapshot,
    predictedState: StateSnapshot?,
    context: SharedAbilityContext,
    result: AbilityResult?,
    timeoutHandle: thread?,
}

type AbilityInput = { 
    direction: Vector3?, 
    target: Vector3?, 
    mouseHit: Vector3?, 
    extraData: {[string]: any}? 
}

-- Validation result type for better error handling
type ValidationResult = {
    success: boolean,
    reason: string?,
    abilityHandler: any?,
    character: Model?,
    targetPosition: Vector3?,
    context: SharedAbilityContext?,
}

-- Client Prediction Manager
local ClientPredictor = {}
ClientPredictor.__index = ClientPredictor

function ClientPredictor.new()
    local self = setmetatable({}, ClientPredictor)

    self.player = Players.LocalPlayer
    -- Immediate lock to prevent race conditions within the same frame
    self._immediateLock = false
    self.pendingPredictions = {} :: {[string]: PredictionData}
    self.pendingByAbility = {} :: {[string]: string}
    self.predictionCounter = 0 :: number
    
    -- Prediction pool for memory reuse
    self.predictionPool = table.create(PREDICTION_POOL_SIZE)
    self.predictionPoolSize = 0

    -- Global lock: only one ability at a time
    self.activePredictionId = nil :: string?

    -- Hold support (per ability)
    self.holdFlags = {} :: {[string]: boolean}
    self.holdTasks = {} :: {[string]: thread}
    
    -- Cache frequently used values
    self._lastCharacter = nil :: Model?
    self._lastCharacterCheck = 0

    -- Initialize cooldown manager
    self.cooldowns = CooldownManager.new()

    -- Smooth correction state to avoid visible jolts on rollbacks
    self.smooth = {
        active = false,
        startCF = nil,
        targetCF = nil,
        startTime = 0,
        duration = 0.12,
        startVel = nil,
        targetVel = nil,
    } :: SmoothState
    self.renderConn = RunService.RenderStepped:Connect(function(_dt)
        self:UpdateSmoothing()
    end)

    -- Network remotes
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    self.predictionRemote = remotes:WaitForChild("AbilityPrediction") :: RemoteEvent
    self.validationRemote = remotes:WaitForChild("AbilityValidation") :: RemoteEvent

    -- Listen for server validation
    self.validationRemote.OnClientEvent:Connect(function(validationData)
        self:HandleServerValidation(validationData)
    end)

    return self
end

-- Lightweight, short-lived lock to serialize ExecuteAbility start section
function ClientPredictor:_tryAcquireImmediate(): boolean
    if self._immediateLock then
        return false
    end
    self._immediateLock = true
    return true
end

function ClientPredictor:_releaseImmediate(): ()
    self._immediateLock = false
end

function ClientPredictor:GeneratePredictionId(): string
    self.predictionCounter = (self.predictionCounter :: number) + 1
    return `pred_{self.player.UserId}_{self.predictionCounter}_{HttpService:GenerateGUID(false)}`
end

function ClientPredictor:ExecuteAbility(abilityId: string, input: AbilityInput): boolean
    -- Fast path checks - fail immediately if basic conditions aren't met
    if not self:_tryAcquireImmediate() then
        return false
    end

    if self.activePredictionId ~= nil then
        self:_releaseImmediate()
        return false
    end

    if self.pendingByAbility[abilityId] ~= nil then
        self:_releaseImmediate()
        return false
    end
    
    -- Check prediction limit
    local pendingCount = 0
    for _ in pairs(self.pendingPredictions) do
        pendingCount += 1
        if pendingCount >= MAX_PENDING_PREDICTIONS then
            self:_releaseImmediate()
            return false
        end
    end

    local tNow = Utils.now()
    if self.cooldowns:isOnCooldown(abilityId, tNow) then
        self:_releaseImmediate()
        return false
    end

    -- Comprehensive validation before any side effects
    local validation = self:_validateAbilityExecution(abilityId, input, tNow)
    if not validation.success then
        if validation.reason then
            warn("Ability execution failed:", validation.reason)
        end
        self:_releaseImmediate()
        return false
    end

    local abilityHandler: Types.ClientAbility = validation.abilityHandler :: any
    local context = validation.context :: SharedAbilityContext
    
    -- Execute client-side ability using category-based dispatcher
    task.spawn(function()
        ClientCategoryHandler.ExecuteAbility(abilityHandler, context)
    end)

    -- Apply cooldown and create prediction
    self.cooldowns:startCooldown(abilityId, nil, tNow)
    self:_createAndSendPrediction(abilityId, input, context, validation.character :: Model)
    
    self:_releaseImmediate()
    return true
end

-- Handle R key reload for Primary abilities
function ClientPredictor:HandleReload()
    local player = self.player
    if not player.Character then return end
    
    -- Find Primary abilities that could be reloaded
    local primaryAbilities = {}
    for abilityString, numericId in pairs(ABILITY_ID_MAP) do
        local config = AbilityUtils.getAbilityConfig(abilityString)
        if config and config.ABILITY_CATEGORY == "Primary" then
            table.insert(primaryAbilities, {
                stringId = abilityString,
                numericId = numericId,
                config = config
            })
        end
    end
    
    -- For now, just reload the first Primary ability found (RemM1)
    -- In a more complex system, you might want to reload all or track which was last used
    if #primaryAbilities > 0 then
        local abilityToReload = primaryAbilities[1]
        
        -- Create reload context
        local currentTime = Utils.now()
        local context = {
            playerId = player.UserId,
            abilityId = abilityToReload.numericId,
            timestamp = currentTime,
            inputData = {
                position = player.Character:GetPivot().Position,
                direction = Vector3.new(0, 0, -1), -- Default forward
                target = nil,
                mouseHit = nil,
                extraData = { action = "reload" },
            },
            characterState = {
                timestamp = currentTime,
                position = player.Character:GetPivot().Position,
                velocity = Vector3.new(),
                health = 100, -- Simplified
                stamina = 100,
                cooldowns = {},
                effects = {},
            },
        }
        
        -- Send reload request to server via remote event
        -- This will trigger CategoryHandler.HandleReload on the server
        local reloadRemote = ReplicatedStorage.Remotes:FindFirstChild("AbilityReload") :: RemoteEvent?
        if reloadRemote then
            reloadRemote:FireServer({
                playerId = player.UserId,
                abilityId = abilityToReload.numericId,
                context = context
            })
            
            print("Reload requested for:", abilityToReload.stringId)
        else
            warn("AbilityReload remote event not found")
        end
    else
        print("No Primary abilities found to reload")
    end
end

-- Comprehensive validation method
function ClientPredictor:_validateAbilityExecution(abilityId: string, input: AbilityInput, currentTime: number): ValidationResult
    -- Check if ability is available
    if not AbilityUtils.isAbilityAvailable(abilityId) then
        return { success = false, reason = "Ability not available or not loaded" }
    end
    
    -- Get ability handler from new system
    local abilityHandler = ClientAbilities.GetAbility(abilityId)
    if not abilityHandler then
        return { success = false, reason = "No ability handler found" }
    end

    -- Validate character state
    local character = self.player.Character
    if not character then
        return { success = false, reason = "No character" }
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = Utils.getCharacterRootPart(character)
    local pivotCF = character:GetPivot()

    if not root then
        return { success = false, reason = "No character root part" }
    end

    -- Get and validate target position
    local targetPosition = Utils.getTargetPosition(self.player, input)
    
    -- Validate ability requirements (distance, target, etc.)
    local reqSuccess, reqReason = AbilityValidator.validateAbilityRequirements(
        abilityHandler, 
        character, 
        targetPosition,
        abilityId
    )
    if not reqSuccess then
        return { success = false, reason = reqReason }
    end

    -- Build context for category validation
    local activeCooldowns = self.cooldowns:getActiveCooldowns()
    local healthValue = if humanoid then (humanoid :: Humanoid).Health else 100
    local originalState: StateSnapshot = {
        timestamp = currentTime,
        position = pivotCF.Position,
        velocity = root.AssemblyLinearVelocity or Vector3.new(),
        health = healthValue,
        stamina = 100,
        cooldowns = activeCooldowns,
        effects = {},
    }

    -- Convert ability ID to number for new system
    local numericAbilityId = AbilityUtils.getNumericId(abilityId)

    local context: SharedAbilityContext = {
        playerId = self.player.UserId,
        abilityId = numericAbilityId,
        timestamp = currentTime,
        inputData = {
            position = originalState.position,
            direction = input.direction,
            target = targetPosition,
            mouseHit = input.mouseHit,
            extraData = input.extraData,
        },
        characterState = originalState,
    }

    -- Category-based validation
    local categoryValidation = ClientCategoryValidator.ValidateAbility(abilityHandler, context)
    if not categoryValidation.success then
        return { success = false, reason = categoryValidation.reason }
    end

    return {
        success = true,
        abilityHandler = abilityHandler,
        character = character,
        targetPosition = targetPosition,
        context = context,
    }
end

-- Create and send prediction to server
function ClientPredictor:_createAndSendPrediction(
    abilityId: string, 
    input: AbilityInput, 
    context: SharedAbilityContext, 
    character: Model
)
    local predictionId = self:GeneratePredictionId()
    
    -- Try to reuse pooled prediction object
    local prediction: PredictionData
    if self.predictionPoolSize > 0 then
        prediction = self.predictionPool[self.predictionPoolSize]
        self.predictionPool[self.predictionPoolSize] = nil
        self.predictionPoolSize -= 1
        -- Reset reused object
        prediction.id = predictionId
        prediction.timestamp = time()
        prediction.originalState = context.characterState
        prediction.predictedState = context.characterState
        prediction.context = context
        prediction.result = { success = true }
    else
        prediction = {
            id = predictionId,
            timestamp = time(),
            originalState = context.characterState,
            predictedState = context.characterState,
            context = context,
            result = { success = true },
            timeoutHandle = nil,
        }
    end
    
    prediction.timeoutHandle = task.delay(PREDICTION_TIMEOUT, function()
        self:TimeoutPrediction(predictionId)
    end)

    -- Update tracking
    self.pendingPredictions[predictionId] = prediction
    self.pendingByAbility[abilityId] = predictionId
    self.activePredictionId = predictionId

    -- Send to server asynchronously
    self:_sendPredictionToServer(predictionId, abilityId, input, context, context.characterState)
end

function ClientPredictor:_sendPredictionToServer(
    predictionId: string, 
    abilityId: string, 
    input: AbilityInput, 
    context: SharedAbilityContext, 
    originalState: StateSnapshot
)
    task.spawn(function()
        self.predictionRemote:FireServer({
            predictionId = predictionId,
            abilityId = abilityId,
            inputData = input,
            timestamp = context.timestamp,
            originalState = originalState,
        })
    end)
end

function ClientPredictor:HandleServerValidation(validationData: any)
    local predictionId = validationData.predictionId
    local prediction = self.pendingPredictions[predictionId]

    if not prediction then
        return -- Already handled or timed out
    end

    -- Cancel timeout
    if prediction.timeoutHandle then
        task.cancel(prediction.timeoutHandle)
    end

    if validationData.success then
        -- Success: Trust client's position, only update non-positional data
        local character: Model? = self.player.Character
        if character and validationData.correctedState then
            local st: any = validationData.correctedState

            -- Only update non-positional authoritative data
            if st.health then
                local hum = character:FindFirstChildOfClass("Humanoid")
                if hum then hum.Health = st.health end
            end
            if st.stamina then
                -- Hook for stamina system
            end
        end

        -- Apply server cooldowns if provided
        if validationData.cooldowns then
            self.cooldowns:applyCooldowns(validationData.cooldowns)
        end

        -- -- OnReplicate hook - updated for new system
        -- local ctx: SharedAbilityContext = prediction.context
        -- local stringAbilityId = AbilityUtils.getStringId(ctx.abilityId)
        -- if stringAbilityId then
        --     local handler = ClientAbilities.GetAbility(stringAbilityId)
        --     if handler and handler.OnReplicate then
        --         pcall(handler.OnReplicate, ctx, validationData)
        --     end
        -- end
    else
        -- Server rejected - rollback if needed
        warn("Server rejected ability:", validationData.reason or "Unknown reason")

        -- Apply server cooldowns if provided
        if validationData.cooldowns then
            self.cooldowns:applyCooldowns(validationData.cooldowns)
        end

        if validationData.correctedState and validationData.correctedState.position then
            self:ApplyServerCorrection(validationData.correctedState)
        else
            local character: Model? = self.player.Character
            if character and validationData.correctedState then
                local st: any = validationData.correctedState
                if st.health then
                    local hum = character:FindFirstChildOfClass("Humanoid")
                    if hum then hum.Health = st.health end
                end
            end
        end

        -- OnCancel hook - updated for new system
        local ctx = prediction.context
        local stringAbilityId = AbilityUtils.getStringId(ctx.abilityId)
        if stringAbilityId then
            local handler = ClientAbilities.GetAbility(stringAbilityId)
            if handler and handler.OnCancel then
                pcall(handler.OnCancel, ctx, validationData and validationData.reason)
            end
        end
    end

    -- Clean up and return to pool
    self.pendingPredictions[predictionId] = nil
    -- Clear per-ability pending slot
    if prediction and prediction.context then
        local stringAbilityId = AbilityUtils.getStringId(prediction.context.abilityId)
        if stringAbilityId and self.pendingByAbility[stringAbilityId] == predictionId then
            self.pendingByAbility[stringAbilityId] = nil
        end
    end
    -- Release global lock if this was the active
    if self.activePredictionId == predictionId then
        self.activePredictionId = nil
    end
    
    -- Return prediction to pool if there's space
    if self.predictionPoolSize < PREDICTION_POOL_SIZE and prediction then
        -- Clear references to help GC
        prediction.context = nil
        prediction.originalState = nil
        prediction.predictedState = nil
        prediction.result = nil
        prediction.timeoutHandle = nil
        
        self.predictionPoolSize += 1
        self.predictionPool[self.predictionPoolSize] = prediction
    end
end

function ClientPredictor:ApplyServerCorrection(correctedState: any)
    local character: Model? = self.player.Character
    if not character then return end

    -- Health correction is always safe
    local h = character:FindFirstChildOfClass("Humanoid")
    if h and correctedState.health then
        h.Health = correctedState.health
    end

    -- Position correction with aggressive thresholds to minimize corrections
    if correctedState.position then
        local currentPivot = character:GetPivot()
        local serverPos = correctedState.position
        local delta = (currentPivot.Position - serverPos)
        local distance = delta.Magnitude

        -- Much higher threshold - only correct if significantly desynced
        if distance < 10.0 then
            return
        end

        if distance > 20 then
            -- Massive desync (likely teleport/respawn) - instant snap
            local rotationOnly = currentPivot - currentPivot.Position
            local newPivot = CFrame.new(serverPos) * rotationOnly
            character:PivotTo(newPivot)

            local hrp: BasePart? = (character:FindFirstChild("HumanoidRootPart") :: BasePart?) or character.PrimaryPart
            if hrp and correctedState.velocity then
                hrp.AssemblyLinearVelocity = correctedState.velocity
            end
        else
            -- Medium desync - apply very smooth correction
            local duration = math.clamp(distance / 10, 0.15, 0.5)
            self:StartSmoothCorrection(serverPos, correctedState.velocity, duration)
        end
    end
end

function ClientPredictor:TimeoutPrediction(predictionId: string)
    local prediction = self.pendingPredictions[predictionId]
    if not prediction then
        return
    end

    warn("Ability prediction timed out - keeping client state (no rollback)")

    -- Optional: notify module of timeout
    local ctx = prediction.context
    local stringAbilityId = AbilityUtils.getStringId(ctx.abilityId)
    if stringAbilityId then
        local handler = ClientAbilities.GetAbility(stringAbilityId)
        if handler and handler.OnTimeout then
            pcall(handler.OnTimeout, ctx)
        end
    end

    self.pendingPredictions[predictionId] = nil
    -- Clear per-ability pending slot
    if stringAbilityId and self.pendingByAbility[stringAbilityId] == predictionId then
        self.pendingByAbility[stringAbilityId] = nil
    end
    -- Release global lock if this was the active
    if self.activePredictionId == predictionId then
        self.activePredictionId = nil
    end
end

function ClientPredictor:RollbackPrediction(prediction: any)
    -- Only rollback to original state if explicitly needed
    local st = prediction.originalState
    local character: Model? = self.player.Character
    if not character then return end

    local currentPivot = character:GetPivot()
    local originalPos = st.position

    if originalPos then
        local delta = (currentPivot.Position - originalPos)
        local distance = delta.Magnitude

        if distance > 5.0 then
            self:StartSmoothCorrection(originalPos, st.velocity, 0.3)
        end
    end
end

function ClientPredictor:StartSmoothCorrection(targetPosition: Vector3, targetVelocity: Vector3?, duration: number?)
    local character: Model? = self.player.Character
    if not character then return end
    local currentPivot = character:GetPivot()

    local rotationOnly = currentPivot - currentPivot.Position
    local targetCF = CFrame.new(targetPosition) * rotationOnly

    local hrp: BasePart? = (character:FindFirstChild("HumanoidRootPart") :: BasePart?) or character.PrimaryPart
    local startVel = hrp and hrp.AssemblyLinearVelocity or Vector3.zero

    self.smooth.startCF = currentPivot
    self.smooth.targetCF = targetCF
    self.smooth.startTime = time()
    self.smooth.duration = duration or 0.25
    self.smooth.startVel = startVel
    self.smooth.targetVel = targetVelocity or startVel
    self.smooth.active = true
end

function ClientPredictor:UpdateSmoothing()
    local s = self.smooth
    if not s.active then return end
    local character: Model? = self.player.Character
    if not character then
        s.active = false
        return
    end
    if not s.startCF or not s.targetCF then
        s.active = false
        return
    end

    local elapsed = time() - s.startTime
    local alpha = if s.duration > 0 then math.clamp(elapsed / s.duration, 0, 1) else 1

    local easedAlpha = 1 - (1 - alpha) * (1 - alpha) -- Quadratic ease-out

    local newCF = s.startCF:Lerp(s.targetCF, easedAlpha)
    character:PivotTo(newCF)

    if s.startVel and s.targetVel then
        local hrp: BasePart? = (character:FindFirstChild("HumanoidRootPart") :: BasePart?) or character.PrimaryPart
        if hrp then
            local currentY = hrp.AssemblyLinearVelocity.Y
            local lerpedVel = s.startVel:Lerp(s.targetVel, easedAlpha)
            hrp.AssemblyLinearVelocity = Vector3.new(lerpedVel.X, currentY, lerpedVel.Z)
        end
    end

    if alpha >= 1 then
        s.active = false
    end
end

-- Optimized Hold Loop System
function ClientPredictor:StartHoldLoop(abilityId: string)
    if self.holdTasks[abilityId] ~= nil then
        return
    end
    
    self.holdFlags[abilityId] = true

    self.holdTasks[abilityId] = task.spawn(function()
        local lastInputData = nil
        while self.holdFlags[abilityId] do
            local currentTime = Utils.now()
            
            -- Only execute if not on cooldown and not actively predicting
            if self.activePredictionId == nil and not self.cooldowns:isOnCooldown(abilityId, currentTime) then
                local character: Model? = self:_getCachedCharacter()
                if character then
                    -- Cache input data to avoid recalculating if nothing changed
                    local inputData = lastInputData or self:_getMouseInputData(character)
                    if inputData then
                        lastInputData = inputData
                        self:ExecuteAbility(abilityId, inputData)
                    end
                end
            end

            -- Wait a consistent frame time for smooth input
            task.wait(HOLD_LOOP_MIN_WAIT)
        end
        self.holdTasks[abilityId] = nil
    end)
end

function ClientPredictor:StopHoldLoop(abilityId: string)
    self.holdFlags[abilityId] = false
end

-- Get cached character to reduce lookups
function ClientPredictor:_getCachedCharacter(): Model?
    local now = time()
    if now - self._lastCharacterCheck > 0.1 then  -- Cache for 100ms
        self._lastCharacter = self.player.Character
        self._lastCharacterCheck = now
    end
    return self._lastCharacter
end

-- Enhanced mouse input data with validation
function ClientPredictor:_getMouseInputData(character: Model): AbilityInput?
    local mouse = self.player:GetMouse()
    if not mouse then return nil end
    
    local pivotCF = character:GetPivot()
    local mouseHit = mouse.Hit
    
    if not mouseHit then return nil end
    
    -- Calculate direction from character to mouse position (always toward cursor)
    local characterPos = pivotCF.Position
    local mousePos = mouseHit.Position
    
    -- Create direction vector on the horizontal plane (Y = character Y level)
    local horizontalMousePos = Vector3.new(mousePos.X, characterPos.Y, mousePos.Z)
    local direction = (horizontalMousePos - characterPos)
    
    -- Normalize direction, with fallback
    if direction.Magnitude > 0.001 then
        direction = direction.Unit
    else
        -- If too close to character, use character's facing direction as fallback
        direction = pivotCF.LookVector
    end
    
    return {
        direction = direction,
        target = mousePos,
        mouseHit = mousePos,
    }
end

-- Input Handling System
function ClientPredictor:SetupInputHandling()
    local function createHoldHandler(handlerType: string)
        return function(abilityId: string)
            if handlerType == "start" then
                self:StartHoldLoop(abilityId)
            else
                self:StopHoldLoop(abilityId)
            end
        end
    end

    local inputBeganHandlers = {
        [Enum.UserInputType.MouseButton1] = createHoldHandler("start"),
        [Enum.UserInputType.MouseButton2] = createHoldHandler("start"),
    }

    local inputEndedHandlers = {
        [Enum.UserInputType.MouseButton1] = createHoldHandler("stop"),
        [Enum.UserInputType.MouseButton2] = createHoldHandler("stop"),
    }

    local player = self.player

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        local character = player.Character
        if not character then return end

        -- Determine ability from input
        local queryEnum: EnumItem = if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2
            or input.UserInputType == Enum.UserInputType.MouseButton3
            then input.UserInputType
            else input.KeyCode

        local abilityId: string? = INPUT_ABILITY_MAP[queryEnum] or KEYBOARD_ABILITY_MAP[input.KeyCode]
        
        -- Special handling for R key reload
        if input.KeyCode == Enum.KeyCode.R then
            self:HandleReload()
            return
        end
        
        if not abilityId then return end

        -- Handle mouse buttons with hold loops
        local holdHandler = inputBeganHandlers[input.UserInputType]
        if holdHandler then
            holdHandler(abilityId)
            return
        end

        -- Handle keyboard inputs
        if self.activePredictionId ~= nil or self.cooldowns:isOnCooldown(abilityId) then
            return
        end

        local inputData = self:_getMouseInputData(character)
        if inputData then
            self:ExecuteAbility(abilityId, inputData)
        end
    end)

    UserInputService.InputEnded:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        local endHandler = inputEndedHandlers[input.UserInputType]
        if not endHandler then return end

        local abilityId: string? = INPUT_ABILITY_MAP[input.UserInputType]
        if abilityId then
            endHandler(abilityId)
        end
    end)
end

-- Performance Monitoring
function ClientPredictor:StartPerformanceMonitoring()
    task.spawn(function()
        while true do
            task.wait(_PERFORMANCE_CHECK_INTERVAL)

            local pendingCount = 0
            local oldestPrediction = math.huge
            local stalePredictions = {}

            for id, prediction in pairs(self.pendingPredictions) do
                pendingCount += 1
                local age = time() - prediction.timestamp
                oldestPrediction = math.min(oldestPrediction, prediction.timestamp)
                
                if age > PREDICTION_TIMEOUT then
                    table.insert(stalePredictions, id)
                end
            end

            for _, id in stalePredictions do
                self:TimeoutPrediction(id)
            end

            if pendingCount > 3 or oldestPrediction < math.huge and (time() - oldestPrediction) > 3 then
                local oldestAge = if oldestPrediction < math.huge then time() - oldestPrediction else 0
                warn(`Performance: {pendingCount} predictions pending, oldest: {math.floor(oldestAge * 100) / 100}s`)
            end
        end
    end)
end

function ClientPredictor:PrintControls()
    print("Client ability predictor initialized (Config-based system)")
    print("Controls:")
    
    -- Print mouse button abilities
    for input, abilityId in pairs(INPUT_ABILITY_MAP) do
        local inputName = if typeof(input) == "EnumItem" then input.Name else tostring(input)
        local cooldown = AbilityUtils.getCooldownTime(abilityId)
        local range = AbilityUtils.getAttackRange(abilityId)
        local category = AbilityUtils.getAbilityCategory(abilityId) or "Unknown"
        local requiresTarget = AbilityUtils.requiresTarget(abilityId)
        local available = AbilityUtils.isAbilityAvailable(abilityId)
        
        local status = if available then "✓" else "✗"
        local targetInfo = if requiresTarget then " [Target Required]" else ""
        
        print(`{status} {inputName} - {abilityId} ({category}) | Cooldown: {cooldown}s | Range: {range}{targetInfo}`)
    end
    
    -- Print keyboard abilities
    for input, abilityId in pairs(KEYBOARD_ABILITY_MAP) do
        local inputName = if typeof(input) == "EnumItem" then input.Name else tostring(input)
        local cooldown = AbilityUtils.getCooldownTime(abilityId)
        local range = AbilityUtils.getAttackRange(abilityId)
        local category = AbilityUtils.getAbilityCategory(abilityId) or "Unknown"
        local requiresTarget = AbilityUtils.requiresTarget(abilityId)
        local available = AbilityUtils.isAbilityAvailable(abilityId)
        
        local status = if available then "✓" else "✗"
        local targetInfo = if requiresTarget then " [Target Required]" else ""
        
        print(`{status} {inputName} - {abilityId} ({category}) | Cooldown: {cooldown}s | Range: {range}{targetInfo}`)
    end
    
    print("Legend: ✓ = Available, ✗ = Not loaded/configured")
end

-- Initialize the system
local predictor = ClientPredictor.new()

-- Function to wait for abilities to be loaded
local function waitForAbilities()
    print("[AbilityPredictor] Waiting for abilities to load...")
    local attempts = 0
    local abilitiesLoaded = false
    
    while not abilitiesLoaded and attempts < 30 do
        attempts += 1
        
        -- Check if core abilities are loaded
        local hasRemM1 = ClientAbilities.GetAbility("RemM1") ~= nil
        local hasRemM2 = ClientAbilities.GetAbility("RemM2") ~= nil
        local hasDash = ClientAbilities.GetAbility("Dash") ~= nil
        local hasRemE = ClientAbilities.GetAbility("RemE") ~= nil
        
        print("[AbilityPredictor] Check", attempts, "- RemM1:", hasRemM1, "RemM2:", hasRemM2, "Dash:", hasDash, "RemE:", hasRemE)
        
        if hasRemM1 or hasRemM2 or hasDash or hasRemE then
            abilitiesLoaded = true
            print("[AbilityPredictor] Abilities loaded successfully!")
            break
        end
        
        task.wait(0.5)
    end
    
    if not abilitiesLoaded then
        warn("[AbilityPredictor] Abilities failed to load after 15 seconds")
    else
        -- Preload configs after abilities are confirmed loaded
        print("[AbilityPredictor] Preloading ability configs...")
        AbilityUtils.preloadConfigs()
        print("[AbilityPredictor] Configs preloaded")
    end
    
    return abilitiesLoaded
end

-- Wait for abilities before setting up input
task.spawn(function()
    local loaded = waitForAbilities()
    
    if loaded then
        print("[AbilityPredictor] Setting up input handling...")
        -- Setup the predictor using any type to bypass type checking
        local anyPredictor = predictor :: any
        anyPredictor:SetupInputHandling()
        anyPredictor:StartPerformanceMonitoring()
        anyPredictor:PrintControls()
    else
        warn("[AbilityPredictor] Not setting up input handling due to load failure")
    end
end)

return predictor