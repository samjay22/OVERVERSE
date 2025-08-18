--!strict

local Players = game:GetService("Players")

local Utils = require(script.Parent.Parent.Utils)
local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)

type StateSnapshot = Types.StateSnapshot

local ServerStateManager = {}
ServerStateManager.__index = ServerStateManager

function ServerStateManager.new()
    local self = setmetatable({}, ServerStateManager)
    self.playerStates = {} :: {[Player]: StateSnapshot}

    Players.PlayerAdded:Connect(function(player)
        self:InitializePlayerState(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        self.playerStates[player] = nil
    end)

    return self
end

function ServerStateManager:InitializePlayerState(player: Player): StateSnapshot
    local state: StateSnapshot = {
        timestamp = Utils.now(),
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

    local prev = self.playerStates[player]
    local state: StateSnapshot = {
        timestamp = Utils.now(),
        position = rootPart.Position,
        velocity = rootPart.AssemblyLinearVelocity,
        health = humanoid and humanoid.Health or 100,
        stamina = prev and prev.stamina or 100,
        cooldowns = Utils.shallowClone(prev and prev.cooldowns or {}),
        effects = Utils.shallowClone(prev and prev.effects or {}),
    }

    self.playerStates[player] = state
    return state
end

function ServerStateManager:ApplyState(player: Player, state: StateSnapshot, opts: { applyTransform: boolean? }?): ()
    local character = player.Character
    if not character or not character.PrimaryPart then
        self.playerStates[player] = Utils.shallowClone(state)
        return
    end

    local rootPart = character.PrimaryPart
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local applyTransform = (opts and opts.applyTransform) == true

    if applyTransform then
        if Utils.isFiniteVector3(state.position) then
            if not rootPart.Anchored then
                character:PivotTo(CFrame.new(state.position :: Vector3))
            else
                rootPart.CFrame = CFrame.new(state.position :: Vector3)
            end
        end
        if Utils.isFiniteVector3(state.velocity) then
            rootPart.AssemblyLinearVelocity = state.velocity :: Vector3
        end
    end

    if state.health and humanoid then
        humanoid.Health = state.health
    end

    self.playerStates[player] = Utils.shallowClone(state)
end

function ServerStateManager:ValidateState(clientState: StateSnapshot, serverState: StateSnapshot): boolean
    local clientTs = clientState.timestamp or 0
    local serverTs = serverState.timestamp or Utils.now()

    if clientTs > serverTs + Constants.TIME_TOLERANCE then
        return false
    end

    if Utils.isFiniteVector3(clientState.position) and Utils.isFiniteVector3(serverState.position) then
        local distance = (clientState.position :: Vector3 - serverState.position :: Vector3).Magnitude
        local dt = math.max(0, serverTs - clientTs)
        local allowed = Constants.AllowedPositionDesync(Constants.VELOCITY_TOLERANCE, dt)
        if distance > allowed then
            return false
        end
    end

    if Utils.isFiniteVector3(clientState.velocity) and Utils.isFiniteVector3(serverState.velocity) then
        local velocityDiff = (clientState.velocity :: Vector3 - serverState.velocity :: Vector3).Magnitude
        if velocityDiff > Constants.VELOCITY_TOLERANCE then
            return false
        end
    end

    return true
end

return ServerStateManager
