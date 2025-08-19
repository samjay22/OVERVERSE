--!strict
-- Client Ability Predictor with enhanced validation and optimization
-- Instant local response with server validation and rollback (PivotTo-based)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local _require: any = require
local ClientAbilities = _require(ReplicatedStorage.Modules.ClientAbilities)

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)
type AbilityId = Types.AbilityId
type StateSnapshot = Types.StateSnapshot
type SharedAbilityContext = Types.SharedAbilityContext
type AbilityResult = Types.AbilityResult

-- Validation Constants
local MAX_ABILITY_RANGE = 200 -- Maximum range for any ability
local _TARGET_VALIDATION_TOLERANCE = 2 -- Tolerance for target position validation

-- Performance Constants
local PERFORMANCE_CHECK_INTERVAL = 5
local PREDICTION_TIMEOUT = 30
local HOLD_LOOP_MIN_WAIT = 0.001
local HOLD_LOOP_MAX_WAIT = 0.5

-- Validation Module
local AbilityValidator = {}

function AbilityValidator.validateTarget(player: any, targetPosition: Vector3?): (boolean, string?)
    if not targetPosition then
        return false, "No target position provided"
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
    targetPosition: Vector3?
): (boolean, string?)
    if not handler then
        return false, "No ability handler found"
    end
    
    -- Check if ability requires a target
    local requiresTarget = handler.getRequiresTarget and handler.getRequiresTarget() or false
    if requiresTarget then
        local success, reason = AbilityValidator.validateTarget(Players.LocalPlayer, targetPosition)
        if not success then
            return false, reason
        end
    end
    
    -- Check range if available
    local maxRange = handler.getAbilityRange and handler.getAbilityRange() or MAX_ABILITY_RANGE
    if targetPosition then
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

-- Client Prediction Manager
local ClientPredictor = {}
ClientPredictor.__index = ClientPredictor

function ClientPredictor.new()
    local self = setmetatable({}, ClientPredictor)

    self.player = Players.LocalPlayer
    -- Immediate lock to prevent race conditions within the same frame
    -- This is separate from activePredictionId which represents the long-lived global lock
    self._immediateLock = false
    self.pendingPredictions = {} :: {[string]: {
        id: string,
        timestamp: number,
        originalState: StateSnapshot,
        predictedState: StateSnapshot?,
        context: SharedAbilityContext,
        result: AbilityResult?,
        timeoutHandle: thread?,
    }}
    self.pendingByAbility = {} :: {[AbilityId]: string}
    self.predictionCounter = 0 :: number

    -- Global lock: only one ability at a time
    self.activePredictionId = nil :: string?

    -- Hold support (per ability)
    self.holdFlags = {} :: {[AbilityId]: boolean}
    self.holdTasks = {} :: {[AbilityId]: thread}

    -- Local client-side cooldowns for debounce (abilityId string -> server time when usable)
    self.localCooldowns = {} :: {[string]: number}
    self.defaultDebounce = 0.15 -- fallback debounce if module didn't return a cooldown

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

-- Local debounce helpers
function ClientPredictor:GetCooldownRemaining(abilityId: AbilityId, t: number?): number
    local key = tostring(abilityId)
    local lc = self.localCooldowns :: {[string]: number}
    local untilTs: number? = lc[key]
    local current = t or Utils.now()
    if untilTs ~= nil then
        local diff = (untilTs :: number) - current
        if diff > 0 then
            return diff
        end
    end
    return 0
end

function ClientPredictor:ApplyCooldowns(cooldowns: {[string]: number}?)
    if not cooldowns then return end
    for k, v in pairs(cooldowns) do
        -- Store the max to avoid shortening an existing cooldown
    local lc = self.localCooldowns :: {[string]: number}
    local prev: number = lc[k] or 0
    lc[k] = math.max(prev, v)
    end
end

type AbilityInput = { direction: Vector3?, target: Vector3?, mouseHit: Vector3?, extraData: {[string]: any}? }

-- Validation result type for better error handling
type ValidationResult = {
    success: boolean,
    reason: string?,
    abilityHandler: any?,
    character: Model?,
    targetPosition: Vector3?,
    context: SharedAbilityContext?,
}

function ClientPredictor:ExecuteAbility(abilityId: AbilityId, input: AbilityInput): boolean
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

    local tNow = Utils.now()
    if self:GetCooldownRemaining(abilityId, tNow) > 0 then
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

    -- Get ability module's validation result BEFORE executing visuals
    local abilityHandler = validation.abilityHandler :: any
    local context = validation.context :: SharedAbilityContext
    
    local result: AbilityResult = self:_getAbilityModuleResult(abilityHandler, context)
    if not result.success then
        self:_applyMinimalDebounce(abilityId, tNow)
        warn("Ability module validation failed:", result.reason)
        self:_releaseImmediate()
        return false
    end

   task.spawn(function()
       if abilityHandler.onCast then
           Players.LocalPlayer:SetAttribute("UsingAbility", true)
           pcall(abilityHandler.onCast, context)
        task.defer(function()
                Players.LocalPlayer:SetAttribute("UsingAbility", false)
            end)
        end
   end)

    -- Apply cooldowns and finalize prediction
    self:_applyCooldownsFromResult(result, abilityId, tNow)
    self:_createAndSendPrediction(abilityId, input, context, validation.character :: Model, result)
    
    self:_releaseImmediate()
    return true
end

-- Comprehensive validation method
function ClientPredictor:_validateAbilityExecution(abilityId: AbilityId, input: AbilityInput, currentTime: number): ValidationResult
    -- Get ability handler
    local abilityHandler = ClientAbilities.Get(abilityId)
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
        targetPosition
    )
    if not reqSuccess then
        return { success = false, reason = reqReason }
    end

    -- Build context for successful validation
    local cooldownsClone = Utils.shallowClone(self.localCooldowns)
    local healthValue = if humanoid then (humanoid :: Humanoid).Health else 100
    local originalState: StateSnapshot = {
        timestamp = currentTime,
        position = pivotCF.Position,
        velocity = root.AssemblyLinearVelocity or Vector3.new(),
        health = healthValue,
        stamina = 100,
        cooldowns = cooldownsClone,
        effects = {},
    }

    local context: SharedAbilityContext = {
        playerId = self.player.UserId,
        abilityId = abilityId,
        timestamp = currentTime,
        inputData = {
            position = originalState.position,
            direction = input.direction,
            target = targetPosition, -- Use resolved target position instead of raw input
            mouseHit = input.mouseHit,
            extraData = input.extraData,
        },
        characterState = originalState,
    }

    return {
        success = true,
        abilityHandler = abilityHandler,
        character = character,
        targetPosition = targetPosition,
        context = context,
    }
end

-- Get result from ability module
function ClientPredictor:_getAbilityModuleResult(abilityHandler: any, context: SharedAbilityContext): AbilityResult
    if not abilityHandler.onRequest then
        return { success = false, reason = "No onRequest method" }
    end

    local success, result = pcall(abilityHandler.onRequest :: any, context)
    if not success then
        return { success = false, reason = `onRequest error: {result}` }
    end

    if not result or not result.success then
        return result or { success = false, reason = "onRequest returned falsy" }
    end

    return result
end

-- Create and send prediction to server
function ClientPredictor:_createAndSendPrediction(
    abilityId: AbilityId, 
    input: AbilityInput, 
    context: SharedAbilityContext, 
    character: Model,
    result: AbilityResult
)
    local predictionId = self:GeneratePredictionId()
    local prediction: PredictionData = {
        id = predictionId,
        timestamp = time(),
        originalState = context.characterState,
        predictedState = context.characterState,
        context = context,
        result = result,
        timeoutHandle = task.delay(PREDICTION_TIMEOUT, function()
            self:TimeoutPrediction(predictionId)
        end),
    }

    -- Update tracking
    self.pendingPredictions[predictionId] = prediction
    self.pendingByAbility[abilityId] = predictionId
    self.activePredictionId = predictionId

    -- Send to server asynchronously
    self:_sendPredictionToServer(predictionId, abilityId, input, context, context.characterState)
end

-- Helper methods for ExecuteAbility
function ClientPredictor:_applyMinimalDebounce(abilityId: AbilityId, currentTime: number)
    local key = tostring(abilityId)
    local lc = self.localCooldowns :: {[string]: number}
    local prev: number = lc[key] or 0
    lc[key] = math.max(prev, currentTime + self.defaultDebounce)
end

function ClientPredictor:_applyCooldownsFromResult(result: AbilityResult, abilityId: AbilityId, currentTime: number)
    if result.cooldowns then
        self:ApplyCooldowns(result.cooldowns)
    else
        self:_applyMinimalDebounce(abilityId, currentTime)
    end
end

function ClientPredictor:_sendPredictionToServer(
    predictionId: string, 
    abilityId: AbilityId, 
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
            -- Keep local cooldowns; they already match the module's returned values
        end

        -- onConfirm hook
        local ctx = prediction.context
        local handler = ClientAbilities.Get(ctx.abilityId)
        if handler and handler.onConfirm then
            pcall(handler.onConfirm, ctx, validationData)
        end
    else
        -- Server rejected - only rollback if there's significant desync
        warn("Server rejected ability:", validationData.reason or "Unknown reason")

        -- Optional: if server provided authoritative cooldowns, merge them to avoid spam
        if validationData.cooldowns then
            self:ApplyCooldowns(validationData.cooldowns)
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

        -- onReject hook
        local ctx = prediction.context
        local handler = ClientAbilities.Get(ctx.abilityId)
        if handler and handler.onReject then
            pcall(handler.onReject, ctx, validationData and validationData.reason)
        end
    end

    -- Clean up
    self.pendingPredictions[predictionId] = nil
    -- Clear per-ability pending slot
    if prediction and prediction.context then
        local aId: AbilityId = prediction.context.abilityId :: AbilityId
        if self.pendingByAbility[aId] == predictionId then
            self.pendingByAbility[aId] = nil
        end
    end
    -- Release global lock if this was the active
    if self.activePredictionId == predictionId then
        self.activePredictionId = nil
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
    local handler = ClientAbilities.Get(ctx.abilityId)
    if handler and handler.onTimeout then
        pcall(handler.onTimeout, ctx)
    end

    self.pendingPredictions[predictionId] = nil
    -- Clear per-ability pending slot
    local aId: AbilityId = prediction.context.abilityId :: AbilityId
    if self.pendingByAbility[aId] == predictionId then
        self.pendingByAbility[aId] = nil
    end
    -- Release global lock if this was the active
    if self.activePredictionId == predictionId then
        self.activePredictionId = nil
    end
end

function ClientPredictor:RollbackPrediction(prediction: any)
    -- Only rollback to original state if explicitly needed
    -- This should rarely be called now since ApplyServerCorrection handles most cases

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

-- Optimized Hold Loop System with better performance and validation
function ClientPredictor:StartHoldLoop(abilityId: AbilityId)
    if self.holdTasks[abilityId] ~= nil then
        return
    end
    
    self.holdFlags[abilityId] = true

    self.holdTasks[abilityId] = task.spawn(function()
        local lastExecutionTime = 0
        local abilityHandler = ClientAbilities.Get(abilityId)
        
        -- Cache ability properties for performance
        local abilityCooldown = abilityHandler and abilityHandler.getAbilityCooldown and abilityHandler.getAbilityCooldown() or 1
        local minWaitTime = math.min(HOLD_LOOP_MIN_WAIT, abilityCooldown * 0.1)
        
        while self.holdFlags[abilityId] do
            local currentTime = Utils.now()
            local timeSinceLastExecution = currentTime - lastExecutionTime
            
            -- Check if we should attempt execution
            local shouldExecute = self.activePredictionId == nil 
                and self:GetCooldownRemaining(abilityId) <= 0
                and timeSinceLastExecution >= minWaitTime
            
            if shouldExecute then
                local character: Model? = self.player.Character
                if not character then break end

                local inputData = self:_getMouseInputData(character)
                if inputData then
                    local success = self:ExecuteAbility(abilityId, inputData)
                    if success then
                        lastExecutionTime = currentTime
                    end
                end
            end

            -- Calculate adaptive wait time based on ability state
            local cooldownRemaining = self:GetCooldownRemaining(abilityId)
            local waitTime = if cooldownRemaining > 0 
                then math.min(cooldownRemaining * 0.8, HOLD_LOOP_MAX_WAIT)  -- Wait for 80% of cooldown
                else minWaitTime
            
            task.wait(waitTime)
        end
        self.holdTasks[abilityId] = nil
    end)
end

function ClientPredictor:StopHoldLoop(abilityId: AbilityId)
    self.holdFlags[abilityId] = false
    -- Let the loop naturally exit to avoid mid-frame issues
end

-- Enhanced mouse input data with validation
function ClientPredictor:_getMouseInputData(character: Model): AbilityInput?
    local mouse = self.player:GetMouse()
    if not mouse then return nil end
    
    local pivotCF = character:GetPivot()
    local mouseHit = mouse.Hit
    
    if not mouseHit then return nil end
    
    return {
        direction = pivotCF.LookVector,
        target = mouseHit.Position,
        mouseHit = mouseHit.Position,
    }
end

-- Optimized Input Handling System with caching and reduced lookups
function ClientPredictor:SetupInputHandling()
    -- Pre-cache handler functions for better performance
    local function createHoldHandler(handlerType: string)
        return function(abilityId: AbilityId)
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

    -- Cache commonly accessed values
    local player = self.player
    local getAbilityByInput = ClientAbilities.GetAbilityByInputValue

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        local character = player.Character
        if not character then return end

        -- Fast enum determination
        local queryEnum: EnumItem = if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2
            or input.UserInputType == Enum.UserInputType.MouseButton3
            then input.UserInputType
            else input.KeyCode

        local abilityId = getAbilityByInput(queryEnum)
        if not abilityId then return end

        -- Handle mouse buttons with optimized hold loops
        local holdHandler = inputBeganHandlers[input.UserInputType]
        if holdHandler then
            holdHandler(abilityId)
            return
        end

        -- Handle keyboard inputs with early exit conditions
        if self.activePredictionId ~= nil or self:GetCooldownRemaining(abilityId) > 0 then
            return
        end

        -- Only create input data if we're going to use it
        local inputData = self:_getMouseInputData(character)
        if inputData then
            self:ExecuteAbility(abilityId, inputData)
        end
    end)

    UserInputService.InputEnded:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        local endHandler = inputEndedHandlers[input.UserInputType]
        if not endHandler then return end

        local abilityId = getAbilityByInput(input.UserInputType)
        if abilityId then
            endHandler(abilityId)
        end
    end)
end

-- Optimized Performance Monitoring and Cleanup
function ClientPredictor:StartPerformanceMonitoring()
    task.spawn(function()
        while true do
            task.wait(PERFORMANCE_CHECK_INTERVAL)

            local pendingCount = 0
            local oldestPrediction = math.huge
            local stalePredictions = {}

            -- Single pass through predictions for efficiency
            for id, prediction in pairs(self.pendingPredictions) do
                pendingCount += 1
                local age = time() - prediction.timestamp
                oldestPrediction = math.min(oldestPrediction, prediction.timestamp)
                
                if age > PREDICTION_TIMEOUT then
                    table.insert(stalePredictions, id)
                end
            end

            -- Clean up stale predictions
            for _, id in stalePredictions do
                self:TimeoutPrediction(id)
            end

            -- Optional performance logging (only when there are issues)
            if pendingCount > 3 or oldestPrediction < math.huge and (time() - oldestPrediction) > 3 then
                local oldestAge = if oldestPrediction < math.huge then time() - oldestPrediction else 0
                warn(`Performance: {pendingCount} predictions pending, oldest: {math.floor(oldestAge * 100) / 100}s`)
            end
        end
    end)
end

-- Scalable Ability Registration System
function ClientPredictor:GetRegisteredAbilities(): {[string]: string}
    local abilities = {}
    
    -- Dynamically discover abilities from the ClientAbilities module
    -- This makes the system more scalable
    for abilityId in pairs(ClientAbilities._modules or {}) do
        local handler = ClientAbilities.Get(abilityId)
        if handler and handler.getAbilityInputRequired then
            local inputType = handler.getAbilityInputRequired()
            local inputName = if typeof(inputType) == "EnumItem" then inputType.Name else tostring(inputType)
            abilities[tostring(abilityId)] = inputName
        end
    end
    
    return abilities
end

function ClientPredictor:PrintControls()
    print("Client ability predictor initialized (ClientAbilities)")
    print("Controls:")
    
    local abilities = self:GetRegisteredAbilities()
    for abilityId, inputName in pairs(abilities) do
        print(`{inputName} - {abilityId}`)
    end
    
    if next(abilities) == nil then
        print("No abilities registered")
    end
end

-- Initialize the system
local predictor = ClientPredictor.new()
predictor:SetupInputHandling()
predictor:StartPerformanceMonitoring()
predictor:PrintControls()

return predictor
