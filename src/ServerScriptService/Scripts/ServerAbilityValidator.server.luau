--!strict
-- Server-side ability validation for client predictions
-- SOLID Principles: Open/Closed, Liskov Substitution, Dependency Inversion
-- ACID Properties: Consistency, Isolation, Durability

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientAbilityTypes = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

type AbilityId = string
type StateSnapshot = ClientAbilityTypes.StateSnapshot
type AbilityResult = ClientAbilityTypes.AbilityResult
type SharedAbilityContext = ClientAbilityTypes.SharedAbilityContext
type ClientAbilityModule = ClientAbilityTypes.ClientAbilityModule

-- Server-specific types
type PredictionRequest = {
    predictionId: string,
    abilityId: AbilityId,
    inputData: {[string]: any},
    timestamp: number,
    originalState: StateSnapshot,
}

type ValidationResult = {
    predictionId: string,
    success: boolean,
    reason: string?,
    correctedState: StateSnapshot?,
    authorizedEffects: {[string]: any}?,
}

-- Constants and utilities
local Constants = {
    POSITION_TOLERANCE_BASE = 5.0, -- studs
    VELOCITY_TOLERANCE = 10.0, -- studs/s
    TIME_TOLERANCE = 0.5, -- s (max future skew)
    MAX_POSITION_DESYNC = 20.0, -- studs (hard ceiling)
    RATE_LIMIT_TOKENS_PER_SEC = 10, -- abilities per second
    RATE_LIMIT_BUCKET_SIZE = 10, -- burst size
}

local function now(): number
    -- Prefer server time for determinism; fallback to tick for compatibility
    return workspace:GetServerTimeNow()
end

local function isFinite(n: number?): boolean
    if n == nil then return false end
    -- In Luau, check against infinities/NaN by comparisons
    if n ~= n then return false end -- NaN
    if n == math.huge or n == -math.huge then return false end
    return true
end

local function isFiniteVector3(v: Vector3?): boolean
    if v == nil then return false end
    return isFinite(v.X) and isFinite(v.Y) and isFinite(v.Z)
end

local function shallowClone<T>(t: T): T
    -- table.clone may error on nil; handle safely
    if t == nil then
        return ({} :: any) :: T
    end
    local ok, cloned = pcall(function()
        return table.clone(t :: any)
    end)
    if ok then
        return (cloned :: any) :: T
    end
    return (t :: any) :: T
end

-- Interface for server state management (Dependency Inversion)
local IServerStateManager = {}
function IServerStateManager:GetPlayerState(player: Player): StateSnapshot
    error("Must implement GetPlayerState")
end
function IServerStateManager:ApplyState(player: Player, state: StateSnapshot): ()
    error("Must implement ApplyState")
end
function IServerStateManager:ValidateState(clientState: StateSnapshot, serverState: StateSnapshot): boolean
    error("Must implement ValidateState")
end

-- Server State Manager Implementation
local ServerStateManager = {}
ServerStateManager.__index = ServerStateManager

function ServerStateManager.new()
    local self = setmetatable({}, ServerStateManager)
    self.playerStates = {} :: {[Player]: StateSnapshot}
    
    -- Initialize player states when they join
    Players.PlayerAdded:Connect(function(player)
        self:InitializePlayerState(player)
    end)
    
    Players.PlayerRemoving:Connect(function(player)
        self.playerStates[player] = nil
    end)
    
    return self
end

function ServerStateManager:InitializePlayerState(player: Player)
    local state: StateSnapshot = {
        timestamp = now(),
        position = Vector3.new(0, 0, 0),
        velocity = Vector3.new(0, 0, 0),
        health = 100,
        stamina = 100,
        cooldowns = {},
        effects = {},
    }
    self.playerStates[player] = state
    return state
end

function ServerStateManager:GetPlayerState(player: Player): StateSnapshot
    local character = player.Character
    if not character or not character.PrimaryPart then
        return self.playerStates[player] or self:InitializePlayerState(player)
    end
    
    local rootPart = character.PrimaryPart
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    
    -- Get current authoritative state
    local state: StateSnapshot = {
        timestamp = now(),
        position = rootPart.Position,
        velocity = rootPart.AssemblyLinearVelocity,
        health = humanoid and humanoid.Health or 100,
        stamina = self.playerStates[player] and self.playerStates[player].stamina or 100,
        cooldowns = shallowClone(self.playerStates[player] and self.playerStates[player].cooldowns or {}),
        effects = shallowClone(self.playerStates[player] and self.playerStates[player].effects or {}),
    }
    
    self.playerStates[player] = state
    return state
end

function ServerStateManager:ApplyState(player: Player, state: StateSnapshot): ()
    local character = player.Character
    if not character or not character.PrimaryPart then
        return
    end
    
    local rootPart = character.PrimaryPart
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    
    -- Apply authoritative state
    if isFiniteVector3(state.position) then
        -- Avoid forcing physics on anchored parts
        if character.PrimaryPart and not rootPart.Anchored then
            -- PivotTo is safer for models
            character:PivotTo(CFrame.new(state.position :: Vector3))
        else
            rootPart.CFrame = CFrame.new(state.position :: Vector3)
        end
    end
    
    if isFiniteVector3(state.velocity) then
        rootPart.AssemblyLinearVelocity = state.velocity :: Vector3
    end
    
    if state.health and humanoid then
        humanoid.Health = state.health
    end
    
    -- Update server state cache
    self.playerStates[player] = shallowClone(state)
end

function ServerStateManager:ValidateState(clientState: StateSnapshot, serverState: StateSnapshot): boolean
    -- Validate client state against server state
    -- Allow some tolerance for network delay and prediction differences
    local clientTs = clientState.timestamp or 0
    local serverTs = serverState.timestamp or now()

    -- Check timestamp (prevent future predictions)
    if clientTs > serverTs + Constants.TIME_TOLERANCE then
        return false
    end
    
    -- Check position reasonableness
    if isFiniteVector3(clientState.position) and isFiniteVector3(serverState.position) then
        local distance = (clientState.position :: Vector3 - serverState.position :: Vector3).Magnitude
        -- Increase tolerance with time delta
        local dt = math.max(0, serverTs - clientTs)
        local dynamicTolerance = Constants.POSITION_TOLERANCE_BASE + Constants.VELOCITY_TOLERANCE * dt
        if distance > math.max(dynamicTolerance, Constants.MAX_POSITION_DESYNC) then
            return false
        end
    end
    
    -- Check velocity reasonableness
    if isFiniteVector3(clientState.velocity) and isFiniteVector3(serverState.velocity) then
        local velocityDiff = (clientState.velocity :: Vector3 - serverState.velocity :: Vector3).Magnitude
        if velocityDiff > Constants.VELOCITY_TOLERANCE then
            return false
        end
    end
    
    return true
end

-- Anti-cheat validator (Single Responsibility)
local AntiCheatValidator = {}
AntiCheatValidator.__index = AntiCheatValidator

function AntiCheatValidator.new()
    local self = setmetatable({}, AntiCheatValidator)
    self.playerCooldowns = {} :: {[Player]: {[AbilityId]: number}}
    -- Token bucket per player+ability for rate limiting
    self.rateLimit = {} :: {[Player]: {[AbilityId]: { tokens: number, lastRefill: number }}}
    return self
end

function AntiCheatValidator:ValidateRequest(player: Player, request: PredictionRequest): (boolean, string?)
    -- Rate limiting
    if not self:CheckRateLimit(player, request.abilityId) then
        return false, "Rate limit exceeded"
    end
    
    -- Cooldown validation
    if not self:ValidateCooldown(player, request.abilityId, request.timestamp) then
        return false, "Ability on cooldown"
    end
    
    -- Physics validation
    if not self:ValidatePhysics(player, request) then
        return false, "Invalid physics state"
    end
    
    return true
end

function AntiCheatValidator:CheckRateLimit(player: Player, abilityId: AbilityId): boolean
    local buckets = self.rateLimit[player]
    if not buckets then
        buckets = {}
        self.rateLimit[player] = buckets
    end
    local bucket = buckets[abilityId]
    local t = now()
    if not bucket then
        bucket = { tokens = Constants.RATE_LIMIT_BUCKET_SIZE, lastRefill = t }
        buckets[abilityId] = bucket
    end

    -- Refill tokens
    local elapsed = t - bucket.lastRefill
    if elapsed > 0 then
        local refill = elapsed * Constants.RATE_LIMIT_TOKENS_PER_SEC
        bucket.tokens = math.min(Constants.RATE_LIMIT_BUCKET_SIZE, bucket.tokens + refill)
        bucket.lastRefill = t
    end

    if bucket.tokens < 1 then
        return false
    end
    bucket.tokens = bucket.tokens - 1
    return true
end

function AntiCheatValidator:ValidateCooldown(player: Player, abilityId: AbilityId, timestamp: number): boolean
    local cooldowns = self.playerCooldowns[player] or {}
    local cooldownEnd = cooldowns[abilityId] or 0
    
    return timestamp >= cooldownEnd
end

function AntiCheatValidator:ValidatePhysics(player: Player, request: PredictionRequest): boolean
    local character = player.Character
    if not character or not character.PrimaryPart then
        return false
    end
    
    -- Basic physics validation
    local root = character.PrimaryPart
    local currentPos = root.Position
    local requestedPos = request.originalState and request.originalState.position

    if isFiniteVector3(requestedPos) then
        local distance = (currentPos - (requestedPos :: Vector3)).Magnitude
        -- Allow reasonable distance variance (accounting for network lag and speed)
        local dt = math.max(0, now() - (request.timestamp or now()))
        local speed = root.AssemblyLinearVelocity.Magnitude
        local allowed = Constants.POSITION_TOLERANCE_BASE + speed * dt + 5 -- +5 studs fudge
        if distance > math.max(allowed, Constants.MAX_POSITION_DESYNC) then
            return false
        end
    end

    return true
end

function AntiCheatValidator:UpdateCooldown(player: Player, abilityId: AbilityId, cooldownEnd: number)
    self.playerCooldowns[player] = self.playerCooldowns[player] or {}
    self.playerCooldowns[player][abilityId] = cooldownEnd
end

-- Main Server Validation System
local ServerAbilityValidator = {}
ServerAbilityValidator.__index = ServerAbilityValidator

function ServerAbilityValidator.new()
    local self = setmetatable({}, ServerAbilityValidator)
    
    self.stateManager = ServerStateManager.new()
    self.antiCheat = AntiCheatValidator.new()
    -- self.pendingValidations reserved for future reconciliation flows
    
    -- Network setup
    local function getOrCreateRemote(folder: Instance, name: string): Instance
        local inst = folder:FindFirstChild(name)
        if not inst then
            local newRemote = Instance.new("RemoteEvent")
            newRemote.Name = name
            newRemote.Parent = folder
            inst = newRemote
        end
        return inst :: Instance
    end

    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remoteFolder then
        local newFolder = Instance.new("Folder")
        newFolder.Name = "Remotes"
        newFolder.Parent = ReplicatedStorage
        remoteFolder = newFolder
    end

    local remotesFolder = remoteFolder :: Folder
    self.predictionRemote = getOrCreateRemote(remotesFolder, "AbilityPrediction") :: RemoteEvent
    self.validationRemote = getOrCreateRemote(remotesFolder, "AbilityValidation") :: RemoteEvent
    
    -- Listen for client predictions
    self.predictionRemote.OnServerEvent:Connect(function(player, requestData)
        self:HandlePredictionRequest(player, requestData)
    end)
    
    return self
end

function ServerAbilityValidator:HandlePredictionRequest(player: Player, requestData: any)
    -- Basic schema validation/sanitization
    if type(requestData) ~= "table" then
        return self:SendValidationResult(player, { predictionId = "", success = false, reason = "Invalid request" })
    end

    local predictionId = tostring(requestData.predictionId or "")
    local abilityId = tostring(requestData.abilityId or "") :: AbilityId
    local inputData = (type(requestData.inputData) == "table") and requestData.inputData or {}
    local timestamp = (type(requestData.timestamp) == "number") and requestData.timestamp or now()
    local originalState: StateSnapshot = requestData.originalState or self.stateManager:GetPlayerState(player)

    local request: PredictionRequest = {
        predictionId = predictionId,
        abilityId = abilityId,
        inputData = inputData,
        timestamp = timestamp,
        originalState = originalState,
    }
    
    -- Validate request
    local validRequest, reason = self.antiCheat:ValidateRequest(player, request)
    if not validRequest then
        self:SendValidationResult(player, {
            predictionId = request.predictionId,
            success = false,
            reason = reason,
        })
        return
    end
    
    -- Get current server state
    local serverState = self.stateManager:GetPlayerState(player)
    
    -- Validate client state against server state
    if not self.stateManager:ValidateState(request.originalState, serverState) then
        self:SendValidationResult(player, {
            predictionId = request.predictionId,
            success = false,
            reason = "State desync detected",
            correctedState = serverState,
        })
        return
    end
    
    -- Execute ability on server
    local context: SharedAbilityContext = {
        playerId = player.UserId,
    abilityId = (request.abilityId :: any),
        timestamp = now(),
        inputData = {
            position = serverState.position,
            direction = inputData.direction,
            target = inputData.target,
            mouseHit = inputData.mouseHit,
            extraData = inputData.extraData,
        },
        characterState = serverState,
    }
    
    -- Execute server per-ability module
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local clientAbilities = modules and modules:FindFirstChild("ClientAbilities")
    local mod = clientAbilities and clientAbilities:FindFirstChild(tostring(request.abilityId))
    local result: AbilityResult
    if mod and mod:IsA("ModuleScript") then
        local ok, moduleOrErr = pcall(require, mod)
        if ok and type(moduleOrErr) == "table" and type(moduleOrErr.onRequest) == "function" then
            local abilityMod = moduleOrErr :: ClientAbilityModule
            local success, res = pcall(function()
                return abilityMod.onRequest(context)
            end)
            if success and type(res) == "table" and (res :: AbilityResult).success ~= nil then
                result = res
            else
                result = { success = false, reason = "Ability execution error" }
            end
        else
            result = { success = false, reason = "Invalid ability module" }
        end
    else
        result = { success = false, reason = "Ability not found" }
    end
    
    if result.success then
        -- Apply cooldowns only
        if result.cooldowns then
            local newState = shallowClone(serverState)
            local cd = newState.cooldowns or {} :: {[string]: number}
            newState.cooldowns = cd
            for cooldownAbilityId, cooldownTime in pairs(result.cooldowns) do
                if type(cooldownTime) == "number" and cooldownTime >= now() then
                    cd[cooldownAbilityId] = cooldownTime
                    if self.antiCheat and self.antiCheat.UpdateCooldown then
                        self.antiCheat:UpdateCooldown(player, cooldownAbilityId :: AbilityId, cooldownTime)
                    end
                end
            end
            self.stateManager:ApplyState(player, newState)
            -- Send confirmation
            self:SendValidationResult(player, {
                predictionId = request.predictionId,
                success = true,
                correctedState = newState,
                authorizedEffects = nil,
            })
        else
            self:SendValidationResult(player, { predictionId = request.predictionId, success = true })
        end
    else
        -- Send rejection
        self:SendValidationResult(player, {
            predictionId = request.predictionId,
            success = false,
            reason = result.reason,
            correctedState = serverState,
        })
    end
end

function ServerAbilityValidator:SendValidationResult(player: Player, result: ValidationResult)
    self.validationRemote:FireClient(player, result)
end

-- Global instance
local globalValidator = ServerAbilityValidator.new()

return globalValidator
