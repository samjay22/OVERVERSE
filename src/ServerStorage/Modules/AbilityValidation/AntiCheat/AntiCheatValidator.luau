--!strict

local Players = game:GetService("Players")

local Utils = require(script.Parent.Parent.Utils)
local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)

type AbilityId = Types.AbilityId
type PredictionRequest = Types.PredictionRequest

local AntiCheatValidator = {}
AntiCheatValidator.__index = AntiCheatValidator

function AntiCheatValidator.new()
    local self = setmetatable({}, AntiCheatValidator)
    self.playerCooldowns = {} :: {[Player]: {[AbilityId]: number}}
    self.rateLimit = {} :: {[Player]: {[AbilityId]: { tokens: number, lastRefill: number }}}

    Players.PlayerRemoving:Connect(function(player)
        self.playerCooldowns[player] = nil
        self.rateLimit[player] = nil
    end)

    return self
end

function AntiCheatValidator:ValidateRequest(player: Player, request: PredictionRequest): (boolean, string?)
    if not self:CheckRateLimit(player, request.abilityId) then
        return false, "Rate limit exceeded"
    end

    if not self:ValidateCooldown(player, request.abilityId, request.timestamp) then
        return false, "Ability on cooldown"
    end

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
    local t = Utils.now()
    if not bucket then
        bucket = { tokens = Constants.RATE_LIMIT_BUCKET_SIZE, lastRefill = t }
        buckets[abilityId] = bucket
    end

    local elapsed = t - bucket.lastRefill
    if elapsed > 0 then
        local refill = elapsed * Constants.RATE_LIMIT_TOKENS_PER_SEC
        bucket.tokens = math.min(Constants.RATE_LIMIT_BUCKET_SIZE, bucket.tokens + refill)
        bucket.lastRefill = t
    end

    if bucket.tokens < 1 then
        return false
    end
    bucket.tokens -= 1
    return true
end

function AntiCheatValidator:ValidateCooldown(player: Player, abilityId: AbilityId, clientTimestamp: number?): boolean
    local cooldowns = self.playerCooldowns[player] or {}
    local cooldownEnd = cooldowns[abilityId] or 0

    local nowT = Utils.now()
    local tol = Constants.TIME_TOLERANCE or 0

    -- Accept if either the client's sent time (plus tolerance) or the server's receive time
    -- (plus tolerance) has reached the cooldown end. This accounts for one-way latency and skew.
    local effective = math.max((clientTimestamp or 0) + tol, nowT + tol)
    return effective >= cooldownEnd
end

function AntiCheatValidator:ValidatePhysics(player: Player, request: PredictionRequest): boolean
    local character = player.Character
    if not character or not character.PrimaryPart then
        return false
    end

    local root = character.PrimaryPart
    local currentPos = root.Position
    local requestedPos = request.originalState and request.originalState.position

    if Utils.isFiniteVector3(requestedPos) then
        local nowT = Utils.now()
        local sentT = request.timestamp or nowT
        -- Include TIME_TOLERANCE to cover client->server transit time and minor clock skew.
        local dt = math.max(0, nowT - sentT) + (Constants.TIME_TOLERANCE or 0)

        local speed = root.AssemblyLinearVelocity.Magnitude
        local allowed = Constants.AllowedPositionDesync(speed, dt) + Constants.FUDGE_STUDS
        local distance = (currentPos - (requestedPos :: Vector3)).Magnitude
        if distance > allowed then
            return false
        end
    end

    return true
end

function AntiCheatValidator:UpdateCooldown(player: Player, abilityId: AbilityId, cooldownEnd: number)
    self.playerCooldowns[player] = self.playerCooldowns[player] or {}
    -- Keep cooldown monotonic so late events can't shorten it.
    local existing = self.playerCooldowns[player][abilityId] or 0
    self.playerCooldowns[player][abilityId] = math.max(existing, cooldownEnd)
end

return AntiCheatValidator
