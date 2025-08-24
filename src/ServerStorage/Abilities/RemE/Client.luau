local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Types = require(game.ReplicatedStorage.Modules.Types.ClientAbilityTypes)

local Configs = require(script.Parent.Config)

local Assets : typeof(script.Parent.Assets) = script.Parent.Assets

export type SharedAbilityContext = Types.SharedAbilityContext
export type AbilityResult = Types.AbilityResult

-- Forward declarations
local executeAttack: (number?, Vector3?) -> ()
local playCharacterAnimation: (string, Vector3?) -> AnimationTrack?

-- Precise Fire trigger helper
local function connectFireTrigger(track: AnimationTrack, targetPosition: Vector3?)
    local fired = false
    local disconnects: { RBXScriptConnection } = {}

    local function fireOnce()
        if fired then return end
        fired = true
        task.spawn(executeAttack, nil, targetPosition) -- local launch with stored target
    end

    -- Prefer Animation Events (Markers)
    local ok, markerSignal = pcall(function()
        return track:GetMarkerReachedSignal("Fire")
    end)
    if ok and markerSignal then
        table.insert(disconnects, markerSignal:Connect(fireOnce))
    end

    -- Also support named keyframe "Fire"
    table.insert(disconnects, track.KeyframeReached:Connect(function(name)
        if name == "Fire" then fireOnce() end
    end))

    -- Fallback: halfway if neither fires in time
    task.delay(math.max(0, track.Length * 0.5), function()
        fireOnce()
    end)

    -- Cleanup
    table.insert(disconnects, track.Stopped:Connect(function()
        for _, conn in ipairs(disconnects) do
            conn:Disconnect()
        end
        table.clear(disconnects)
    end))
end

-- Helper function to find and play animations (updated to use "Fire" timing)
playCharacterAnimation = function(animName: string, targetPosition: Vector3?): AnimationTrack?
    local character = Players.LocalPlayer.Character
    if not character then return nil end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end
    
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return nil end
    
    -- Find animation
    local animTag = tostring(Players.LocalPlayer.UserId) .. "_Animations"
    local animFolder = CollectionService:GetTagged(animTag)[1]
    local anim = animFolder and animFolder:FindFirstChild(animName) :: Animation?
    if not anim then return nil end
    
    -- Load and play animation
    local track = animator:LoadAnimation(anim)
    track.Priority = 5
    pcall(function() track.Looped = false end)

    -- Hook precise trigger with target position
    connectFireTrigger(track, targetPosition)
    
    track:Play(.5, 1, 1)
    return track
end

local Client : Types.ClientAbility = {
    -- Main execution function called by CategoryHandler
    Execute = function(context: SharedAbilityContext)
        -- Call the OnCast function for backward compatibility
        Client.OnCast(context, nil)
        
        return {
            success = true,
            message = "RemE executed"
        }
    end,
    
    -- Validation function
    Validate = function(context: SharedAbilityContext): Types.ValidationResult
        local character = Players.LocalPlayer.Character
        if not character then
            return {
                success = false,
                reason = "No character"
            }
        end
        
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            return {
                success = false,
                reason = "Character is dead"
            }
        end
        
        return {
            success = true
        }
    end,
    
    OnRequest = function(ctx: SharedAbilityContext): AbilityResult
        return {
            success = true,
            cooldowns = { [tostring(ctx.abilityId)] = ctx.timestamp + Configs.COOLDOWN_TIME },
        }
    end,
    
    OnReplicate = function(ctx: SharedAbilityContext, serverData: any?)
        -- Handle replication logic for other players seeing the spell
        if not serverData or not serverData.success then return end
        
        local castingPlayer : Player = game.Players:GetPlayerByUserId(ctx.playerId)
        local localPlayer = game.Players.LocalPlayer
        
        -- Only replicate for other players (not the caster)
        if castingPlayer == localPlayer then return end
        
        local targetPosition = ctx.inputData.target
        task.spawn(executeAttack, ctx and ctx.timestamp, targetPosition)
    end,
    OnCast = function(ctx: SharedAbilityContext, serverData: any?)
        -- Local client: play animation which will trigger attack at precise timing
        local targetPosition = ctx.inputData.target
        local animationName : string = Configs.ANIMATION
        
        -- Play animation with precise fire timing
        playCharacterAnimation(animationName, targetPosition)
    end,
    OnCancel = function(ctx: SharedAbilityContext, reason: string?)
        -- Handle ability cancellation
        local castingPlayer : Player = game.Players:GetPlayerByUserId(ctx.playerId)
        if not castingPlayer then return end
        
        -- Find and clean up any active spell projectiles for this player
        for _, obj in pairs(workspace:GetChildren()) do
            if (obj.Name == "SmokeProjectile" or obj.Name == "CastSmokeSpell") and obj:GetAttribute("CasterId") == ctx.playerId then
                -- Stop any particle effects
                if obj:FindFirstChild("Attachment") then
                    local attachment = obj.Attachment
                    for _, effect in pairs(attachment:GetChildren()) do
                        if effect:IsA("ParticleEmitter") then
                            effect.Enabled = false
                        end
                    end
                end
                
                -- Clean up the projectile
                Debris:AddItem(obj, 0.1)
            end
        end
        
        print(`RemE ability cancelled for ${castingPlayer.Name}: ${reason or "Unknown reason"}`)
    end,
    GetSharedModule = function()
        error("Should be injected")
    end
}

-- Helper function to create and animate projectile
function executeAttack(castTimestamp: number?, targetPosition: Vector3?)
    if not targetPosition then
        warn("No target position provided")
        return
    end
    
    local character = Players.LocalPlayer.Character
    if not character or not character.PrimaryPart then
        warn("No character or PrimaryPart")
        return 
    end

    local wand = character:FindFirstChild("Wand..")
    if not wand or not wand:FindFirstChild("Part") then 
        warn("Wand not found for player:", Players.LocalPlayer.Name)
        return 
    end

    local startPos = wand.Part.Position
    local endPos = targetPosition
    local direction = (endPos - startPos).Unit
    local distance = (endPos - startPos).Magnitude
    
    -- Create the projectile
    local projectile = Assets.SmokeProjectile:Clone()
    projectile.CanCollide = false
    projectile.Anchored = true
    projectile.CFrame = CFrame.lookAt(startPos, endPos)
    projectile:SetAttribute("CasterId", Players.LocalPlayer.UserId)
    projectile.Parent = workspace
    
    -- Add initial visual effects
    if projectile:FindFirstChild("Attachment") then
        for _, effect in pairs(projectile:GetDescendants()) do
            if effect:IsA("ParticleEmitter") then
                effect:Emit(5)
            end
        end
    end
    
    -- Calculate travel time and animation
    local travelTime = distance / Configs.PROJECTILE_SPEED
    local startTime = time()
    
    -- Handle latency compensation for replication
    local initialProgress = 0
    if typeof(castTimestamp) == "number" then
        initialProgress = math.clamp((time() - castTimestamp) / travelTime, 0, 1)
        startTime = startTime - (initialProgress * travelTime)
    end
    
    local connection: RBXScriptConnection
    local impactFired = false
    
    connection = RunService.Heartbeat:Connect(function()
        local elapsed = time() - startTime
        local progress = math.clamp(elapsed / travelTime, 0, 1)
        
    
        -- Stop movement particles and start impact particles
        if projectile:FindFirstChild("Attachment") then
            for _, effect in pairs(projectile:GetDescendants()) do
                if effect:IsA("ParticleEmitter") then
                    effect:Emit(10)
                end
            end
        end

        if progress >= 1 then
            if not impactFired then
                impactFired = true
                projectile.CFrame = CFrame.new(endPos)
                
                -- Create impact effect
                local impactEffect = Assets.SmokeHit:Clone()
                impactEffect.CFrame = CFrame.new(endPos)
                impactEffect.Parent = workspace
                
                -- Create damage indicator (similar to heal indicator)
                -- Check for any target that might have been hit at this position
                local damageValue = Configs.DAMAGE -- Default damage value
                
                -- Try to find if a character was hit near this position to get actual damage
                local charactersInArea = {}
                for _, obj in pairs(workspace:GetChildren()) do
                    if obj:IsA("Model") and obj:FindFirstChild("Humanoid") and obj:FindFirstChild("HumanoidRootPart") then
                        local distance = (obj.HumanoidRootPart.Position - endPos).Magnitude
                        if distance <= 10 then -- Within reasonable distance
                            table.insert(charactersInArea, obj)
                        end
                    end
                end
                
                -- Check if any of these characters have a recent damage value
                for _, character in pairs(charactersInArea) do
                    local recentDamage = character:FindFirstChild("Damage")
                    if recentDamage and recentDamage:IsA("NumberValue") and recentDamage:GetAttribute("AbilityId") == "RemE" then
                        damageValue = recentDamage.Value
                        break
                    end
                end
                
                local damageIndicator = Instance.new("BillboardGui")
                damageIndicator.Name = "DamageIndicator"
                damageIndicator.Size = UDim2.new(0, 100, 0, 50)
                damageIndicator.StudsOffset = Vector3.new(0, 3, 0)
                damageIndicator.Parent = workspace
                
                local textLabel = Instance.new("TextLabel")
                textLabel.Size = UDim2.new(1, 0, 1, 0)
                textLabel.BackgroundTransparency = 1
                textLabel.Text = `-${damageValue} DMG`
                textLabel.TextColor3 = Color3.new(1, 0.2, 0.2) -- Red color for damage
                textLabel.TextScaled = true
                textLabel.Font = Enum.Font.SourceSansBold
                textLabel.Parent = damageIndicator
                
                -- Position the damage indicator at impact position
                damageIndicator.StudsOffset = Vector3.new(0, 3, 0)
                local temp = Instance.new("Part")
                temp.Anchored = true
                temp.CanCollide = false
                temp.Transparency = 1
                temp.Size = Vector3.new(0.1, 0.1, 0.1)
                temp.CFrame = CFrame.new(endPos)
                temp.Parent = workspace
                damageIndicator.Adornee = temp
                
                -- Animate the damage indicator
                local tween = game:GetService("TweenService"):Create(damageIndicator, 
                    TweenInfo.new(2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
                    {StudsOffset = Vector3.new(0, 6, 0)}
                )
                
                local fadeTween = game:GetService("TweenService"):Create(textLabel,
                    TweenInfo.new(2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
                    {TextTransparency = 1}
                )
                
                tween:Play()
                fadeTween:Play()
                
                -- Clean up damage indicator
                Debris:AddItem(temp, 2.5)
                Debris:AddItem(damageIndicator, 2.5)
                
                -- Stop movement particles and start impact particles
                if projectile:FindFirstChild("Attachment") then
                    for _, effect in pairs(projectile:GetDescendants()) do
                        if effect:IsA("ParticleEmitter") then
                            effect:Emit(10)
                        end
                    end
                end
                
                if impactEffect:FindFirstChild("Attachment") then
                    for _, effect in pairs(impactEffect:GetDescendants()) do
                        if effect:IsA("ParticleEmitter") then
                            effect:Emit(10)
                        end
                    end
                end
                
                -- Clean up
                Debris:AddItem(projectile, 0.1)
                -- Debris:AddItem(impactEffect, 2)
            end
            connection:Disconnect()
            return
        end
        
        -- Animate projectile position
        local currentPos = startPos:Lerp(endPos, progress)
        projectile.CFrame = CFrame.lookAt(currentPos, currentPos + direction)
    end)
    
    -- Backup cleanup
    Debris:AddItem(projectile, travelTime + 0.5)
end

return Client