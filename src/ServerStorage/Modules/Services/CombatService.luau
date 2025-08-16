--!nonstrict
-- CombatService: centralized combat logic

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Modules.Utility.Constants)

local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)
local CombatTypes = require(game.ServerStorage.Modules.Types.CombatTypes)
local CombatEventBus = require(game.ServerStorage.Modules.Utilities.CombatEventBus)

local CombatService = {}
CombatService.__index = CombatService

function CombatService.New()
    local self = setmetatable({}, CombatService)
    self._config = {
        ATTACK_COOLDOWN = Constants.ATTACK_COOLDOWN or 0.5,
        ATTACK_STAMINA_COST = Constants.ATTACK_STAMINA_COST or 10,
        BLOCK_EFFICIENCY = Constants.BLOCK_EFFICIENCY or 0.5,
        COMBO_RESET_TIME = Constants.COMBO_RESET_TIME or 3,
        GUARD_BREAK_RECOVERY_TIME = Constants.GUARD_BREAK_RECOVERY_TIME or 2,
    }
    self._buses = {} :: {[number]: any}
    return self
end

function CombatService:Initialize(character: CharacterTypes.internalCharacter, config: CombatTypes.CombatConfig?)
    character.Components = character.Components or {}
    character.Components.Combat = character.Components.Combat or {
        LastAttackTime = 0,
        LastBlockTime = 0,
        ComboCount = 0,
        GuardBreakRecovery = 0,
    }

    if config then
        for k, v in pairs(config) do
            (self._config :: any)[k] = v
        end
    end

    local bus = self._buses[character.PlayerId]
    if not bus then
        bus = CombatEventBus.New()
        self._buses[character.PlayerId] = bus
        table.insert(character._connections, bus.AttackRequested:Connect(function(attackType)
            local ok = self:PerformAttack(character, attackType)
            bus.AttackPerformed:Fire(ok, attackType, (character.Components.Combat and character.Components.Combat.ComboCount) or 0)
        end))
        table.insert(character._connections, bus.BlockRequested:Connect(function(shouldBlock)
            local ok = self:PerformBlock(character, shouldBlock)
            if ok then
                bus.BlockStateChanged:Fire(shouldBlock)
            end
        end))
        table.insert(character._connections, bus.DamageRequested:Connect(function(damage, canBlock)
            local amount = self:TakeDamage(character, damage, canBlock)
            local wasBlocked = (character.StateManager:Get("IsBlocking") and canBlock ~= false) or false
            bus.DamageApplied:Fire(amount, wasBlocked)
        end))
        local conn = character.Signals and character.Signals.OnUpdate and character.Signals.OnUpdate.Event:Connect(function(dt)
            bus.Tick:Fire(dt)
        end)
        if conn then
            table.insert(character._connections, conn)
        end
        character.StateManager:OnStateChange("Guard", function(newVal, oldVal)
            bus.GuardChanged:Fire(newVal, oldVal)
        end)
    end

    character.StateManager:OnStateChange("Guard", function(newGuard: number)
        if newGuard <= 0 and not character.StateManager:Get("IsStunned") then
            self:HandleGuardBreak(character)
        end
    end)

    character.StateManager:OnStateChange("MaxGuard", function(newMaxGuard: number)
        local currentGuard = character.StateManager:Get("Guard")
        if currentGuard > newMaxGuard then
            character.StateManager:Set("Guard", newMaxGuard)
        end
    end)

    character.StateManager:OnStateChange("IsBlocking", function(isBlocking: boolean)
        local combatData = character.Components.Combat
        if isBlocking then
            combatData.LastBlockTime = time()
        end
    end)
end

function CombatService:HandleGuardBreak(character: CharacterTypes.internalCharacter)
    local stateManager = character.StateManager
    local combatData = character.Components.Combat

    stateManager:Set("IsStunned", true)
    stateManager:Set("IsBlocking", false)

    combatData.GuardBreakRecovery = time() + self._config.GUARD_BREAK_RECOVERY_TIME

    task.spawn(function()
        task.wait(self._config.GUARD_BREAK_RECOVERY_TIME)
        if not stateManager:Get("IsDead") then
            stateManager:Set("IsStunned", false)
        end
    end)
    local bus = self._buses[character.PlayerId]
    if bus then
        bus.GuardBroken:Fire()
    end
end

function CombatService:Update(character: CharacterTypes.internalCharacter, dt: number)
    local stateManager = character.StateManager
    local combatData = character.Components.Combat
    if stateManager:Get("IsDead") then return end

    local currentTime = time()

    if currentTime - combatData.LastAttackTime > self._config.COMBO_RESET_TIME then
        combatData.ComboCount = 0
    end

    if combatData.GuardBreakRecovery > 0 and currentTime >= combatData.GuardBreakRecovery then
        combatData.GuardBreakRecovery = 0
    end

    if not stateManager:Get("IsStunned") then
        -- Use state-projected values (kept up to date by EffectComponent)
        local guard = stateManager:Get("Guard")
        local maxGuard = stateManager:Get("MaxGuard")
        local isBlocking = stateManager:Get("IsBlocking")
        if not isBlocking and guard < maxGuard then
            local baseRegen = ((Constants.REGEN_RATES and Constants.REGEN_RATES.Guard and Constants.REGEN_RATES.Guard.regenRate) or 15)
            local mult = (stateManager:Get("GuardRegenMult") or 1)
            local guardChange = dt * baseRegen * mult
            stateManager:Set("Guard", math.min(maxGuard, guard + guardChange))
        end
        -- stamina passive bonus example
        local staminaBonus = stateManager:Get("StaminaRegenBonus") or 0
        if staminaBonus ~= 0 then
            local s = stateManager:Get("Stamina")
            local ms = stateManager:Get("MaxStamina")
            if s < ms then stateManager:Set("Stamina", math.min(ms, s + staminaBonus * dt)) end
        end
    end
end

function CombatService:PerformAttack(character: CharacterTypes.internalCharacter, attackType: CombatTypes.AttackType?): boolean
    local stateManager = character.StateManager
    local combatData = character.Components.Combat

    if stateManager:Get("IsDead") or stateManager:Get("IsStunned") then
        return false
    end

    local currentTime = time()
    local attackCooldown = self._config.ATTACK_COOLDOWN * (stateManager:Get("AttackCooldownMult") or 1)
    if currentTime - combatData.LastAttackTime < attackCooldown then
        return false
    end

    local staminaCost = self._config.ATTACK_STAMINA_COST * (stateManager:Get("StaminaCostMult") or 1)
    local currentStamina = stateManager:Get("Stamina")
    if currentStamina < staminaCost then
        return false
    end

    combatData.LastAttackTime = currentTime
    combatData.ComboCount += 1
    stateManager:Set("Stamina", currentStamina - staminaCost)

    if character.Signals and character.Signals.OnAttack then
        character.Signals.OnAttack:Fire(attackType or "Default", combatData.ComboCount)
    end
    local bus = self._buses[character.PlayerId]
    if bus then
        bus.AttackPerformed:Fire(true, attackType, combatData.ComboCount)
    end

    return true
end

function CombatService:PerformBlock(character: CharacterTypes.internalCharacter, shouldBlock: boolean): boolean
    local stateManager = character.StateManager
    if stateManager:Get("IsDead") or stateManager:Get("IsStunned") then
        return false
    end
    if stateManager:Get("Guard") <= 0 then
        return false
    end
    stateManager:Set("IsBlocking", shouldBlock)
    local bus = self._buses[character.PlayerId]
    if bus then
        bus.BlockStateChanged:Fire(shouldBlock)
    end
    return true
end

function CombatService:TakeDamage(character: CharacterTypes.internalCharacter, damage: number, canBlock: boolean?): number
    local stateManager = character.StateManager
    if stateManager:Get("IsDead") then return 0 end

    local actualDamage = damage
    local isBlocking = stateManager:Get("IsBlocking")

    if isBlocking and canBlock ~= false then
        local guard = stateManager:Get("Guard")
        local blockedDamage = damage * self._config.BLOCK_EFFICIENCY
        local guardDamage = damage * (1 - self._config.BLOCK_EFFICIENCY)
        stateManager:Set("Guard", math.max(0, guard - guardDamage))
        actualDamage = blockedDamage
    end

    local currentHealth = stateManager:Get("Health")
    local incomingMult = (stateManager:Get("IncomingDamageMult") or 1)
    stateManager:Set("Health", math.max(0, currentHealth - (actualDamage * incomingMult)))
    local bus = self._buses[character.PlayerId]
    if bus then
        local wasBlocked = (isBlocking and canBlock ~= false) or false
        bus.DamageApplied:Fire(actualDamage, wasBlocked)
    end
    return actualDamage
end

-- Convenience: apply damage from an attacker to a target, including attacker and defender modifiers
function CombatService:ApplyDamage(attacker: CharacterTypes.internalCharacter?, target: CharacterTypes.internalCharacter, baseDamage: number, canBlock: boolean?): number
    local outgoingMult = 1
    if attacker then
        local smA = attacker.StateManager
        outgoingMult = (smA and smA:Get("OutgoingDamageMult")) or 1
    end
    local adjusted = baseDamage * outgoingMult
    return self:TakeDamage(target, adjusted, canBlock)
end

return CombatService
