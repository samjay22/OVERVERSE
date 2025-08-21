--!strict
local Players = game:GetService("Players")
local _CollectionService = game:GetService("CollectionService")
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
        -- NPC
        entity = {
            entityType = "NPC",
            player = nil,
            npcId = `NPC_{-playerId}`,
            name = `NPC_{-playerId}`,
            userId = playerId
        }
    end
    
    -- Cache the result if found
    if entity then
        entityCache[playerId] = entity
    end
    
    return entity
end

-- Helper function to check if target is a valid ally (for healing)
local function isValidHealTarget(casterEntity: EntityRef, targetEntity: EntityRef): boolean
    if not casterEntity or not targetEntity then
        print("RemM1: Invalid entities - caster or target is nil")
        return false
    end
    
    -- Allow self-healing for RemM1 (healing ability should work on self)
    -- if casterEntity.userId == targetEntity.userId then
    --     return false
    -- end
    
    -- Check if target is alive (works for both players and NPCs)
    local targetCharacterData = CharacterManager:GetCharacterData(targetEntity)
    if not targetCharacterData then
        print(`RemM1: No character data found for target {targetEntity.name}`)
        return false
    end
    
    if not targetCharacterData.Humanoid then
        print(`RemM1: No humanoid found for target {targetEntity.name}`)
        return false
    end
    
    if targetCharacterData.Humanoid.Health <= 0 then
        print(`RemM1: Target {targetEntity.name} is dead (Health: {targetCharacterData.Humanoid.Health})`)
        return false
    end
    
    print(`RemM1: Target {targetEntity.name} is valid for healing (Health: {targetCharacterData.Humanoid.Health})`)
    return true
end

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
    
    -- Try to find target entity by position (needs to be updated for unified system)
    -- For now, we'll use a simplified approach - in a real implementation, you'd want
    -- a better targeting system that works with both players and NPCs
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
                -- This is likely an NPC model
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
    
    if not targetEntity then
        return {
            success = false,
            reason = "No valid target found",
        }
    end
    
    -- Validate target is valid for healing
    if not isValidHealTarget(casterEntity, targetEntity) then
        return {
            success = false,
            reason = "Cannot heal this target",
        }
    end
    
    -- Apply healing using CharacterManager interface
    local currentHealth = CharacterManager:GetCharacterState(targetEntity, "Health") or 0
    
    -- Calculate heal amount with overheal capability
    local healAmount = Config.HEAL_AMOUNT
    local maxHealth = CharacterManager:GetCharacterState(targetEntity, "MaxHealth") or 100
    local overhealCap = maxHealth * (1 + Config.OVERHEAL_PERCENTAGE)
    
    -- Set the overheal cap in StateManager for HealCharacter to respect
    CharacterManager:SetCharacterState(targetEntity, "MaxHealth", overhealCap)
    
    -- Apply the healing using the new HealCharacter method
    local healSuccess = CharacterManager:HealCharacter(targetEntity, healAmount)
    if not healSuccess then
        return {
            success = false,
            reason = "Failed to apply healing",
        }
    end
    
    -- Get the actual new health after healing
    local newHealth = CharacterManager:GetCharacterState(targetEntity, "Health") or currentHealth
    
    -- Log healing for debugging
    local actualHeal = newHealth - currentHealth
    print(`RemM1: {casterEntity.name} healed {targetEntity.name} for {actualHeal} HP ({currentHealth} -> {newHealth})`)
    
    return {
        success = true,
        cooldowns = { [tostring(ctx.abilityId)] = ctx.timestamp + Config.COOLDOWN_TIME },
    }
end

-- Required interface function
function Server.GetSharedModule()
    return require(script.Parent.Shared)
end

return Server