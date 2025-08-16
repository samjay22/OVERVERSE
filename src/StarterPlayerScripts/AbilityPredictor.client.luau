--!strict
-- Client Ability Predictor using per-ability ClientAbilities modules
-- Instant local response with server validation and rollback

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

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

function ClientPredictor.new()
    local self = setmetatable({}, ClientPredictor)
    
    self.player = Players.LocalPlayer
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
    
    -- Network remotes
    self.predictionRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AbilityPrediction") :: RemoteEvent
    self.validationRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AbilityValidation") :: RemoteEvent
    
    -- Listen for server validation
    self.validationRemote.OnClientEvent:Connect(function(validationData)
        self:HandleServerValidation(validationData)
    end)
    
    return self
end

function ClientPredictor:GeneratePredictionId(): string
    self.predictionCounter = (self.predictionCounter :: number) + 1
    return `pred_{self.player.UserId}_{self.predictionCounter}_{HttpService:GenerateGUID(false)}`
end

type AbilityInput = { direction: Vector3?, target: Vector3?, mouseHit: Vector3?, extraData: {[string]: any}? }
function ClientPredictor:ExecuteAbility(abilityId: AbilityId, input: AbilityInput): boolean
    -- Throttle: avoid multiple concurrent predictions of the same ability
    local existing = self.pendingByAbility[abilityId]
    if existing ~= nil then
        -- Option: silently ignore rapid re-press; future: queue or replace
        return false
    end

    -- Step 1: Build current state snapshot
    local character = self.player.Character
    local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
    local root: BasePart? = character and character.PrimaryPart
    local now = workspace:GetServerTimeNow()
    local originalState: StateSnapshot = {
        timestamp = now,
        position = root and root.Position or Vector3.new(),
        velocity = root and root.AssemblyLinearVelocity or Vector3.new(),
        health = humanoid and humanoid.Health or 100,
        stamina = 100,
        cooldowns = {},
        effects = {},
    }

    local context: SharedAbilityContext = {
        playerId = self.player.UserId,
        abilityId = abilityId,
        timestamp = now,
        inputData = {
            position = originalState.position,
            direction = input.direction,
            target = input.target,
            mouseHit = input.mouseHit,
            extraData = input.extraData,
        },
        characterState = originalState,
    }
    
    -- Step 2: Execute prediction immediately for responsiveness via ClientAbilities
    local handler = ClientAbilities.Get(abilityId)
    local result: AbilityResult = handler and handler.onRequest and handler.onRequest(context) or { success = false, reason = "No client module" }
    
    if not result.success then
        warn("Ability failed:", result.reason)
        return false
    end
    
    -- Step 3: No client-side VFX/state here; modules can handle visuals in onCast
    
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
        -- Apply any server corrections
        if validationData.correctedState then
            local st: any = validationData.correctedState
            local character = self.player.Character
            if character and character.PrimaryPart then
                if st.position then character.PrimaryPart.Position = st.position end
                if st.velocity then character.PrimaryPart.AssemblyLinearVelocity = st.velocity end
                if st.health and character:FindFirstChildOfClass("Humanoid") then
                    (character:FindFirstChildOfClass("Humanoid") :: Humanoid).Health = st.health
                end
            end
        end
        -- onConfirm hook
        local ctx = prediction.context
        local handler = ClientAbilities.Get(ctx.abilityId)
        if handler and handler.onConfirm then
            pcall(handler.onConfirm, ctx, validationData)
        end
    else
        -- Server rejected - rollback to original state
        warn("Server rejected ability:", validationData.reason or "Unknown reason")
        self:RollbackPrediction(prediction)
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
end

function ClientPredictor:TimeoutPrediction(predictionId: string)
    local prediction = self.pendingPredictions[predictionId]
    if not prediction then
        return
    end
    
    warn("Ability prediction timed out - rolling back")
    self:RollbackPrediction(prediction)
    
    self.pendingPredictions[predictionId] = nil
    -- Clear per-ability pending slot
    local aId: AbilityId = prediction.context.abilityId :: AbilityId
    if self.pendingByAbility[aId] == predictionId then
        self.pendingByAbility[aId] = nil
    end
end

function ClientPredictor:RollbackPrediction(prediction: any)
    -- Restore original state conservatively
    local st = prediction.originalState
    local character = self.player.Character
    if character and character.PrimaryPart then
        if st.position then character.PrimaryPart.Position = st.position end
        if st.velocity then
            local v = st.velocity
            character.PrimaryPart.AssemblyLinearVelocity = Vector3.new(v.X, character.PrimaryPart.AssemblyLinearVelocity.Y, v.Z)
        end
        local h = character:FindFirstChildOfClass("Humanoid")
        if h and st.health then h.Health = st.health end
    end
end

-- Input handling with all abilities
function ClientPredictor:SetupInputHandling()
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        local character = self.player.Character
        if not character or not character.PrimaryPart then return end
        
        local mouse = self.player:GetMouse()
        local direction = character.PrimaryPart.CFrame.LookVector
        local mousePos = mouse.Hit.Position
        
    local abilityId: AbilityId? = ClientAbilities.GetAbilityByInputValue(input.KeyCode)
        if abilityId then
            local inputData = {
                direction = direction,
                target = mousePos,
                mouseHit = mousePos,
            }
            self:ExecuteAbility(abilityId, inputData)
        end
    end)
end

-- Performance monitoring and cleanup
function ClientPredictor:StartPerformanceMonitoring()
    task.spawn(function()
        while true do
            task.wait(5) -- Check every 5 seconds
            
            local pendingCount = 0
            local oldestPrediction = math.huge
            
            for _, prediction in pairs(self.pendingPredictions) do
                pendingCount += 1
                oldestPrediction = math.min(oldestPrediction, prediction.timestamp)
            end
            
            if pendingCount > 0 then
        local oldestAge = time() - oldestPrediction
                print(`Performance: {pendingCount} predictions pending, oldest: {math.floor(oldestAge * 100) / 100}s`)
                
                -- Clean up very old predictions (failsafe)
                if oldestAge > 10 then
                    for id, prediction in pairs(self.pendingPredictions) do
            if time() - prediction.timestamp > 10 then
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
