--!strict
local Debris = game:GetService("Debris")
-- Ability Component - Rewritten to use the new scalable ability system
-- HEAVILY OPTIMIZED FOR PERFORMANCE

local BaseComponent = require(script.Parent.BaseComponent)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

-- New Ability System
local AbilitySystemPath = game.ServerStorage.Modules.Core.AbilitySystem
local Types = require(AbilitySystemPath.Types)
local AbilityRegistry = require(AbilitySystemPath.AbilityRegistry)
local EffectComposer = require(AbilitySystemPath.EffectComposer)
local AbilityModifierSystem = require(AbilitySystemPath.AbilityModifierSystem)
local AbilityComboSystem = require(AbilitySystemPath.AbilityComboSystem)
local CooldownManager = require(AbilitySystemPath.CooldownManager)
local TargetingSystem = require(AbilitySystemPath.TargetingSystem)
local NetworkManager = require(game.ReplicatedStorage.Modules.Network.Server)

-- PERFORMANCE OPTIMIZATIONS - Cache frequently used functions
local mathMax = math.max
local mathMin = math.min
local mathCeil = math.ceil
local tableInsert = table.insert
local tableClear = table.clear
local taskSpawn = task.spawn
local taskCancel = task.cancel
local tick = tick

-- OPTIMIZED: Object pools and buffer systems for maximum performance
local ObjectPool = require(game.ServerStorage.Modules.Systems.ObjectPool)
local BufferStateManager = require(game.ServerStorage.Modules.Systems.BufferStateManager)
local BufferAbilitySerializer = require(game.ServerStorage.Modules.Systems.BufferAbilitySerializer)

local abilityInstancePool = ObjectPool.ObjectPool.new(
    function() return {} end,
    function(instance) tableClear(instance) end,
    32
)
local targetDataPool = ObjectPool.ObjectPool.new(
    function() return {} end,
    function(data) tableClear(data) end,
    16
)

-- OPTIMIZED: Buffer-based state management for abilities
local abilityStateBuffers = {} :: {[number]: BufferStateManager} -- playerId -> buffer manager

-- Cache for frequently accessed singletons (lazy initialization)
local registryCache = nil
local cooldownManagerCache = nil
local effectComposerCache = nil
local modifierSystemCache = nil
local comboSystemCache = nil
local targetingSystemCache = nil

type AbilityInstance = Types.AbilityInstance
type AbilityDefinition = Types.AbilityDefinition

type AbilityComponentData = {
    Loadout: AbilityTypes.Loadout,
    AbilityInstances: {[string]: AbilityInstance},
    KeyBindings: {[string]: string?},
    ActiveChannels: {[string]: thread?},
    LastInputTime: number,
    ComboWindow: number,
}

export type AbilityComponent = BaseComponent.BaseComponent & {
    Activate: (self: AbilityComponent, player: Player, abilityId: string, targetData: any?) -> boolean,
    HandleInput: (self: AbilityComponent, player: Player, action: string, isDown: boolean, meta: {[string]: any}?) -> boolean,
    GetLoadout: (self: AbilityComponent, playerId: number) -> AbilityTypes.Loadout?,
    SetLoadout: (self: AbilityComponent, characterData: CharacterTypes.internalCharacter, loadout: AbilityTypes.Loadout) -> (),
    RemapBinding: (self: AbilityComponent, player: Player, binding: string, abilityId: string?) -> boolean,
    IsOnCooldown: (self: AbilityComponent, characterData: CharacterTypes.internalCharacter, abilityId: string) -> boolean,
    GetCooldownRemaining: (self: AbilityComponent, characterData: CharacterTypes.internalCharacter, abilityId: string) -> number,
    ApplyModifier: (self: AbilityComponent, characterData: CharacterTypes.internalCharacter, modifier: Types.AbilityModifier) -> (),
    GetComboCount: (self: AbilityComponent, characterData: CharacterTypes.internalCharacter) -> number,
}

-- System singletons (initialized lazily)
local registry = nil
local effectComposer = nil
local modifierSystem = nil
local comboSystem = nil
local cooldownManager = nil
local targetingSystem = nil

local function getRegistry()
    if not registry then
        registry = AbilityRegistry.get()
    end
    return registry
end

local function getEffectComposer()
    if not effectComposer then
        effectComposer = EffectComposer.get()
    end
    return effectComposer
end

local function getModifierSystem()
    if not modifierSystem then
        modifierSystem = AbilityModifierSystem.get()
    end
    return modifierSystem
end

local function getComboSystem()
    if not comboSystem then
        comboSystem = AbilityComboSystem.get()
    end
    return comboSystem
end

local function getCooldownManager()
    if not cooldownManager then
        cooldownManager = CooldownManager.get()
    end
    return cooldownManager
end

local function getTargetingSystem()
    if not targetingSystem then
        targetingSystem = TargetingSystem.new()
    end
    return targetingSystem
end

-- Constants
local SLOT_KEYS = {"Q", "E", "R", "F"}
local DEFAULT_COMBO_WINDOW = 2.0

-- Store component instances by player ID for quick access
local componentsByPlayerId: {[number]: AbilityComponentData} = {}

local AbilityComponent = BaseComponent:extend("Ability") :: any

function AbilityComponent:Initialize(characterData: CharacterTypes.internalCharacter, config: any?)
    BaseComponent.Initialize(self, characterData, config)
    
    -- Get loadout from config or use character's default
    local loadout: AbilityTypes.Loadout
    if config and (config :: any).AbilityLoadout then
        loadout = (config :: any).AbilityLoadout
    else
        local Constants = require(game.ReplicatedStorage.Modules.Utility.Constants)
        local LoadoutRegistry = require(game.ServerStorage.Modules.registry.Loadouts)
        local classId = characterData.ClassId or Constants.CHARACTER_ASSET_DEFAULT
        loadout = LoadoutRegistry.Get(classId)
    end
    
    local componentData: AbilityComponentData = {
        Loadout = loadout,
        AbilityInstances = {},
        KeyBindings = {},
        ActiveChannels = {},
        LastInputTime = 0,
        ComboWindow = DEFAULT_COMBO_WINDOW,
    }
    
    characterData.Components.Ability = componentData :: any
    componentsByPlayerId[characterData.PlayerId] = componentData
    
    -- Clear any existing cooldowns for this character (in case of respawn/reinit)
    if characterData.Character then
        getCooldownManager():clearEntityCooldowns(characterData.Character)
        getComboSystem():clearComboState(characterData.Character)
        getModifierSystem():clearAllModifiers(characterData.Character)
    end
    
    -- Initialize abilities from loadout
    self:_InitializeAbilities(characterData, componentData)
    
    -- Apply passive modifiers
    if loadout.passive then
        self:_ApplyPassiveAbility(characterData, loadout.passive)
    end
    
    -- Initialize state
    characterData.StateManager:Set("KeyBindings", {})
    characterData.StateManager:Set("PassiveModifiers", {})
    characterData.StateManager:Set("ComboCount", 0)
end

function AbilityComponent:Update(characterData: CharacterTypes.internalCharacter, dt: number)
    if not self:IsEnabled(characterData) then
        return
    end

    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then
        return
    end

    -- OPTIMIZED: Cache character reference and only update combo if needed
    local character = characterData.Character
    if character then
        local comboSystem = getComboSystem()
        local currentCombo = comboSystem:getComboCount(character)
        local lastCombo = characterData.StateManager:Get("ComboCount")
        if currentCombo ~= lastCombo then
            characterData.StateManager:Set("ComboCount", currentCombo)
        end
    end

    -- OPTIMIZED: Check for expired channels with early exit
    local activeChannels = component.ActiveChannels
    local hasExpiredChannels = false
    for abilityId, thread in pairs(activeChannels) do
        if thread and coroutine.status(thread) == "dead" then
            activeChannels[abilityId] = nil
            hasExpiredChannels = true
        end
    end

    -- Only trigger cleanup if we had expired channels
    if hasExpiredChannels then
        -- Trigger any necessary cleanup here if needed
    end
end

function AbilityComponent:Cleanup(characterData: CharacterTypes.internalCharacter)
    local component = characterData.Components.Ability :: AbilityComponentData
    if component then
        -- Cancel active channels
        for _, thread in pairs(component.ActiveChannels) do
            if thread and coroutine.status(thread) ~= "dead" then
                task.cancel(thread)
            end
        end
        
        -- Clear cooldowns
        local cooldownManager = getCooldownManager()
        cooldownManager:clearEntityCooldowns(characterData.Character)

        -- Clear combo state
        local comboSystem = getComboSystem()
        comboSystem:clearComboState(characterData.Character)

        -- Clear modifiers
        local modifierSystem = getModifierSystem()
        modifierSystem:clearAllModifiers(characterData.Character)
    end
    
    componentsByPlayerId[characterData.PlayerId] = nil
    BaseComponent.Cleanup(self, characterData)
end

function AbilityComponent:Activate(player: Player, abilityId: string, targetData: any?): boolean
    local characterData = self:_GetCharacterData(player)
    if not characterData then
        return false
    end
    
    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then
        return false
    end
    
    -- Get ability instance
    local instance = component.AbilityInstances[abilityId]
    if not instance then
        print(`[AbilityComponent] Ability instance not found for '{abilityId}', attempting to create...`)
        -- Try to create instance if ability exists in registry
        instance = self:_CreateAbilityInstance(characterData, abilityId)
        if not instance then
            warn(`[AbilityComponent] Ability not found: {abilityId}`)
            local availableAbilities = {}
            for id, _ in pairs(component.AbilityInstances) do
                table.insert(availableAbilities, id)
            end
            print(`[AbilityComponent] Available instances: {table.concat(availableAbilities, ", ")}`)
            return false
        else
            print(`[AbilityComponent] Successfully created ability instance for '{abilityId}'`)
        end
    else
        print(`[AbilityComponent] Found existing ability instance for '{abilityId}'`)
    end
    
    -- Check if can cast
    local canCast, reason = self:_CanCast(characterData, instance, targetData)
    if not canCast then
        -- Send failure feedback to client for synchronization
        self:_ReplicateAbilityCastFailure(characterData, abilityId, reason or "Unknown", targetData)
        return false
    end
    
    -- Set casting state
    characterData.StateManager:Set("CastingAbility", true)
    characterData.StateManager:Set("CurrentAbility", abilityId)
    
    -- Execute ability
    local success = self:_ExecuteAbility(characterData, instance, targetData)
    
    -- Clear casting state
    characterData.StateManager:Set("CastingAbility", false)
    characterData.StateManager:Set("CurrentAbility", nil)
    
    return success
end

function AbilityComponent:HandleInput(player: Player, action: string, isDown: boolean, meta: {[string]: any}?): boolean
    local characterData = self:_GetCharacterData(player)
    if not characterData then
        return false
    end
    
    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then
        return false
    end
    
    -- Update input time
    component.LastInputTime = os.clock()
    characterData.StateManager:Set("LastInputTS", meta and meta.tsServer or os.time())
    
    -- Handle different input types
    if action == "M1" then
        return self:_HandleM1(player, characterData, isDown, meta)
    elseif action == "M2" then
        return self:_HandleM2(player, characterData, isDown, meta)
    elseif string.sub(action, 1, 4) == "Slot" then
        return self:_HandleSlot(player, characterData, action, isDown, meta)
    else
        -- Try direct ability activation
        if isDown then
            return self:Activate(player, action, meta)
        end
    end
    
    return false
end

function AbilityComponent:GetLoadout(playerId: number): AbilityTypes.Loadout?
    local componentData = componentsByPlayerId[playerId]
    if componentData then
        return componentData.Loadout
    end
    
    local CharacterManager = require(game.ServerStorage.Modules.Entities.Character.CharacterManager)
    local characterData = CharacterManager:GetCharacterData(playerId) :: any
    if characterData and characterData.Components and characterData.Components.Ability then
        local component = characterData.Components.Ability :: AbilityComponentData
        return component.Loadout
    end
    
    return nil
end

function AbilityComponent:SetLoadout(characterData: CharacterTypes.internalCharacter, loadout: AbilityTypes.Loadout)
    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then
        return
    end
    
    -- Clear old abilities and cooldowns
    if characterData.Character then
        local cooldownManager = getCooldownManager()
        cooldownManager:clearEntityCooldowns(characterData.Character)
    end
    component.AbilityInstances = {}
    
    -- Update loadout
    component.Loadout = loadout
    componentsByPlayerId[characterData.PlayerId] = component
    
    -- Initialize new abilities
    self:_InitializeAbilities(characterData, component)
    
    -- Apply new passive
    if loadout.passive then
        self:_ApplyPassiveAbility(characterData, loadout.passive)
    end
end

function AbilityComponent:RemapBinding(player: Player, binding: string, abilityId: string?): boolean
    local characterData = self:_GetCharacterData(player)
    if not characterData then
        return false
    end
    
    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then
        return false
    end
    
    component.KeyBindings[binding] = abilityId
    
    local binds = table.clone(characterData.StateManager:Get("KeyBindings") or {})
    binds[binding] = abilityId
    characterData.StateManager:Set("KeyBindings", binds)
    
    return true
end

function AbilityComponent:IsOnCooldown(characterData: CharacterTypes.internalCharacter, abilityId: string): boolean
    local cooldownManager = getCooldownManager()
    return cooldownManager:isOnCooldown(characterData.Character, abilityId)
end

function AbilityComponent:GetCooldownRemaining(characterData: CharacterTypes.internalCharacter, abilityId: string): number
    local cooldownManager = getCooldownManager()
    return cooldownManager:getCooldownRemaining(characterData.Character, abilityId)
end

function AbilityComponent:ApplyModifier(characterData: CharacterTypes.internalCharacter, modifier: Types.AbilityModifier)
    local modifierSystem = getModifierSystem()
    modifierSystem:applyModifier(characterData.Character, modifier)

    -- Recalculate all ability stats
    local component = characterData.Components.Ability :: AbilityComponentData
    if component then
        for _, instance in pairs(component.AbilityInstances) do
            self:_RecalculateAbilityStats(instance)
        end
    end
end

function AbilityComponent:GetComboCount(characterData: CharacterTypes.internalCharacter): number
    local comboSystem = getComboSystem()
    return comboSystem:getComboCount(characterData.Character)
end

-- Private helper methods

-- Helper function to safely get numeric values from StateManager
local function getNumericState(stateManager: any, key: string, defaultValue: number): number
    local value = stateManager:Get(key)
    return (typeof(value) == "number" and value or defaultValue) :: number
end

function AbilityComponent:_InitializeAbilities(characterData: CharacterTypes.internalCharacter, component: AbilityComponentData)
    -- Initialize primary attacks
    if component.Loadout.primaryAttacks then
        for _, abilityId in ipairs(component.Loadout.primaryAttacks) do
            self:_CreateAbilityInstance(characterData, abilityId)
        end
    end
    
    -- Initialize active abilities
    if component.Loadout.actives then
        for slot, abilityId in ipairs(component.Loadout.actives) do
            if abilityId then
                local instance = self:_CreateAbilityInstance(characterData, abilityId)
                if instance then
                    instance.definition.slot = SLOT_KEYS[slot]
                end
            end
        end
    end
end

function AbilityComponent:_CreateAbilityInstance(characterData: CharacterTypes.internalCharacter, abilityId: string): AbilityInstance?
    local component = characterData.Components.Ability :: AbilityComponentData
    if not component then
        return nil
    end
    
    -- Check if already exists
    if component.AbilityInstances[abilityId] then
        return component.AbilityInstances[abilityId]
    end
    
    -- Get definition from registry
    local registry = getRegistry()
    local definition = registry:getDefinition(abilityId)
    if not definition then
        -- Try legacy format
        local className = characterData.ClassName or "Rem"
        local legacyId = `{className}_{abilityId}`
        definition = registry:getDefinition(legacyId)
        
        if not definition then
            print(`[AbilityComponent] WARNING: Could not find ability definition for '{abilityId}' or '{legacyId}'`)
            return nil
        end
    else
        print(`[AbilityComponent] Found ability definition for '{abilityId}'`)
    end
    
    -- Initialize resources for abilities that use them (only if they don't exist)
    if definition.resources then
        for _, resource in ipairs(definition.resources) do
            local amount = type(resource.amount) == "table" and resource.amount.base or resource.amount
            
            if resource.type == "Ammo" then
                -- Only initialize if not already set
                if characterData.StateManager:Get("CurrentAmmo") == nil then
                    characterData.StateManager:Set("CurrentAmmo", amount)
                    characterData.StateManager:Set("MaxAmmo", amount)
                end
                
                -- Handle custom reload data
                if definition.customData and definition.customData.reloadTime then
                    characterData.StateManager:Set("ReloadTime", definition.customData.reloadTime)
                end
            elseif resource.type == "Mana" then
                if characterData.StateManager:Get("CurrentMana") == nil then
                    characterData.StateManager:Set("CurrentMana", amount)
                    characterData.StateManager:Set("MaxMana", amount)
                end
            elseif resource.type == "Energy" then
                if characterData.StateManager:Get("CurrentEnergy") == nil then
                    characterData.StateManager:Set("CurrentEnergy", amount)
                    characterData.StateManager:Set("MaxEnergy", amount)
                end
            elseif resource.type == "Rage" then
                if characterData.StateManager:Get("CurrentRage") == nil then
                    characterData.StateManager:Set("CurrentRage", 0) -- Rage usually starts at 0
                    characterData.StateManager:Set("MaxRage", amount)
                end
            elseif resource.type == "Focus" then
                if characterData.StateManager:Get("CurrentFocus") == nil then
                    characterData.StateManager:Set("CurrentFocus", amount)
                    characterData.StateManager:Set("MaxFocus", amount)
                end
            elseif resource.type == "Charges" then
                if characterData.StateManager:Get("CurrentCharges") == nil then
                    characterData.StateManager:Set("CurrentCharges", amount)
                    characterData.StateManager:Set("MaxCharges", amount)
                end
            elseif resource.type == "Custom" then
                local customKey = `Current{resource.type}`
                if characterData.StateManager:Get(customKey) == nil then
                    characterData.StateManager:Set(customKey, amount)
                    characterData.StateManager:Set(`Max{resource.type}`, amount)
                end
            end
        end
    end
    
    -- Create instance
    local instance: AbilityInstance = {
        definition = definition,
        owner = characterData.Character,
        level = characterData.Level or 1,
        cooldownRemaining = 0,
        charges = definition.charges and definition.charges.max or 0,
        lastCastTime = 0,
        castCount = 0,
        modifiers = {},
        computedStats = {},
    } :: any
    
    -- Add methods
    instance.canCast = function(self: AbilityInstance, target: Instance?): (boolean, string?)
        return AbilityComponent:_CanCast(characterData, self, target)
    end
    
    instance.execute = function(self: AbilityInstance, targetData: any?): boolean
        return AbilityComponent:_ExecuteAbility(characterData, self, targetData)
    end
    
    instance.interrupt = function(self: AbilityInstance, source: Instance?)
        AbilityComponent:_InterruptAbility(characterData, self, source)
    end
    
    instance.addModifier = function(self: AbilityInstance, modifier: Types.AbilityModifier)
        table.insert(self.modifiers, modifier)
        AbilityComponent:_RecalculateAbilityStats(self)
    end
    
    instance.removeModifier = function(self: AbilityInstance, modifierId: string)
        for i, modifier in ipairs(self.modifiers) do
            if modifier.id == modifierId then
                table.remove(self.modifiers, i)
                AbilityComponent:_RecalculateAbilityStats(self)
                break
            end
        end
    end
    
    instance.getModifiedValue = function(self: AbilityInstance, stat: string): any
        return self.computedStats[stat]
    end
    
    -- Calculate initial stats
    self:_RecalculateAbilityStats(instance)
    
    -- Initialize charges if applicable
    if definition.charges and characterData.Character then
        local cooldownManager = getCooldownManager()
        cooldownManager:initializeCharges(
            characterData.Character,
            definition.id,
            definition.charges.max,
            definition.charges.rechargeTime,
            definition.charges.sharedCharges and {definition.charges.sharedCharges}
        )
    elseif definition.charges and not characterData.Character then
        warn(`[AbilityComponent] Cannot initialize charges for {definition.id}: characterData.Character is nil`)
    end
    
    -- Store instance
    component.AbilityInstances[definition.id] = instance
    
    return instance
end

function AbilityComponent:_CanCast(characterData: CharacterTypes.internalCharacter, instance: AbilityInstance, targetData: any?): (boolean, string?)
    local owner = characterData.Character
    local definition = instance.definition
    
    -- Debug logging
    print("[AbilityComponent] _CanCast check:", {
        owner = owner,
        ownerName = owner and owner.Name or "nil",
        ownerParent = owner and owner.Parent or "nil",
        abilityId = definition.id,
        characterDataPlayerId = characterData.PlayerId
    })
    
    -- Critical: Check if owner is nil
    if not owner then
        warn("[AbilityComponent] Cannot cast ability - character is nil!")
        return false, "Character not found"
    end
    
    -- Check basic states
    if characterData.StateManager:Get("IsDead") then
        return false, "Dead"
    end
    
    if characterData.StateManager:Get("IsStunned") then
        return false, "Stunned"
    end
    
    if characterData.StateManager:Get("CastingAbility") then
        return false, "Already casting"
    end
    
    if characterData.StateManager:Get("IsReloading") then
        return false, "Reloading"
    end
    
    -- Check cooldown
    local cooldownManager = getCooldownManager()
    if cooldownManager:isOnCooldown(owner, definition.id) then
        local remaining = cooldownManager:getCooldownRemaining(owner, definition.id)
        return false, `On cooldown ({math.ceil(remaining)}s)`
    end

    -- Check global cooldown
    if cooldownManager:isOnGlobalCooldown(owner) then
        return false, "Global cooldown"
    end

    -- Check charges
    if definition.charges then
        local currentCharges = cooldownManager:getCharges(owner, definition.id)
        if currentCharges and currentCharges <= 0 then
            return false, "No charges"
        end
    end
    
    -- Check resources
    if definition.resources then
        for _, resource in ipairs(definition.resources) do
            if not self:_CheckResource(characterData, resource) then
                return false, `Insufficient {resource.type}`
            end
        end
    end
    
    -- Check requirements
    if definition.requirements then
        local reqs = definition.requirements
        
        if reqs.level and characterData.Level and characterData.Level < reqs.level then
            return false, `Requires level {reqs.level}`
        end
        
        if reqs.inCombat ~= nil then
            local inCombat = characterData.StateManager:Get("InCombat")
            if inCombat ~= reqs.inCombat then
                return false, reqs.inCombat and "Must be in combat" or "Cannot use in combat"
            end
        end
        
        if reqs.custom and not reqs.custom(owner) then
            return false, "Requirements not met"
        end
    end
    
    -- Validate target if needed
    if definition.targeting.type ~= "Self" and targetData and targetData.target then
        local isValid, reason = getTargetingSystem():validateTarget(owner, targetData.target, definition.targeting)
        if not isValid then
            return false, reason or "Invalid target"
        end
    end
    
    return true
end

function AbilityComponent:_ExecuteAbility(characterData: CharacterTypes.internalCharacter, instance: AbilityInstance, targetData: any?): boolean
    local owner = characterData.Character
    local definition = instance.definition
    
    -- Consume resources
    if definition.resources then
        for _, resource in ipairs(definition.resources) do
            if resource.consumeOnUse ~= false then
                self:_ConsumeResource(characterData, resource)
            end
        end
    end
    
    -- Start cooldown or use charge
    print("[AbilityComponent] Starting cooldown for ability:", definition.id, "owner:", owner, owner and owner.Name or "nil")
    local cooldownManager = getCooldownManager()
    local cooldownStartTime = os.clock()

    if definition.charges then
        cooldownManager:useCharge(owner, definition.id)
        -- Sync charge usage through scalable system
        local maxCharges = 1 -- Default to 1 charge
        if type(definition.charges) == "table" then
            maxCharges = definition.charges.max
        elseif type(definition.charges) == "number" then
            maxCharges = definition.charges
        end
        self:_SyncChargeToClient(characterData, definition.id, maxCharges - 1)
    else
        local cooldown = instance.computedStats.cooldown or (type(definition.cooldown) == "table" and definition.cooldown.base or definition.cooldown)
        print("[AbilityComponent] Cooldown duration:", cooldown)
        cooldownManager:startCooldown(owner, definition.id, cooldown :: number)

        -- Use improved sync system for immediate cooldown sync
        self:_SyncCooldownToClient(characterData, definition.id, cooldown :: number, cooldownStartTime)
    end

    -- Start global cooldown
    if definition.globalCooldown then
        cooldownManager:startGlobalCooldown(owner, definition.globalCooldown)
    end
    
    -- Update combo system
    local comboSystem = getComboSystem()
    comboSystem:onAbilityUsed(owner, definition.id, targetData)

    -- OPTIMIZED: Get targets with cached data and early exits
    local targets = {}
    local targetingSystem = getTargetingSystem()
    if targetData and targetingSystem then
        -- Cache frequently accessed values
        local primaryPart = characterData.Character and characterData.Character.PrimaryPart
        local position = (targetData and targetData.position) or (primaryPart and primaryPart.Position) or Vector3.new()
        local direction = characterData.StateManager:Get("LookDirection") or Vector3.new(0, 0, -1)

        -- Use pooled target config to reduce allocations
        local targetConfig = targetDataPool:Get()
        targetConfig.target = targetData and targetData.target
        targetConfig.position = position
        targetConfig.direction = direction

        targets = targetingSystem:acquireTargets(owner, definition.targeting, targetConfig)

        -- Return to pool
        targetDataPool:Return(targetConfig)
    end

    -- Get combo multiplier
    local comboMultiplier = comboSystem:getComboMultiplier(owner)
    
    -- Execute effects
    local context = {
        stats = instance.computedStats,
        comboMultiplier = comboMultiplier,
        level = instance.level,
        caster = owner
    }
    
    -- Handle different ability types
    if definition.type == "Instant" then
        -- Check if this is a legacy ability
        if self:_HasTag(definition, "Legacy") and definition._legacyModule then
            self:_ExecuteLegacyAbility(characterData, definition, targetData)
        else
            self:_ExecuteInstantAbility(definition, owner, targets, context)
        end
    elseif definition.type == "Channeled" then
        self:_ExecuteChanneledAbility(characterData, definition, owner, targets, context)
    elseif definition.type == "Toggle" then
        self:_ExecuteToggleAbility(characterData, definition, owner, context)
    elseif definition.type == "Charged" then
        self:_ExecuteChargedAbility(characterData, definition, owner, targetData, context)
    end
    
    -- Update instance stats
    instance.lastCastTime = os.clock()
    instance.castCount = instance.castCount + 1
    
    -- Fire events
    -- EventBus integration would go here if needed
    -- Currently handled through NetworkManager
    
    -- Network replication
    self:_ReplicateAbilityCast(characterData, definition.id, targetData, targets)
    
    return true
end

function AbilityComponent:_ExecuteInstantAbility(definition: AbilityDefinition, caster: Instance, targets: {Instance}, context: {[string]: any})
    -- Execute OnCast effects
    local onCastEffects = {}
    if definition.effects then
        for _, effect in ipairs(definition.effects) do
            if effect.trigger == "OnCast" then
                table.insert(onCastEffects, effect)
            end
        end
    end
    local effectComposer = getEffectComposer()
    for _, effect in ipairs(onCastEffects) do
        if effectComposer then
            effectComposer:executeEffect(effect, caster, nil, context)
        end
    end
    
    -- Check if this is a projectile ability
    local isProjectile = self:_HasTag(definition, "Projectile")
    
    -- For projectile abilities, perform hit detection
    if isProjectile then
        local hitTargets = self:_PerformHitDetection(caster, definition, context)
        
        -- Execute OnHit effects only for confirmed hits
        local onHitEffects = {}
        if definition.effects then
            for _, effect in ipairs(definition.effects) do
                if effect.trigger == "OnHit" then
                    table.insert(onHitEffects, effect)
                end
            end
        end
        
        for _, hitData in ipairs(hitTargets) do
            for _, effect in ipairs(onHitEffects) do
                if effectComposer then
                    effectComposer:executeEffect(effect, caster, hitData.target, context)
                end
            end
        end
    else
        -- Non-projectile abilities apply effects to all targeted enemies
        local onHitEffects = {}
        if definition.effects then
            for _, effect in ipairs(definition.effects) do
                if effect.trigger == "OnHit" then
                    table.insert(onHitEffects, effect)
                end
            end
        end
        
        for _, target in ipairs(targets) do
            for _, effect in ipairs(onHitEffects) do
                if effectComposer then
                    effectComposer:executeEffect(effect, caster, target, context)
                end
            end
        end
    end
end

function AbilityComponent:_ExecuteChanneledAbility(characterData: CharacterTypes.internalCharacter, definition: AbilityDefinition, caster: Instance, targets: {Instance}, context: {[string]: any})
    local component = characterData.Components.Ability :: AbilityComponentData
    
    -- Start channel
    local channelTime = definition.channelTime and definition.channelTime.base or 3
    local thread = task.spawn(function()
        local startTime = os.clock()
        
        -- OnChannel effects
        local onChannelEffects = {}
        if definition.effects then
            for _, effect in ipairs(definition.effects) do
                if effect.trigger == "OnChannel" then
                    table.insert(onChannelEffects, effect)
                end
            end
        end
        
        while os.clock() - startTime < channelTime do
            local _progress = (os.clock() - startTime) / channelTime
            
            -- Execute periodic effects
            local effectComposer = getEffectComposer()
            for _, effect in ipairs(onChannelEffects) do
                if effectComposer then
                    effectComposer:executeEffect(effect, caster, targets[1], context)
                end
            end
            
            -- Check if interrupted
            if characterData.StateManager:Get("IsStunned") or characterData.StateManager:Get("IsDead") then
                break
            end
            
            task.wait(0.1)
        end
        
        -- OnEnd effects
        if os.clock() - startTime >= channelTime then
            local onEndEffects = {}
            if definition.effects then
                for _, effect in ipairs(definition.effects) do
                    if effect.trigger == "OnEnd" then
                        table.insert(onEndEffects, effect)
                    end
                end
            end
            for _, target in ipairs(targets) do
                for _, effect in ipairs(onEndEffects) do
                    if effectComposer then
                        effectComposer:executeEffect(effect, caster, target, context)
                    end
                end
            end
        end
        
        component.ActiveChannels[definition.id] = nil
    end)
    
    component.ActiveChannels[definition.id] = thread
end

function AbilityComponent:_ExecuteToggleAbility(characterData: CharacterTypes.internalCharacter, definition: AbilityDefinition, caster: Instance, context: {[string]: any})
    local component = characterData.Components.Ability :: AbilityComponentData
    
    -- Check if already active
    local activeThread = component.ActiveChannels[definition.id]
    if activeThread then
        -- Deactivate
        task.cancel(activeThread)
        component.ActiveChannels[definition.id] = nil
    else
        -- Activate
        local thread = task.spawn(function()
            while true do
                -- Execute periodic effects
                local periodicEffects = {}
                if definition.effects then
                    for _, effect in ipairs(definition.effects) do
                        if effect.trigger == "Periodic" then
                            table.insert(periodicEffects, effect)
                        end
                    end
                end
                local effectComposer = getEffectComposer()
                for _, effect in ipairs(periodicEffects) do
                    if effectComposer then
                        effectComposer:executeEffect(effect, caster, nil, context)
                    end
                end
                
                task.wait(1) -- Tick rate
            end
        end)
        
        component.ActiveChannels[definition.id] = thread
    end
end

function AbilityComponent:_ExecuteChargedAbility(characterData: CharacterTypes.internalCharacter, definition: AbilityDefinition, caster: Instance, targetData: any?, context: {[string]: any})
    -- This would implement charge-up mechanics
    -- For now, treat as instant
    self:_ExecuteInstantAbility(definition, caster, {}, context)
end

function AbilityComponent:_ExecuteLegacyAbility(characterData: CharacterTypes.internalCharacter, definition: AbilityDefinition, targetData: any?)
    -- Handle legacy ability modules (like M1) that use Server.Validate pattern
    local legacyModule = definition._legacyModule
    local legacyData = definition._legacyData

    if not legacyModule or not legacyData then
        warn(`[AbilityComponent] Legacy ability {definition.id} missing module or data`)
        return
    end

    -- Get player from character data
    local player = characterData.Entity and characterData.Entity.player
    if not player then
        warn(`[AbilityComponent] No player found for legacy ability {definition.id}`)
        return
    end

    -- Check if the legacy module has a Server.Validate function
    if legacyData.Server and legacyData.Server.Validate then
        -- Create onHit callback for damage application
        local onHit = function(target: Model?)
            if not target then return end

            -- Apply damage using the combat system
            local targetCharacterData = self:_GetCharacterDataFromModel(target)
            if targetCharacterData then
                local combatComponent = targetCharacterData.Components.Combat
                if combatComponent and combatComponent.Service then
                    -- Get damage from definition or legacy config
                    local damage = 10 -- Default damage
                    if definition._legacyData and definition._legacyData.Config and definition._legacyData.Config.Damage then
                        damage = definition._legacyData.Config.Damage
                    elseif #definition.effects > 0 then
                        for _, effect in ipairs(definition.effects) do
                            if effect.type == "Damage" and effect.amount then
                                damage = effect.amount.base or effect.amount
                                break
                            end
                        end
                    end

                    combatComponent.Service:ApplyDamage(characterData, targetCharacterData, damage, true)
                    print(`[AbilityComponent] Legacy ability {definition.id} dealt {damage} damage to {target.Name}`)
                end
            end
        end

        -- Call the legacy Server.Validate function with network-aware targetData
        local success = pcall(function()
            legacyData.Server:Validate(player, onHit, characterData, targetData)
        end)

        if not success then
            warn(`[AbilityComponent] Failed to execute legacy ability {definition.id}`)
        end
    else
        warn(`[AbilityComponent] Legacy ability {definition.id} missing Server.Validate function`)
    end
end

function AbilityComponent:_InterruptAbility(characterData: CharacterTypes.internalCharacter, instance: AbilityInstance, source: Instance?)
    local component = characterData.Components.Ability :: AbilityComponentData
    local definition = instance.definition
    
    -- Cancel active channel
    local activeThread = component.ActiveChannels[definition.id]
    if activeThread then
        task.cancel(activeThread)
        component.ActiveChannels[definition.id] = nil
    end
    
    -- Fire interrupt event
    -- EventBus integration would go here if needed
    -- Currently handled through NetworkManager
end

function AbilityComponent:_HasTag(definition: AbilityDefinition, tag: string): boolean
    if not definition.tags then
        return false
    end
    
    for _, t in ipairs(definition.tags) do
        if t == tag then
            return true
        end
    end
    
    return false
end

function AbilityComponent:_PerformHitDetection(caster: Instance, definition: AbilityDefinition, context: {[string]: any}): {{target: Instance, hitPoint: Vector3, distance: number}}
    local hitTargets = {}

    -- Get character data to access components
    local player = game.Players:GetPlayerFromCharacter(caster)
    if not player then
        return hitTargets
    end

    local characterData = self:_GetCharacterData(player)
    if not characterData then
        return hitTargets
    end

    -- Get character position (use HumanoidRootPart or PrimaryPart)
    local rootPart = caster:FindFirstChild("HumanoidRootPart")
    if not rootPart and caster:IsA("Model") then
        rootPart = (caster :: Model).PrimaryPart
    end
    if not rootPart then
        return hitTargets
    end

    local rootPartTyped = rootPart :: BasePart
    local startPosition = rootPartTyped.Position

    -- Get mouse component data for direction calculation
    local mouseComponent = characterData.Components.Mouse
    local mouseHitPosition = mouseComponent and mouseComponent.MouseHitPosition or characterData.StateManager:Get("MouseHitPosition")

    -- Calculate direction
    local direction: Vector3
    if mouseHitPosition and typeof(mouseHitPosition) == "Vector3" then
        direction = (mouseHitPosition - startPosition).Unit
    else
        -- Fallback to forward direction
        direction = rootPartTyped.CFrame.LookVector
    end

    -- Get range and width from targeting config
    local range = definition.targeting.range or 100
    local width = definition.targeting.radius or 5 -- Use radius as width for the collision part

    -- Use invisible part collision detection instead of raycast
    hitTargets = self:_PerformPartBasedHitDetection(caster, startPosition, direction, range, width, definition.targeting.filter)

    return hitTargets
end

function AbilityComponent:_PerformPartBasedHitDetection(caster: Instance, startPosition: Vector3, direction: Vector3, range: number, width: number, filter: any?): {{target: Instance, hitPoint: Vector3, distance: number}}
    local hitTargets = {}

    -- Create invisible collision part
    local hitPart = Instance.new("Part")
    hitPart.Name = "AbilityHitDetection"
    hitPart.Anchored = true
    hitPart.CanCollide = false
    hitPart.CanTouch = true
    hitPart.Transparency = 0 -- Invisible
    hitPart.Material = Enum.Material.ForceField -- No visual impact

    warn("Performing part-based hit detection")

    -- Size the part based on range and width
    -- Make it a rectangular prism extending forward from the character
    hitPart.Size = Vector3.new(width, width, range)

    -- Position the part forward from the character by half the range
    local centerPosition = startPosition + direction * (range / 2)
    hitPart.CFrame = CFrame.lookAt(centerPosition, centerPosition + direction)

    -- Parent to workspace temporarily
    hitPart.Parent = workspace

    -- Track what we've already hit to avoid duplicates
    local alreadyHit = {}
    local temp = hitPart.Touched:Connect(warn)
    local boundingParts = hitPart:GetTouchingParts()
    temp:Disconnect()
    for _, hit in ipairs(boundingParts) do
         -- Find the character model
        local hitModel = hit:FindFirstAncestorWhichIsA("Model")
        if not hitModel then
            continue
        end

        -- Avoid hitting the caster
        if hitModel == caster then
            continue
        end

        -- Avoid duplicate hits
        if alreadyHit[hitModel] then
            continue
        end
        alreadyHit[hitModel] = true

        -- Check for humanoid
        local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            continue
        end

        -- Validate target against filter
        if not self:_ValidateTarget(caster, hitModel, filter) then
            continue
        end

        -- Calculate hit point and distance
        local targetRootPart = hitModel:FindFirstChild("HumanoidRootPart") or hitModel.PrimaryPart
        local hitPoint: Vector3
        if targetRootPart and targetRootPart:IsA("BasePart") then
            hitPoint = (targetRootPart :: BasePart).Position
        else
            hitPoint = (hit :: BasePart).Position
        end
        local distance = (hitPoint - startPosition).Magnitude

        -- Use pooled hit data to reduce allocations
        local hitData = targetDataPool:Get() :: any
        hitData.target = hitModel
        hitData.hitPoint = hitPoint
        hitData.distance = distance

        tableInsert(hitTargets, hitData)
    end

    Debris:AddItem(hitPart, .15)
    return hitTargets
end

-- Enhanced hit detection with different shapes and better performance
function AbilityComponent:_PerformShapedHitDetection(caster: Instance, startPosition: Vector3, direction: Vector3, config: {
    range: number,
    width: number?,
    height: number?,
    shape: "Box" | "Sphere" | "Cone"?,
    maxTargets: number?
}): {{target: Instance, hitPoint: Vector3, distance: number}}
    local hitTargets = {}
    local shape = config.shape or "Box"
    local maxTargets = config.maxTargets or math.huge

    -- Create the appropriate collision part based on shape
    local hitPart: BasePart

    if shape == "Sphere" then
        hitPart = Instance.new("Part")
        local partTyped = hitPart :: Part
        partTyped.Shape = Enum.PartType.Ball
        hitPart.Size = Vector3.new(config.range * 2, config.range * 2, config.range * 2)
        hitPart.CFrame = CFrame.new(startPosition)
    elseif shape == "Cone" then
        -- Use a wedge part for cone-like detection
        hitPart = Instance.new("WedgePart")
        local width = config.width or config.range * 0.5
        hitPart.Size = Vector3.new(width, config.height or width, config.range)
        local centerPosition = startPosition + direction * (config.range / 2)
        hitPart.CFrame = CFrame.lookAt(centerPosition, centerPosition + direction)
    else -- Box (default)
        hitPart = Instance.new("Part")
        local width = config.width or 5
        local height = config.height or width
        hitPart.Size = Vector3.new(width, height, config.range)
        local centerPosition = startPosition + direction * (config.range / 2)
        hitPart.CFrame = CFrame.lookAt(centerPosition, centerPosition + direction)
    end

    -- Configure the hit part
    hitPart.Name = "AbilityHitDetection"
    hitPart.Anchored = true
    hitPart.CanCollide = false
    hitPart.CanTouch = true
    hitPart.Transparency = 1
    hitPart.Material = Enum.Material.ForceField
    hitPart.Parent = workspace

    -- Track hits and setup collision detection
    local alreadyHit = {}
    local hitCount = 0

    local connection
    connection = hitPart.Touched:Connect(function(hit)
        -- Early exit if we've hit max targets
        if hitCount >= maxTargets then
            return
        end

        local hitModel = hit:FindFirstAncestorWhichIsA("Model")
        if not hitModel or hitModel == caster or alreadyHit[hitModel] then
            return
        end

        alreadyHit[hitModel] = true

        local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            return
        end

        -- For cone shape, do additional angle checking
        if shape == "Cone" then
            local targetPos = humanoid.RootPart and humanoid.RootPart.Position or hitModel.PrimaryPart and hitModel.PrimaryPart.Position
            if targetPos then
                local toTarget = (targetPos - startPosition).Unit
                local angle = math.acos(direction:Dot(toTarget))
                local maxAngle = math.rad(45) -- 45 degree cone
                if angle > maxAngle then
                    return
                end
            end
        end

        local targetRootPart = hitModel:FindFirstChild("HumanoidRootPart") or hitModel.PrimaryPart
        local hitPoint: Vector3
        if targetRootPart and targetRootPart:IsA("BasePart") then
            hitPoint = (targetRootPart :: BasePart).Position
        else
            hitPoint = (hit :: BasePart).Position
        end

        local hitData = targetDataPool:Get() :: any
        hitData.target = hitModel
        hitData.hitPoint = hitPoint
        hitData.distance = (hitPoint - startPosition).Magnitude

        tableInsert(hitTargets, hitData)
        hitCount = hitCount + 1
    end)

    -- Brief wait for collision detection
    task.wait(0.1)

    -- Cleanup
    connection:Disconnect()
    hitPart:Destroy()

    return hitTargets
end

-- Example usage method for different ability types
function AbilityComponent:_GetHitDetectionForAbility(caster: Instance, definition: AbilityDefinition, context: {[string]: any}): {{target: Instance, hitPoint: Vector3, distance: number}}
    local rootPart = caster:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return {}
    end

    local rootPartTyped = rootPart :: BasePart
    local startPosition = rootPartTyped.Position
    local direction = rootPartTyped.CFrame.LookVector -- Default forward direction

    -- Get mouse direction if available
    local player = game.Players:GetPlayerFromCharacter(caster)
    if player then
        local characterData = self:_GetCharacterData(player)
        if characterData and characterData.Components.Mouse then
            local mouseHitPosition = characterData.Components.Mouse.MouseHitPosition
            if mouseHitPosition and typeof(mouseHitPosition) == "Vector3" then
                direction = (mouseHitPosition - startPosition).Unit
            end
        end
    end

    -- Determine hit detection method based on ability type
    local abilityType = definition.customData and definition.customData.abilityType or "single"

    if abilityType == "melee" then
        -- Short range, wide arc for melee attacks
        return self:_PerformShapedHitDetection(caster, startPosition, direction, {
            range = definition.targeting.range or 8,
            width = 10,
            height = 8,
            shape = "Box",
            maxTargets = 3
        })
    elseif abilityType == "shotgun" then
        -- Wide cone for shotgun-like abilities
        return self:_PerformShapedHitDetection(caster, startPosition, direction, {
            range = definition.targeting.range or 20,
            width = 15,
            height = 10,
            shape = "Cone",
            maxTargets = 5
        })
    elseif abilityType == "aoe" then
        -- Sphere around caster for area abilities
        return self:_PerformShapedHitDetection(caster, startPosition, direction, {
            range = definition.targeting.radius or 15,
            shape = "Sphere",
            maxTargets = 10
        })
    elseif abilityType == "beam" then
        -- Long, narrow beam
        return self:_PerformPartBasedHitDetection(caster, startPosition, direction,
            definition.targeting.range or 50,
            definition.targeting.radius or 3,
            definition.targeting.filter)
    else
        -- Default single target or projectile
        return self:_PerformPartBasedHitDetection(caster, startPosition, direction,
            definition.targeting.range or 30,
            definition.targeting.radius or 5,
            definition.targeting.filter)
    end
end

function AbilityComponent:_ValidateTarget(caster: Instance, target: Instance, filter: any?): boolean
    if not filter then
        return true
    end
    
    -- Check team filter
    if filter.team then
        if filter.team == "Enemy" then
            -- For now, consider all other characters as enemies
            return target ~= caster
        elseif filter.team == "Ally" then
            -- Would need team system implementation
            return false
        elseif filter.team == "All" then
            return target ~= caster
        end
    end
    
    -- Check status filter  
    if filter.status == "Alive" then
        local humanoid = target:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            return false
        end
    end
    
    return true
end

function AbilityComponent:_RecalculateAbilityStats(instance: AbilityInstance)
    local definition = instance.definition
    
    -- Base stats
    local baseStats = {
        cooldown = type(definition.cooldown) == "table" and (definition.cooldown :: any).base or definition.cooldown,
        castTime = definition.castTime and (definition.castTime :: any).base or 0,
        range = definition.targeting.range or 0,
        radius = definition.targeting.radius or 0,
        damage = 0,
        cost = {}
    }
    
    -- Calculate resource costs
    if definition.resources then
        for _, resource in ipairs(definition.resources) do
            local amount = type(resource.amount) == "table" and resource.amount.base or resource.amount
            baseStats.cost[resource.type] = amount
        end
    end
    
    -- Apply modifiers
    local modifierSystem = getModifierSystem()
    instance.computedStats = (modifierSystem :: any):calculateModifiedStats(instance, baseStats)
end

function AbilityComponent:_ApplyPassiveAbility(characterData: CharacterTypes.internalCharacter, passiveId: string)
    -- Get passive definition
    local registry = getRegistry()
    local definition = (registry :: any):getDefinition(passiveId)
    if not definition then
        return
    end

    -- Apply passive effects
    local passiveEffects = {}
    if definition.effects then
        for _, effect in ipairs(definition.effects) do
            if (effect :: any).trigger == "Passive" then
                table.insert(passiveEffects, effect)
            end
        end
    end
    local effectComposer = getEffectComposer()
    for _, effect in ipairs(passiveEffects) do
        if effectComposer then
            effectComposer:executeEffect(effect, characterData.Character, nil, {})
        end
    end
    
    -- Apply modifiers if specified
    if definition.modifiers then
        local modifier: Types.AbilityModifier = {
            id = `Passive_{passiveId}`,
            source = characterData.Character,
            priority = 10,
            duration = nil, -- Permanent
            statModifiers = definition.modifiers
        }
        local modifierSystem = getModifierSystem()
        local modifierSystemTyped = modifierSystem :: any
        modifierSystemTyped:applyModifier(characterData.Character, modifier)
    end
end

function AbilityComponent:_CheckResource(characterData: CharacterTypes.internalCharacter, resource: Types.ResourceRequirement): boolean
    local amount: number = if type(resource.amount) == "table" then (resource.amount :: any).base else resource.amount :: number
    
    if resource.type == "Health" then
        local humanoid = characterData.Character:FindFirstChild("Humanoid") :: Humanoid?
        return humanoid ~= nil and humanoid.Health > amount
    elseif resource.type == "Stamina" then
        local stamina = getNumericState(characterData.StateManager, "CurrentStamina", 100)
        return stamina >= amount
    elseif resource.type == "Mana" then
        local mana = getNumericState(characterData.StateManager, "CurrentMana", 0)
        return mana >= amount
    elseif resource.type == "Energy" then
        local energy = getNumericState(characterData.StateManager, "CurrentEnergy", 0)
        return energy >= amount
    elseif resource.type == "Rage" then
        local rage = getNumericState(characterData.StateManager, "CurrentRage", 0)
        return rage >= amount
    elseif resource.type == "Focus" then
        local focus = getNumericState(characterData.StateManager, "CurrentFocus", 0)
        return focus >= amount
    elseif resource.type == "Charges" then
        local charges = getNumericState(characterData.StateManager, "CurrentCharges", 0)
        return charges >= amount
    elseif resource.type == "Ammo" then
        -- For ammo, we need at least 1 shot
        local currentAmmo = getNumericState(characterData.StateManager, "CurrentAmmo", 0)
        return currentAmmo > 0
    elseif resource.type == "Custom" then
        local customKey = `Current{resource.type}`
        local customValue = tonumber(characterData.StateManager:Get(customKey)) or 0
        return customValue >= amount
    end
    
    return true
end

function AbilityComponent:_ConsumeResource(characterData: CharacterTypes.internalCharacter, resource: Types.ResourceRequirement)
    local amount: number = if type(resource.amount) == "table" then (resource.amount :: any).base else resource.amount :: number
    
    if resource.type == "Health" then
        local humanoid = characterData.Character:FindFirstChild("Humanoid") :: Humanoid?
        if humanoid then
            humanoid:TakeDamage(amount)
        end
    elseif resource.type == "Stamina" then
        local stamina = getNumericState(characterData.StateManager, "CurrentStamina", 100)
        characterData.StateManager:Set("CurrentStamina", math.max(0, stamina - amount))
    elseif resource.type == "Mana" then
        local mana = getNumericState(characterData.StateManager, "CurrentMana", 0)
        characterData.StateManager:Set("CurrentMana", math.max(0, mana - amount))
    elseif resource.type == "Energy" then
        local energy = getNumericState(characterData.StateManager, "CurrentEnergy", 0)
        characterData.StateManager:Set("CurrentEnergy", math.max(0, energy - amount))
    elseif resource.type == "Rage" then
        local rage = getNumericState(characterData.StateManager, "CurrentRage", 0)
        characterData.StateManager:Set("CurrentRage", math.min(100, rage + amount)) -- Rage increases on use
    elseif resource.type == "Focus" then
        local focus = getNumericState(characterData.StateManager, "CurrentFocus", 0)
        characterData.StateManager:Set("CurrentFocus", math.max(0, focus - amount))
    elseif resource.type == "Charges" then
        local charges = getNumericState(characterData.StateManager, "CurrentCharges", 0)
        characterData.StateManager:Set("CurrentCharges", math.max(0, charges - amount))
    elseif resource.type == "Ammo" then
        -- Consume 1 ammo per shot
        local currentAmmo = getNumericState(characterData.StateManager, "CurrentAmmo", 0)
        characterData.StateManager:Set("CurrentAmmo", math.max(0, currentAmmo - 1))

        -- Handle reload if out of ammo
        if currentAmmo - 1 <= 0 then
            local maxAmmo = getNumericState(characterData.StateManager, "MaxAmmo", amount)
            local reloadTime = getNumericState(characterData.StateManager, "ReloadTime", 3)
            
            -- Start reload
            characterData.StateManager:Set("IsReloading", true)
            task.spawn(function()
                task.wait(reloadTime)
                characterData.StateManager:Set("CurrentAmmo", maxAmmo)
                characterData.StateManager:Set("IsReloading", false)
            end)
        end
    elseif resource.type == "Custom" then
        local customKey = `Current{resource.type}`
        local customValue = tonumber(characterData.StateManager:Get(customKey)) or 0
        characterData.StateManager:Set(customKey, math.max(0, customValue - amount))
    end
end

function AbilityComponent:_ReplicateAbilityCast(characterData: CharacterTypes.internalCharacter, abilityId: string, targetData: any, targets: {Instance})
    -- Network replication
    local player = game.Players:GetPlayerFromCharacter(characterData.Character)

    if NetworkManager and NetworkManager.CastAbility then
        local eventData = {
            PlayerCaster = player or game.Players:GetPlayers()[1], -- Fallback for NPCs
            CharacterName = characterData.Entity and characterData.Entity.name or "Unknown",
            AbilityName = abilityId,
            Position = targetData and targetData.position or Vector3.new(0,0,0),
            Direction = targetData and targetData.normal or Vector3.new(0,0,-1)
        }

        if player then
            -- FireAllExcept doesn't exist, use FireAll with filter logic on client
            NetworkManager.CastAbility.FireAll(eventData)
        else
            NetworkManager.CastAbility.FireAll(eventData)
        end
    end
end

-- New method to send ability cast failure to client using state sync
function AbilityComponent:_ReplicateAbilityCastFailure(characterData: CharacterTypes.internalCharacter, abilityId: string, reason: string, targetData: any?)
    -- Set a temporary state that the client can read to cancel prediction
    characterData.StateManager:Set("LastAbilityCastFailed", {
        abilityId = abilityId,
        reason = reason,
        timestamp = os.clock()
    })

    -- Clear the failure state after a short time
    task.delay(0.5, function()
        if characterData.StateManager then
            characterData.StateManager:Set("LastAbilityCastFailed", {})
        end
    end)
end

local function debugLog(message: string)
    print(`[AbilityComponent] {message}`)
end

-- Immediately sync cooldown state to client for better timing
function AbilityComponent:_SyncCooldownToClient(characterData: CharacterTypes.internalCharacter, abilityId: string, cooldownDuration: number, startTime: number)
    local player = game.Players:GetPlayerFromCharacter(characterData.Character)
    if not player then
        return
    end

    -- Use improved immediate sync for better timing
    local cooldownEndTime = startTime + cooldownDuration
    local cooldownState = {
        abilityId = abilityId,
        startTime = startTime,
        endTime = cooldownEndTime,
        duration = cooldownDuration,
        timestamp = os.clock()
    }

    -- Set immediate cooldown state for client sync
    characterData.StateManager:Set("ImmediateCooldownSync", cooldownState)

    debugLog(`Immediate cooldown sync sent for {abilityId}: {cooldownDuration}s`)

    -- Clear the immediate sync state after a short time
    task.delay(1.0, function()
        if characterData.StateManager then
            characterData.StateManager:Set("ImmediateCooldownSync", {})
        end
    end)
end

-- Sync charge state to client through improved system
function AbilityComponent:_SyncChargeToClient(characterData: CharacterTypes.internalCharacter, abilityId: string, remainingCharges: number)
    local player = game.Players:GetPlayerFromCharacter(characterData.Character)
    if not player then
        return
    end

    -- Use immediate charge sync for better timing
    local chargeState = {
        abilityId = abilityId,
        charges = remainingCharges,
        timestamp = os.clock()
    }

    -- Set immediate charge state for client sync
    characterData.StateManager:Set("ImmediateChargeSync", chargeState)

    debugLog(`Immediate charge sync sent for {abilityId}: {remainingCharges} charges remaining`)

    -- Clear the immediate sync state after a short time
    task.delay(1.0, function()
        if characterData.StateManager then
            characterData.StateManager:Set("ImmediateChargeSync", {})
        end
    end)
end

function AbilityComponent:_HandleM1(player: Player, characterData: CharacterTypes.internalCharacter, isDown: boolean, meta: {[string]: any}?): boolean
    if not isDown then return true end
    
    local component = characterData.Components.Ability :: AbilityComponentData
    local abilityId = component.KeyBindings.M1 or (component.Loadout.primaryAttacks and component.Loadout.primaryAttacks[1])
    
    if abilityId then
        return self:Activate(player, abilityId, meta and meta.target)
    end
    
    return false
end

function AbilityComponent:_HandleM2(player: Player, characterData: CharacterTypes.internalCharacter, isDown: boolean, meta: {[string]: any}?): boolean
    local component = characterData.Components.Ability :: AbilityComponentData
    local abilityId = component.KeyBindings.M2 or (component.Loadout.primaryAttacks and component.Loadout.primaryAttacks[2])
    
    if abilityId and isDown then
        return self:Activate(player, abilityId, meta and meta.target)
    end
    
    return false
end

function AbilityComponent:_HandleSlot(player: Player, characterData: CharacterTypes.internalCharacter, action: string, isDown: boolean, meta: {[string]: any}?): boolean
    if not isDown then return false end
    
    local component = characterData.Components.Ability :: AbilityComponentData
    local slot = tonumber(string.sub(action, 5))
    
    if slot and slot >= 1 and slot <= 4 then
        local abilityId = component.Loadout.actives and component.Loadout.actives[slot]
        if abilityId then
            return self:Activate(player, abilityId, meta and meta.target)
        end
    end
    
    return false
end

function AbilityComponent:_GetCharacterData(player: Player): CharacterTypes.internalCharacter?
    local CharacterManager = require(game.ServerStorage.Modules.Entities.Character.CharacterManager)
    return CharacterManager:GetCharacterData(player) :: any
end

function AbilityComponent:_GetCharacterDataFromModel(model: Model): CharacterTypes.internalCharacter?
    -- Try to find player from the model
    local player = game.Players:GetPlayerFromCharacter(model)
    if player then
        return self:_GetCharacterData(player)
    end

    -- If no player found, this might be an NPC - would need NPC character system
    return nil
end

-- Create singleton instance
local instance = AbilityComponent.new()

-- Export interface
return {
    Instance = instance,
    
    -- Component interface
    Initialize = function(...) return instance:Initialize(...) end,
    Update = function(...) return instance:Update(...) end,
    Cleanup = function(...) return instance:Cleanup(...) end,
    Activate = function(...) return instance:Activate(...) end,
    HandleInput = function(...) return instance:HandleInput(...) end,
    GetLoadout = function(...) return instance:GetLoadout(...) end,
    SetLoadout = function(...) return instance:SetLoadout(...) end,
    RemapBinding = function(...) return instance:RemapBinding(...) end,
    IsOnCooldown = function(...) return instance:IsOnCooldown(...) end,
    GetCooldownRemaining = function(...) return instance:GetCooldownRemaining(...) end,
    ApplyModifier = function(...) return instance:ApplyModifier(...) end,
    GetComboCount = function(...) return instance:GetComboCount(...) end,
}