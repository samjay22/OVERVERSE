--!strict
-- Client Ability Predictor using per-ability ClientAbilities modules
-- Instant local response with server validation and rollback (PivotTo-based)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local _require: any = require
local ClientAbilities = _require(ReplicatedStorage.Modules.ClientAbilities)

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)
type AbilityId = Types.AbilityId
type StateSnapshot = Types.StateSnapshot
type SharedAbilityContext = Types.SharedAbilityContext
type AbilityResult = Types.AbilityResult

-- Client Prediction Manager
local ClientPredictor = {}
ClientPredictor.__index = ClientPredictor

type SmoothState = {
    active: boolean,
    startCF: CFrame?,
    targetCF: CFrame?,
    startTime: number,
    duration: number,
    startVel: Vector3?,
    targetVel: Vector3?,
}

local function now(): number
    return workspace:GetServerTimeNow()
end

local function shallowClone<T>(t: {[any]: T}?): {[any]: T}
    local r: {[any]: T} = {}
    if t then
        for k, v in pairs(t) do
            r[k] = v
        end
    end
    return r
end

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

local function getCharacterRootPart(character: Model?): BasePart?
    if not character then return nil end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then
        return hrp
    end
    return character.PrimaryPart
end

-- Local debounce helpers
function ClientPredictor:GetCooldownRemaining(abilityId: AbilityId, t: number?): number
    local key = tostring(abilityId)
    local lc = self.localCooldowns :: {[string]: number}
    local untilTs: number? = lc[key]
    local current = t or now()
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
function ClientPredictor:ExecuteAbility(abilityId: AbilityId, input: AbilityInput): boolean
    -- Serialize entry to avoid race conditions starting multiple abilities at once
    if not self:_tryAcquireImmediate() then
        return false
    end

    -- Enforce only one ability at a time globally
    if self.activePredictionId ~= nil then
        self:_releaseImmediate()
        return false
    end

    -- Throttle: avoid multiple concurrent predictions of the same ability
    local existing = self.pendingByAbility[abilityId]
    if existing ~= nil then
        self:_releaseImmediate()
        return false
    end

    local tNow = now()

    -- Local debounce check
    if self:GetCooldownRemaining(abilityId, tNow) > 0 then
        self:_releaseImmediate()
        return false
    end

    -- Step 1: Build current state snapshot (from pivot)
    local character: Model? = self.player.Character
    local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
    local root: BasePart? = getCharacterRootPart(character)
    local pivotCF: CFrame? = character and character:GetPivot() or nil

    -- Provide local cooldowns to the module's onRequest so it can enforce client-side CD
    local cooldownsClone = shallowClone(self.localCooldowns)

    local originalState: StateSnapshot = {
        timestamp = tNow,
        position = pivotCF and pivotCF.Position or (root and root.Position or Vector3.new()),
        velocity = root and root.AssemblyLinearVelocity or Vector3.new(),
        health = humanoid and humanoid.Health or 100,
        stamina = 100,
        cooldowns = cooldownsClone, -- let onRequest consult these
        effects = {},
    }

    local context: SharedAbilityContext = {
        playerId = self.player.UserId,
        abilityId = abilityId,
        timestamp = tNow,
        inputData = {
            position = originalState.position,
            direction = input.direction,
            target = input.target,
            mouseHit = input.mouseHit,
            extraData = input.extraData,
        },
        characterState = originalState,
    }

    -- Step 2: Execute local visuals immediately (only if not on cooldown)
    local handler = ClientAbilities.Get(abilityId)
    if handler and handler.onCast then
        pcall(handler.onCast, context)
    end

    -- Step 3: Ask the client module to validate request and return cooldowns
    local result: AbilityResult =
        (handler and handler.onRequest and (handler.onRequest :: any)(context))
        or { success = false, reason = "No client module" }

    if not result.success then
        -- Optional short tap debounce to prevent spam click floods
        local key = tostring(abilityId)
    local lc = self.localCooldowns :: {[string]: number}
    local prev: number = lc[key] or 0
    lc[key] = math.max(prev, tNow + self.defaultDebounce)
        warn("Ability failed:", result.reason)
    self:_releaseImmediate()
        return false
    end

    -- Apply returned cooldowns to local debounce immediately
    if result.cooldowns then
        self:ApplyCooldowns(result.cooldowns)
    else
        -- Fallback: apply a minimal debounce
        local key = tostring(abilityId)
    local lc = self.localCooldowns :: {[string]: number}
    local prev: number = lc[key] or 0
    lc[key] = math.max(prev, tNow + self.defaultDebounce)
    end

    -- Step 4: Send to server for validation
    local predictionId = self:GeneratePredictionId()
    local prediction = {
        id = predictionId,
        timestamp = time(),
        originalState = originalState,
        predictedState = originalState,
        context = context,
        result = result,
        timeoutHandle = task.delay(5.0, function()
            self:TimeoutPrediction(predictionId)
        end),
    }

    self.pendingPredictions[predictionId] = prediction
    self.pendingByAbility[abilityId] = predictionId
    self.activePredictionId = predictionId -- lock globally
    -- Release immediate lock; global lock is now active for the duration of this prediction
    self:_releaseImmediate()

    -- Send to server (non-blocking)
    task.spawn(function()
        self.predictionRemote:FireServer({
            predictionId = predictionId,
            abilityId = abilityId,
            inputData = input,
            timestamp = context.timestamp,
            originalState = originalState,
        })
    end)

    return true
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

-- Hold helpers for Mouse1/Mouse2 abilities
function ClientPredictor:StartHoldLoop(abilityId: AbilityId)
    if self.holdTasks[abilityId] ~= nil then
        return
    end
    self.holdFlags[abilityId] = true

    self.holdTasks[abilityId] = task.spawn(function()
        while self.holdFlags[abilityId] do
            -- Try to fire when: no active ability globally and no local cooldown
            if self.activePredictionId == nil and self:GetCooldownRemaining(abilityId) <= 0 then
                local character: Model? = self.player.Character
                if not character then break end

                local mouse = self.player:GetMouse()
                local pivotCF = character:GetPivot()
                local direction = pivotCF.LookVector
                local mousePos = mouse.Hit.Position

                self:ExecuteAbility(abilityId, {
                    direction = direction,
                    target = mousePos,
                    mouseHit = mousePos,
                })

                -- Wait roughly until cooldown is up to avoid busy loop
                local rem = self:GetCooldownRemaining(abilityId)
                if rem > 0 then
                    task.wait(math.min(rem, 0.25))
                else
                    task.wait(0.05)
                end
            else
                -- Back off while locked or cooling down
                local rem = self:GetCooldownRemaining(abilityId)
                if rem > 0 then
                    task.wait(math.min(rem, 0.25))
                else
                    task.wait(0.05)
                end
            end
        end
        self.holdTasks[abilityId] = nil
    end)
end

function ClientPredictor:StopHoldLoop(abilityId: AbilityId)
    self.holdFlags[abilityId] = false
    local t = self.holdTasks[abilityId]
    if t then
        -- Let the loop naturally exit; avoid task.cancel to prevent mid-frame issues
        -- It will nil out holdTasks on exit
    end
end

-- Input handling with all abilities
function ClientPredictor:SetupInputHandling()
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        local character: Model? = self.player.Character
        if not character then return end

        local mouse = self.player:GetMouse()
        local pivotCF = character:GetPivot()
        local direction = pivotCF.LookVector
        local mousePos = mouse.Hit.Position

        -- Determine the correct enum to query (KeyCode for keyboard, UserInputType for mouse)
        local queryEnum: EnumItem
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2
            or input.UserInputType == Enum.UserInputType.MouseButton3 then
            queryEnum = input.UserInputType
        else
            queryEnum = input.KeyCode
        end

        local abilityId: AbilityId? = ClientAbilities.GetAbilityByInputValue(queryEnum)
        if not abilityId then
            return
        end

        -- If Mouse1/Mouse2, start hold loop (it will fire immediately if possible)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2 then
            self:StartHoldLoop(abilityId :: AbilityId)
            return
        end

        -- Keyboard (or other) single-fire: enforce global lock and cooldowns
        if self.activePredictionId ~= nil then
            return
        end
        if self:GetCooldownRemaining(abilityId :: AbilityId) > 0 then
            return
        end

        local inputData = {
            direction = direction,
            target = mousePos,
            mouseHit = mousePos,
        }
        self:ExecuteAbility(abilityId :: AbilityId, inputData)
    end)

    UserInputService.InputEnded:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        -- Stop hold loop for Mouse1/Mouse2
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2 then

            local queryEnum: EnumItem = input.UserInputType
            local abilityId: AbilityId? = ClientAbilities.GetAbilityByInputValue(queryEnum)
            if abilityId then
                self:StopHoldLoop(abilityId :: AbilityId)
            end
        end
    end)
end

-- Performance monitoring and cleanup
function ClientPredictor:StartPerformanceMonitoring()
    task.spawn(function()
        while true do
            task.wait(5)

            local pendingCount = 0
            local oldestPrediction = math.huge

            for _, prediction in pairs(self.pendingPredictions) do
                pendingCount += 1
                oldestPrediction = math.min(oldestPrediction, prediction.timestamp)
            end

            if pendingCount > 0 then
                local oldestAge = time() - oldestPrediction
                print(`Performance: {pendingCount} predictions pending, oldest: {math.floor(oldestAge * 100) / 100}s`)
                if oldestAge > 10 then
                    for id, pred in pairs(self.pendingPredictions) do
                        if time() - pred.timestamp > 10 then
                            self:TimeoutPrediction(id)
                        end
                    end
                end
            end
        end
    end)
end

-- Initialize the system
local predictor = ClientPredictor.new()
predictor:SetupInputHandling()
predictor:StartPerformanceMonitoring()

print("Client ability predictor initialized (ClientAbilities)")
print("Controls:")
print("Q - Dash (movement)")
print("E - Heal (recovery)")
print("R - Keen (damage boost)")
print("F - Block (defense)")
print("G - Parry (counter)")
print("C - Charge (attack movement)")
print("V - Slam (AOE)")
print("X - Thrust (directional attack)")

return predictor
