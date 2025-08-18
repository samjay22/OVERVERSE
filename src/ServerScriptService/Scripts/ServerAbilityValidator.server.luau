--!strict
-- Server-side ability validation orchestrator

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local AbilityValidationRoot = ServerStorage:WaitForChild("Modules"):WaitForChild("AbilityValidation")
local Utils = require(AbilityValidationRoot:WaitForChild("Utils"))
local Types = require(AbilityValidationRoot:WaitForChild("Types"))
local ServerStateManager = require(AbilityValidationRoot:WaitForChild("State"):WaitForChild("ServerStateManager"))
local AntiCheatValidator = require(AbilityValidationRoot:WaitForChild("AntiCheat"):WaitForChild("AntiCheatValidator"))
local Remotes = require(AbilityValidationRoot:WaitForChild("Network"):WaitForChild("Remotes"))

type AbilityId = Types.AbilityId
type StateSnapshot = Types.StateSnapshot
type AbilityResult = Types.AbilityResult
type SharedAbilityContext = Types.SharedAbilityContext
type ClientAbilityModule = Types.ClientAbilityModule
type PredictionRequest = Types.PredictionRequest
type ValidationResult = Types.ValidationResult

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

function ServerAbilityValidator:HandlePredictionRequest(player: Player, requestData: any)
    if type(requestData) ~= "table" then
        return self:SendValidationResult(player, { predictionId = "", success = false, reason = "Invalid request" })
    end

    local predictionId = tostring(requestData.predictionId or "")
    local abilityId = tostring(requestData.abilityId or "") :: AbilityId
    local inputData = (type(requestData.inputData) == "table") and requestData.inputData or {}
    local timestamp = (type(requestData.timestamp) == "number") and requestData.timestamp or Utils.now()
    local originalState: StateSnapshot = requestData.originalState or self.stateManager:GetPlayerState(player)

    local request: PredictionRequest = {
        predictionId = predictionId,
        abilityId = abilityId,
        inputData = inputData,
        timestamp = timestamp,
        originalState = originalState,
    }

    local okRequest, reason = self.antiCheat:ValidateRequest(player, request)
    if not okRequest then
        return self:SendValidationResult(player, {
            predictionId = request.predictionId,
            success = false,
            reason = reason,
        })
    end

    local serverState = self.stateManager:GetPlayerState(player)

    if not self.stateManager:ValidateState(request.originalState, serverState) then
        return self:SendValidationResult(player, {
            predictionId = request.predictionId,
            success = false,
            reason = "State desync detected",
            correctedState = serverState,
        })
    end

    local context: SharedAbilityContext = {
        playerId = player.UserId,
        abilityId = (request.abilityId :: any),
        timestamp = Utils.now(),
        inputData = {
            position = serverState.position,
            direction = inputData.direction,
            target = inputData.target,
            mouseHit = inputData.mouseHit,
            extraData = inputData.extraData,
        },
        characterState = serverState,
    }

    local result: AbilityResult = { success = false, reason = "Ability not found" }

    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local clientAbilities = modules and modules:FindFirstChild("ClientAbilities")
    local mod = clientAbilities and clientAbilities:FindFirstChild(tostring(request.abilityId))

    if mod and mod:IsA("ModuleScript") then
        local ok, moduleOrErr = Utils.safeRequire(mod)
        if ok and type(moduleOrErr) == "table" and type(moduleOrErr.onRequest) == "function" then
            local onRequestFn = (moduleOrErr :: ClientAbilityModule).onRequest :: (SharedAbilityContext) -> AbilityResult
            local success, res = pcall(function()
                return onRequestFn(context)
            end)
            if success and type(res) == "table" and (res :: AbilityResult).success ~= nil then
                result = res
            else
                result = { success = false, reason = "Ability execution error" }
            end
        else
            result = { success = false, reason = "Invalid ability module" }
        end
    end

    if result.success then
        if result.cooldowns then
            local newState = Utils.shallowClone(serverState)
            local cd = newState.cooldowns or {} :: {[string]: number}
            newState.cooldowns = cd
            local nowTs = Utils.now()
            for cooldownAbilityId, cooldownTime in pairs(result.cooldowns) do
                if type(cooldownTime) == "number" and cooldownTime >= nowTs then
                    cd[cooldownAbilityId] = cooldownTime
                    self.antiCheat:UpdateCooldown(player, cooldownAbilityId :: AbilityId, cooldownTime)
                end
            end
            self.stateManager:ApplyState(player, newState, { applyTransform = false })

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
        self:SendValidationResult(player, {
            predictionId = request.predictionId,
            success = false,
            reason = result.reason,
            correctedState = serverState,
        })
    end
end

local globalValidator = ServerAbilityValidator.new()
return globalValidator
