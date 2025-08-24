local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Types = require(game.ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)
local TargetingModule = require(ReplicatedStorage.Modules.CoreClient.Targeting)
local CharacterManager = require(game.ServerStorage.Modules.Entities.Character.CharacterManager)
local Configs = require(script.Parent.Config)
local Shared = require(script.Parent.Shared)

-- Get or create the targeting system instance
local Targeting = TargetingModule.new()

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult
export type EntityRef = AbilityTypes.EntityRef

-- Performance optimization: cache frequently used functions
local math_floor = math.floor

local function calculateImpactTime(position: Vector3, target: Vector3, speed: number): number
    return (position - target).Magnitude / speed
end

-- Legacy targeting function (not used in current implementation)
local function _getEntityTarget(entity: EntityRef): Model?
    local targetKey: string?
    
    if entity.entityType == "Player" and entity.player then
        targetKey = entity.player:GetAttribute("targetKey") :: string?
    elseif entity.entityType == "NPC" then
        -- For NPCs, we could store targeting data differently
        -- For now, assume NPCs don't have complex targeting
        return nil
    end
    
    if not targetKey then return nil end
    
    local targets = CollectionService:GetTagged(targetKey)
    return targets[1]
end

local function isValidTarget(target: any): boolean
    if not target then return false end
    if not target:IsA("Model") then return false end
    
    local humanoid = target:FindFirstChild("Humanoid")
    if not humanoid then return false end
    
    return humanoid.Health > 0
end

local function calculateDamage(baseDamage: number, distance: number): number
    -- Damage falloff based on distance
    local maxRange = Configs.ATTACK_RANGE
    local falloffFactor = math.max(0.5, 1 - (distance / maxRange) * 0.3)
    return math_floor(baseDamage * falloffFactor)
end

local function applyDamage(target: Model, damage: number, sourcePlayer: Player): boolean
    local humanoid = target:FindFirstChild("Humanoid")
    if not humanoid then return false end
    
    -- Get target entity
    local targetEntity: EntityRef?
    
    -- Try to find the associated player for the target
    local targetPlayer = Players:GetPlayerFromCharacter(target)
    if targetPlayer then
        targetEntity = {
            entityType = "Player",
            player = targetPlayer,
            npcId = nil,
            name = targetPlayer.Name,
            userId = targetPlayer.UserId
        }
    else
        -- This is likely an NPC model
        local playerId = target:FindFirstChild("PlayerId")
        local npcId = (playerId and playerId:IsA("IntValue") and playerId.Value) or -1
        targetEntity = {
            entityType = "NPC",
            player = nil,
            npcId = target.Name,
            name = target.Name,
            userId = npcId
        }
    end
    
    if not targetEntity then return false end
    
    -- Apply damage through CharacterManager
    local actualDamage = CharacterManager:TakeDamage(targetEntity, damage)
    if actualDamage <= 0 then return false end
    
    -- Create a damage event for tracking
    local damageValue = Instance.new("NumberValue")
    damageValue.Name = "Damage"
    damageValue.Value = actualDamage
    damageValue:SetAttribute("Source", sourcePlayer.UserId)
    damageValue:SetAttribute("AbilityId", "RemE")
    damageValue.Parent = target

    print(`${target.Name} hit by ${sourcePlayer.Name} for ${actualDamage} damage! (intended: ${damage}, via CharacterManager)`)
    
    -- Clean up the damage value
    game:GetService("Debris"):AddItem(damageValue, 1)
    
    return true
end

local function handleHit(target: Model?, damage: number, sourcePlayer: Player, impactPosition: Vector3): boolean
    if not isValidTarget(target) then 
        print(`Invalid target for ${sourcePlayer.Name}'s RemE ability`)
        return false 
    end
    
    local validTarget = target :: Model
    
    -- Calculate distance-based damage
    local targetPosition: Vector3
    if validTarget.PrimaryPart then
        targetPosition = validTarget.PrimaryPart.Position
    else
        -- Fallback to model's center if no PrimaryPart
        local cf, _size = validTarget:GetBoundingBox()
        targetPosition = cf.Position
    end
    
    local distance = (impactPosition - targetPosition).Magnitude
    local actualDamage = calculateDamage(damage, distance)
    
    return applyDamage(validTarget, actualDamage, sourcePlayer)
end

local function processAbility(ctx: Types.SharedAbilityContext): Types.AbilityResult
    -- Enhanced validation using shared module
    local isValid, errorMessage = Shared.IsValid(ctx)
    if not isValid then
        warn(`RemE ability validation failed: ${errorMessage or "Unknown reason"}`)
        return {
            success = false,
        }
    end
    
    local player = game.Players:GetPlayerByUserId(ctx.playerId)
    if not player then
        warn("Player not found for RemE ability")
        return {
            success = false,
        }
    end
    
    local character = player.Character
    if not character then
        warn("Character not found for RemE ability")
        return {
            success = false,
        }
    end
    
    -- Check if ability requires a target and validate target
    if Configs.REQUIRES_TARGET then
        local playerTarget = Targeting:GetTarget(player)
        if not playerTarget then
            warn(`RemE ability requires a target but ${player.Name} has no target`)
            return {
                success = false,
            }
        end
        
        -- Validate target is still valid
        if not isValidTarget(playerTarget) then
            warn(`RemE ability target is invalid for ${player.Name}`)
            -- Clear the invalid target
            Targeting:ClearTarget(player)
            return {
                success = false,
            }
        end
        
        -- Validate target is within range
        local targetPosition: Vector3
        if playerTarget.PrimaryPart then
            targetPosition = playerTarget.PrimaryPart.Position
        else
            local cf, _size = playerTarget:GetBoundingBox()
            targetPosition = cf.Position
        end
        
        local playerPosition = character.HumanoidRootPart and character.HumanoidRootPart.Position or character:GetPivot().Position
        local distance = (playerPosition - targetPosition).Magnitude
        
        if distance > Configs.ATTACK_RANGE then
            warn(`RemE ability target is out of range for ${player.Name} (${distance} > ${Configs.ATTACK_RANGE})`)
            return {
                success = false,
            }
        end
    end
    
    -- Get wand position for accurate calculation
    local wand = character:FindFirstChild("Wand..")
    if not wand or not wand:FindFirstChild("Part") then
        warn("Wand not found for RemE ability")
        return {
            success = false,
        }
    end
    
    local startPos = wand.Part.Position
    local targetPos = ctx.inputData.target
    
    -- Calculate impact time and schedule damage
    local impactTime = calculateImpactTime(startPos, targetPos, Configs.PROJECTILE_SPEED)
    
    -- Schedule the damage application
    task.delay(impactTime, function()
        -- Re-validate player still exists when impact occurs
        local currentPlayer = Players:GetPlayerByUserId(ctx.playerId)
        if not currentPlayer then return end
        
        -- Check if the player has a target using the targeting system
        local playerTarget = Targeting:GetTarget(currentPlayer)
        
        local hitTargets = {}
        local searchRadius = 8 -- studs to search for targets around impact
        
        -- If player has a specific target, prioritize it if it's within range
        if playerTarget and playerTarget:FindFirstChild("HumanoidRootPart") then
            local distance = (playerTarget.HumanoidRootPart.Position - targetPos).Magnitude
            if distance <= searchRadius then
                -- Don't hit the caster
                local targetPlayer = Players:GetPlayerFromCharacter(playerTarget)
                if not targetPlayer or targetPlayer.UserId ~= ctx.playerId then
                    table.insert(hitTargets, playerTarget)
                    print(`RemE: Using targeted player/NPC: ${playerTarget.Name}`)
                end
            end
        end
        
        -- If no targeted entity was hit, search for any valid targets in range
        if #hitTargets == 0 then
            for _, obj in workspace:GetChildren() do
                if obj:IsA("Model") and obj:FindFirstChild("Humanoid") and obj:FindFirstChild("HumanoidRootPart") then
                    local distance = (obj.HumanoidRootPart.Position - targetPos).Magnitude
                    if distance <= searchRadius then
                        -- Don't hit the caster
                        local targetPlayer = Players:GetPlayerFromCharacter(obj)
                        if not targetPlayer or targetPlayer.UserId ~= ctx.playerId then
                            table.insert(hitTargets, obj)
                        end
                    end
                end
            end
        end
        
        print(`RemE: Found {#hitTargets} valid targets to damage`)
        
        -- Apply damage to all targets hit
        local anyHitSuccess = false
        for _, target in hitTargets do
            local hitSuccess = handleHit(target, Configs.DAMAGE, currentPlayer, targetPos)
            if hitSuccess then
                anyHitSuccess = true
            end
        end
        
        -- Ensure the caster stays grounded (prevent flying effect)
        if currentPlayer.Character and currentPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local humanoid = currentPlayer.Character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.PlatformStand = false
                humanoid.Sit = false
                -- Reset any unusual velocity
                currentPlayer.Character.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(
                    currentPlayer.Character.HumanoidRootPart.AssemblyLinearVelocity.X,
                    math.min(currentPlayer.Character.HumanoidRootPart.AssemblyLinearVelocity.Y, 0),
                    currentPlayer.Character.HumanoidRootPart.AssemblyLinearVelocity.Z
                )
            end
        end
        
        if not anyHitSuccess and #hitTargets == 0 then
            print(`RemE ability missed - no targets found at impact position for ${currentPlayer.Name}`)
        end
    end)
    
    -- Return success with cooldown
    return {
        success = true,
        cooldowns = { 
            [tostring(ctx.abilityId)] = ctx.timestamp + Configs.COOLDOWN_TIME 
        },
    }
end

local Server : Types.ServerAbility = {
    OnRequest = processAbility,
    GetSharedModule = function()
        error("Should be injected")
    end
}

return Server