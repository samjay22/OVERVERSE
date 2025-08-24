--!strict
-- RemM1 Server Module - Primary Category Ability
-- Rewritten to work with category-based execution system

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types: {  } = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local Config = require(script.Parent.Config)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

-- Import required services
local Targeting = require(ReplicatedStorage.Modules.CoreClient.Targeting).new()
local CharacterManager = require(game.ServerStorage.Modules.Entities.Character)

type EntityRef = AbilityTypes.EntityRef

-- Performance optimization: Simple entity lookup cache
local entityCache: {[number]: EntityRef?} = {}
local CACHE_EXPIRY_TIME = 5 -- seconds
local lastCacheClean = tick()

local function cleanExpiredCache()
    local currentTime = tick()
    if currentTime - lastCacheClean > CACHE_EXPIRY_TIME then
        table.clear(entityCache)
        lastCacheClean = currentTime
    end
end

local Server = {}

-- Helper function to get EntityRef from playerId (optimized with caching)
local function getEntityFromPlayerId(playerId: number): EntityRef?
    -- Clean expired cache periodically
    cleanExpiredCache()
    
    -- Check cache first
    local cachedEntity = entityCache[playerId]
    if cachedEntity then
        return cachedEntity
    end
    
    local entity: EntityRef?
    
    if playerId > 0 then
        -- Player
        local player = Players:GetPlayerByUserId(playerId)
        if player then
            entity = {
                entityType = "Player",
                player = player,
                npcId = nil,
                name = player.Name,
                userId = playerId
            }
        end
    else
        -- NPC (negative playerId indicates NPC)
        local npcId = -playerId
        entity = {
            entityType = "NPC",
            player = nil,
            npcId = tostring(npcId),
            name = "NPC_" .. tostring(npcId),
            userId = playerId
        }
    end
    
    -- Cache the result
    if entity then
        entityCache[playerId] = entity
    end
    
    return entity
end

-- Helper function to get entity position
local function _getEntityPosition(entity: EntityRef): Vector3?
    local characterData = CharacterManager:GetCharacterData(entity)
    if characterData and characterData.Character and characterData.Character.PrimaryPart then
        return characterData.Character.PrimaryPart.Position
    end
    return nil
end

-- Validate if target entity can be healed
local function validateHealTarget(targetEntity: EntityRef): boolean
    local targetCharacterData = CharacterManager:GetCharacterData(targetEntity)
    if not targetCharacterData or not targetCharacterData.Humanoid then
        print(`RemM1: Target {targetEntity.name} has no character data`)
        return false
    end
    
    -- Check if target is alive
    if targetCharacterData.Humanoid.Health <= 0 then
        print(`RemM1: Target {targetEntity.name} is dead (Health: {targetCharacterData.Humanoid.Health})`)
        return false
    end
    
    print(`RemM1: Target {targetEntity.name} is valid for healing (Health: {targetCharacterData.Humanoid.Health})`)
    return true
end

-- Apply healing to target entity
local function applyHealing(targetEntity: EntityRef, healAmount: number): boolean
    local targetCharacterData = CharacterManager:GetCharacterData(targetEntity)
    if not targetCharacterData or not targetCharacterData.Humanoid then
        return false
    end
    
    local humanoid = targetCharacterData.Humanoid
    local currentHealth = humanoid.Health
    local maxHealth = humanoid.MaxHealth
    
    -- Calculate overheal limit
    local overhealLimit = maxHealth * (1 + Config.OVERHEAL_PERCENTAGE)
    local newHealth = math.min(currentHealth + healAmount, overhealLimit)
    
    -- Apply healing
    humanoid.Health = newHealth
    
    print(`RemM1: Healed {targetEntity.name} for {newHealth - currentHealth} HP (${currentHealth} -> ${newHealth})`)
    return true
end

-- Primary ability request handler - called by CategoryHandler for Primary abilities
function Server.OnRequest(ctx: Types.SharedAbilityContext): Types.AbilityResult
    local casterEntity = getEntityFromPlayerId(ctx.playerId)
    if not casterEntity then
        return {
            success = false,
            reason = "Invalid caster entity",
        }
    end
    
    -- Get target position from context
    local targetPosition = ctx.inputData.target
    if not targetPosition then
        return {
            success = false,
            reason = "No target position provided",
        }
    end
    
    -- Validate range (works for both players and NPCs)
    local casterCharacterData = CharacterManager:GetCharacterData(casterEntity)
    if casterCharacterData and casterCharacterData.Character and casterCharacterData.Character.PrimaryPart then
        local distance = (casterCharacterData.Character.PrimaryPart.Position - targetPosition).Magnitude
        if distance > Config.ATTACK_RANGE then
            return {
                success = false,
                reason = "Target out of range",
            }
        end
    end
    
    -- Try to find target entity by position
    local targetEntity: EntityRef? = nil
    
    -- First try to find a player target
    if casterEntity.entityType == "Player" and casterEntity.player then
        local targetPlayer = Targeting:GetTarget(casterEntity.player)
        if targetPlayer and targetPlayer:IsA("Model") then
            -- Try to find the associated player
            local player = Players:GetPlayerFromCharacter(targetPlayer)
            if player then
                targetEntity = {
                    entityType = "Player",
                    player = player,
                    npcId = nil,
                    name = player.Name,
                    userId = player.UserId
                }
            else
                local playerId = targetPlayer:FindFirstChild("PlayerId")
                local npcId = (playerId and playerId:IsA("IntValue") and playerId.Value) or -1
                targetEntity = {
                    entityType = "NPC",
                    player = nil,
                    npcId = targetPlayer.Name,
                    name = targetPlayer.Name,
                    userId = npcId
                }
            end
        end
    end
    
    -- If no direct target found, try to find entity at target position
    if not targetEntity then
        -- This is a simplified approach - in practice, you'd want a more sophisticated
        -- system for finding entities at specific positions
        for _, player in Players:GetPlayers() do
            if player.Character and player.Character.PrimaryPart then
                local playerPos = player.Character.PrimaryPart.Position
                local distance = (playerPos - targetPosition).Magnitude
                if distance <= Config.HEAL_RANGE_MULTIPLIER * Config.ATTACK_RANGE then
                    targetEntity = {
                        entityType = "Player",
                        player = player,
                        npcId = nil,
                        name = player.Name,
                        userId = player.UserId
                    }
                    break
                end
            end
        end
    end
    
    -- Validate target entity
    if not targetEntity then
        return {
            success = false,
            reason = "No valid target found at position",
        }
    end
    
    -- Validate that the target can be healed
    if not validateHealTarget(targetEntity) then
        return {
            success = false,
            reason = "Target cannot be healed",
        }
    end
    
    -- Apply healing effect
    if not applyHealing(targetEntity, Config.HEAL_AMOUNT) then
        return {
            success = false,
            reason = "Failed to apply healing",
        }
    end
    
    -- Return success (no cooldown since Primary uses ammo system)
    return {
        success = true,
        -- No cooldowns returned since Primary abilities use ammo instead
    }
end

-- Shared module accessor - required by CategoryHandler
function Server.GetSharedModule()
    local sharedMod = require(script.Parent.Shared)
    
    sharedMod.GetAssets = function()
        return script.Parent.Assets
    end
    
    sharedMod.GetConfig = function()
        -- Return config with proper type compatibility
        local configWithOptionalFields = Config :: any
        return configWithOptionalFields
    end
    
    return sharedMod
end

-- Category getter - used by CategoryHandler to route to appropriate method
function Server.getAbilityCategory()
    return Config.ABILITY_CATEGORY
end

-- Validate configuration for category system compatibility
function Server.validateConfig()
    local category = Config.ABILITY_CATEGORY
    if category == "Primary" then
        -- Primary abilities should have MAX_AMMO and RELOAD_TIME, not COOLDOWN_TIME
        return Config.MAX_AMMO ~= nil and Config.RELOAD_TIME ~= nil
    else
        -- Other categories should have COOLDOWN_TIME
        -- Use type assertion since Config might not have this field for Primary abilities
        local configWithCooldown = Config :: any
        return configWithCooldown.COOLDOWN_TIME ~= nil
    end
end

return Server
