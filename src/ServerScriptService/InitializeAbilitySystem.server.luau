--!strict
-- Initialize the new scalable ability system on server startup

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Ability System Modules
local AbilitySystemPath = game.ServerStorage.Modules.Core.AbilitySystem
local AbilityRegistry = require(AbilitySystemPath.AbilityRegistry)
local EffectComposer = require(AbilitySystemPath.EffectComposer)
local AbilityModifierSystem = require(AbilitySystemPath.AbilityModifierSystem)
local AbilityComboSystem = require(AbilitySystemPath.AbilityComboSystem)
local CooldownManager = require(AbilitySystemPath.CooldownManager)
local TargetingSystem = require(AbilitySystemPath.TargetingSystem)

-- Load ability definitions
local AbilityDefinitionsLoader = require(game.ServerStorage.AbilityDefinitions)

print("[AbilitySystem] Initializing new scalable ability system...")

-- Initialize all system components (singletons)
local registry = AbilityRegistry.get()
local effectComposer = EffectComposer.get()
local modifierSystem = AbilityModifierSystem.get()
local comboSystem = AbilityComboSystem.get()
local cooldownManager = CooldownManager.get()
local targetingSystem = TargetingSystem.get()

-- Set up event hooks for system integration
local function setupEventHooks()
    -- Hook into player added for character initialization
    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(character)
            print(`[AbilitySystem] Character added for player {player.Name}`)
            
            -- Ability component will handle the rest
        end)
    end)
    
    -- For NPCs, we'd hook into the NPC spawn system
    -- This would be integrated with your entity system
end

-- Set up default combo patterns
local function setupDefaultCombos()
    -- Register some universal combo patterns
    
    -- Basic attack combo (any character's M1 chain)
    comboSystem:registerComboPattern({
        id = "BasicAttackChain",
        name = "Basic Attack Chain",
        sequence = {"Rem_M1", "Rem_M1", "Rem_M1"}, -- Using specific ability IDs
        window = 2.0,
        requirements = {
            targetSame = true
        },
        bonuses = {
            damageMultiplier = 1.3
        },
        visualization = {
            soundEffect = "ComboComplete"
        }
    })
    
    -- Ability chain combo (Q-E-R)
    comboSystem:registerComboPattern({
        id = "AbilityChain",
        name = "Ability Chain",
        sequence = {"Rem_Q", "Rem_E", "Rem_R"},
        window = 3.0,
        bonuses = {
            cooldownReduction = 0.2,
            damageMultiplier = 1.5
        },
        visualization = {
            particleEffect = "ComboChain",
            soundEffect = "ComboChainComplete"
        }
    })
    
    -- Ice combo for Rem
    comboSystem:registerComboPattern({
        id = "IceCombo",
        name = "Frozen Barrage",
        sequence = {"Rem_E", "Rem_M1", "Rem_M1"},
        window = 2.5,
        requirements = {
            targetSame = true
        },
        effects = {
            {
                type = "Stun",
                trigger = "OnCast",
                duration = 0.5
            }
        },
        bonuses = {
            damageMultiplier = 1.4
        }
    })
    
    print("[AbilitySystem] Default combo patterns registered")
end

-- Set up default modifiers
local function setupDefaultModifiers()
    -- Register interaction rules for common modifiers
    
    -- Haste stacks up to 3 times
    modifierSystem:createStackingRule("Haste", 3, true)
    
    -- Power replaces weaker versions
    modifierSystem:createReplaceRule("Power", 60)
    
    -- Immunity blocks debuffs
    modifierSystem:createBlockRule("Immunity")
    
    -- CDR caps at 40%
    modifierSystem:createStackingRule("CooldownReduction", 1, false) -- Don't stack, take highest
    
    print("[AbilitySystem] Default modifier rules registered")
end

-- Set up cooldown reset triggers
local function setupCooldownTriggers()
    -- Register default reset triggers
    
    -- Ultimate resets on triple kill
    cooldownManager:registerResetTrigger({
        id = "TripleKillReset",
        condition = "Custom",
        chance = 1.0,
        affectsAbilities = {"Rem_F"}, -- Ultimate abilities
        cooldown = 30,
        customCondition = function(entity, context)
            -- Check if player got 3 kills in last 10 seconds
            -- This would need integration with kill tracking
            return false -- Placeholder
        end
    })
    
    print("[AbilitySystem] Cooldown triggers registered")
end

-- Initialize legacy ability support
local function initializeLegacySupport()
    -- The registry will automatically convert legacy abilities when needed
    local legacyFolder = game.ReplicatedStorage:FindFirstChild("Modules"):FindFirstChild("Abilities")
    if legacyFolder then
        print("[AbilitySystem] Legacy abilities folder found, conversion available on demand")
        
        -- Pre-convert common abilities for better performance
        for _, characterFolder in ipairs(legacyFolder:GetChildren()) do
            if characterFolder:IsA("Folder") then
                print(`  - Found legacy abilities for: {characterFolder.Name}`)
            end
        end
    end
end

-- Main initialization
local function initialize()
    -- Core setup
    setupEventHooks()
    setupDefaultCombos()
    setupDefaultModifiers()
    setupCooldownTriggers()
    initializeLegacySupport()
    
    -- Print system stats
    print("[AbilitySystem] Initialization complete!")
    print(`  - Abilities loaded: {registry:getDefinitionCount()}`)
    print(`  - Combo patterns: {#comboSystem.comboPatterns}`)
    print(`  - Active modifiers: {modifierSystem:getActiveModifierCount()}`)
    
    -- Verify key abilities are loaded
    local requiredAbilities = {"Rem_M1"}
    for _, abilityId in ipairs(requiredAbilities) do
        local def = registry:getDefinition(abilityId)
        if def then
            print(`  ✓ {abilityId} loaded`)
        else
            warn(`  ✗ {abilityId} not found!`)
        end
    end
end

-- Run initialization
initialize()

-- Set up periodic stats reporting in Studio
if RunService:IsStudio() then
    task.spawn(function()
        while true do
            task.wait(60) -- Report every minute
            
            print("\n[AbilitySystem] Performance Report:")
            
            local cooldownStats = cooldownManager:getStats()
            print(`  Cooldowns: {cooldownStats.activeCooldowns} active, {cooldownStats.totalResets} resets`)
            
            local modifierStats = modifierSystem:getStats()
            print(`  Modifiers: {modifierStats.activeModifierCount} active`)
            
            local comboStats = comboSystem:getStats()
            print(`  Combos: {comboStats.totalCombosTriggered} triggered, max chain: {comboStats.highestComboCount}`)
            
            local effectStats = effectComposer:getStats()
            print(`  Effects: {effectStats.activeEffectCount} active, {effectStats.pooledEffectCount} pooled`)
            
            local targetingStats = targetingSystem:getStats()
            local hitRate = targetingStats.totalTargetingAttempts > 0 
                and math.floor(targetingStats.successfulTargetings / targetingStats.totalTargetingAttempts * 100)
                or 0
            print(`  Targeting: {hitRate}% success rate, {targetingStats.cacheHits} cache hits`)
        end
    end)
end

print("[AbilitySystem] Server initialization complete!")