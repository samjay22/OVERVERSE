--!strict
-- CombatService: centralized combat logic

local Constants = require(game.ReplicatedStorage.Modules.Utility.Constants)

local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)
local CombatTypes = require(game.ServerStorage.Modules.Types.CombatTypes)
local StateHelpers = require(game.ServerStorage.Modules.Types.CharacterStateTypes)
local CombatEventBus = require(game.ServerStorage.Modules.Events.CombatEventBus)

export type CombatService = CombatTypes.ICombatService

local CombatService = {}
CombatService.__index = CombatService

function CombatService.New(): CombatService
    local self = setmetatable({}, CombatService) :: any
    self._config = {
        ATTACK_COOLDOWN = Constants.ATTACK_COOLDOWN or 0.5,
        ATTACK_STAMINA_COST = Constants.ATTACK_STAMINA_COST or 10,
        BLOCK_EFFICIENCY = Constants.BLOCK_EFFICIENCY or 0.5,
        COMBO_RESET_TIME = Constants.COMBO_RESET_TIME or 3,
        GUARD_BREAK_RECOVERY_TIME = Constants.GUARD_BREAK_RECOVERY_TIME or 2,
    } :: CombatTypes.CombatConfig
    self._buses = {} :: {[number]: any}
    return self :: CombatService
end

function CombatService:Initialize(character: CharacterTypes.internalCharacter, config: CombatTypes.CombatConfig?)
    character.Components = character.Components or {}
    character.Components.Combat = character.Components.Combat or {
        LastAttackTime = 0,
        LastBlockTime = 0,
        ComboCount = 0,
        GuardBreakRecovery = 0,
    } :: CombatTypes.CombatPerCharacter

    if config then
        for k, v in pairs(config) do
            ((self :: any)._config :: any)[k] = v
        end
    end

    local bus = ((self :: any)._buses :: any)[character.PlayerId]
    if not bus then
        bus = CombatEventBus.New()
        ;((self :: any)._buses :: any)[character.PlayerId] = bus
        table.insert(character._connections, bus.AttackRequested:Connect(function(attackType: string?)
            local ok = self:PerformAttack(character, attackType)
            bus.AttackPerformed:Fire(ok, attackType, (character.Components.Combat and character.Components.Combat.ComboCount) or 0)
        end))
        table.insert(character._connections, bus.BlockRequested:Connect(function(shouldBlock: boolean)
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

    character.StateManager:OnStateChange("Guard", function(newGuard, oldGuard)
        local guardValue = StateHelpers.asNumber(newGuard, 0)
        local isStunned = StateHelpers.asBoolean(character.StateManager:Get("IsStunned"), false)
        if guardValue <= 0 and not isStunned then
            self:HandleGuardBreak(character)
        end
    end)

    character.StateManager:OnStateChange("MaxGuard", function(newMaxGuard, _oldMaxGuard)
        local maxGuardValue = StateHelpers.asNumber(newMaxGuard, 100)
        local currentGuard = StateHelpers.asNumber(character.StateManager:Get("Guard"), 0)
        if currentGuard > maxGuardValue then
            character.StateManager:Set("Guard", maxGuardValue)
        end
    end)

    character.StateManager:OnStateChange("IsBlocking", function(isBlocking, _oldBlocking)
        local isBlockingValue = StateHelpers.asBoolean(isBlocking, false)
        local combatData = character.Components.Combat
        if isBlockingValue then
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

    local isStunned = StateHelpers.asBoolean(stateManager:Get("IsStunned"), false)
    if not isStunned then
        -- Use state-projected values (kept up to date by EffectComponent)
        local guard = StateHelpers.asNumber(stateManager:Get("Guard"), 0)
        local maxGuard = StateHelpers.asNumber(stateManager:Get("MaxGuard"), 100)
        local isBlocking = StateHelpers.asBoolean(stateManager:Get("IsBlocking"), false)
        if not isBlocking and guard < maxGuard then
            local baseRegen = ((Constants.REGEN_RATES and Constants.REGEN_RATES.Guard and Constants.REGEN_RATES.Guard.regenRate) or 15)
            local mult = StateHelpers.asNumber(stateManager:Get("GuardRegenMult"), 1)
            local guardChange = dt * baseRegen * mult
            stateManager:Set("Guard", math.min(maxGuard, guard + guardChange))
        end
        -- stamina passive bonus example
        local staminaBonus = StateHelpers.asNumber(stateManager:Get("StaminaRegenBonus"), 0)
        if staminaBonus ~= 0 then
            local s = StateHelpers.asNumber(stateManager:Get("Stamina"), 0)
            local ms = StateHelpers.asNumber(stateManager:Get("MaxStamina"), 100)
            if s < ms then stateManager:Set("Stamina", math.min(ms, s + staminaBonus * dt)) end
        end

        -- Safety: auto-clear blocking if no recent block requests arrived (handles missed key-up)
        if isBlocking then
            local last = combatData.LastBlockTime or 0
            -- If we haven't seen a fresh block request for a short period, release block
            if currentTime - last > 0.4 then
                stateManager:Set("IsBlocking", false)
            end
        end
    end
end

function CombatService:PerformAttack(character: CharacterTypes.internalCharacter, attackType: CombatTypes.AttackType?): boolean
    local stateManager = character.StateManager
    local combatData = character.Components.Combat

    local isDead = StateHelpers.asBoolean(stateManager:Get("IsDead"), false)
    local isStunned = StateHelpers.asBoolean(stateManager:Get("IsStunned"), false)
    local isBlocking = StateHelpers.asBoolean(stateManager:Get("IsBlocking"), false)
    
    if isDead or isStunned or isBlocking then
        return false
    end

    local currentTime = time()
    local attackCooldownMult = StateHelpers.asNumber(stateManager:Get("AttackCooldownMult"), 1)
    local attackCooldown = (self :: any)._config.ATTACK_COOLDOWN * attackCooldownMult
    if currentTime - combatData.LastAttackTime < attackCooldown then
        return false
    end

    local staminaCostMult = StateHelpers.asNumber(stateManager:Get("StaminaCostMult"), 1)
    local staminaCost = (self :: any)._config.ATTACK_STAMINA_COST * staminaCostMult
    local currentStamina = StateHelpers.asNumber(stateManager:Get("Stamina"), 0)
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
    -- Only toggle when necessary; refresh timer on repeats to track active holds accurately
    local isCurrentlyBlocking = stateManager:Get("IsBlocking") == true
    if shouldBlock then
        if not isCurrentlyBlocking then
            stateManager:Set("IsBlocking", true)
        end
        local combatData = character.Components.Combat
        combatData.LastBlockTime = time()
    else
        if isCurrentlyBlocking then
            stateManager:Set("IsBlocking", false)
        end
    end
    local bus = self._buses[character.PlayerId]
    if bus then
        bus.BlockStateChanged:Fire(shouldBlock)
    end
    return true
end

function CombatService:TakeDamage(character: CharacterTypes.internalCharacter, damage: number, canBlock: boolean?): number
    local stateManager = character.StateManager
    local isDead = StateHelpers.asBoolean(stateManager:Get("IsDead"), false)
    if isDead then return 0 end

    local actualDamage = damage
    local isBlocking = StateHelpers.asBoolean(stateManager:Get("IsBlocking"), false)

    if isBlocking and canBlock ~= false then
        local guard = StateHelpers.asNumber(stateManager:Get("Guard"), 0)
        local blockedDamage = damage * (self :: any)._config.BLOCK_EFFICIENCY
        local guardDamage = damage * (1 - (self :: any)._config.BLOCK_EFFICIENCY)
        stateManager:Set("Guard", math.max(0, guard - guardDamage))
        actualDamage = blockedDamage
    end

    local currentHealth = StateHelpers.asNumber(stateManager:Get("Health"), 100)
    local incomingMult = StateHelpers.asNumber(stateManager:Get("IncomingDamageMult"), 1)
    stateManager:Set("Health", math.max(0, currentHealth - (actualDamage * incomingMult)))
    local bus = ((self :: any)._buses :: any)[character.PlayerId]
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
        local outgoingMultValue = StateHelpers.asNumber(smA:Get("OutgoingDamageMult"), 1)
        outgoingMult = outgoingMultValue
    end
    local adjusted = baseDamage * outgoingMult
    return self:TakeDamage(target, adjusted, canBlock)
end

return CombatService
