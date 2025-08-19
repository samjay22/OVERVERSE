--!strict
-- Client-side Passive Ability Manager
-- Handles visual effects, UI updates, and client-side logic for passive abilities

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- local PassiveAbilities = require(ReplicatedStorage.Modules.PassiveAbilities) -- TODO: Enable when module exists

local Player = Players.LocalPlayer

local PassiveManager = {}
PassiveManager.__index = PassiveManager

function PassiveManager.new()
    local self = setmetatable({}, PassiveManager) :: any
    
    self.equippedPassives = {} :: {[string]: any}
    self.tickConnection = nil :: RBXScriptConnection?
    
    return self
end

-- Equip a passive ability
function PassiveManager:EquipPassive(passiveId: string)
    if self.equippedPassives[passiveId] then
        return -- Already equipped
    end

    -- TODO: Replace with actual PassiveAbilities.Get() call when module is ready
    local passiveModule = nil -- PassiveAbilities.Get(passiveId)
    if not passiveModule then
        warn(`Passive ability {passiveId} not found - PassiveAbilities module not yet implemented`)
        return
    end

    -- Store the passive module for later reference
    self.equippedPassives[passiveId] = passiveModule

    -- Get player's current state snapshot (simplified for now)
    local stateSnapshot = self:_getCurrentStateSnapshot()

    -- Call the passive's onEquip function
    local statModifiers = passiveModule.onEquip(Player.UserId, stateSnapshot)
    
    -- Apply visual effects or UI updates based on the passive
    self:_applyPassiveVisuals(passiveId, statModifiers)
    
    print(`Equipped passive ability: {passiveId}`)
end

-- Unequip a passive ability
function PassiveManager:UnequipPassive(passiveId: string)
    local passiveModule = self.equippedPassives[passiveId]
    if not passiveModule then
        return -- Not equipped
    end

    -- Get player's current state snapshot
    local stateSnapshot = self:_getCurrentStateSnapshot()

    -- Call the passive's onUnequip function
    passiveModule.onUnequip(Player.UserId, stateSnapshot)
    
    -- Remove visual effects
    self:_removePassiveVisuals(passiveId)
    
    -- Remove from equipped list
    self.equippedPassives[passiveId] = nil
    
    print(`Unequipped passive ability: {passiveId}`)
end

-- Update all equipped passives (called periodically)
function PassiveManager:Update(deltaTime: number)
    local stateSnapshot = self:_getCurrentStateSnapshot()
    
    for passiveId, passiveModule in pairs(self.equippedPassives) do
        if passiveModule.onTick then
            passiveModule.onTick(Player.UserId, stateSnapshot, deltaTime)
        end
    end
end

-- Start the passive manager
function PassiveManager:Start()
    if self.tickConnection then
        return -- Already started
    end
    
    self.tickConnection = RunService.Heartbeat:Connect(function(deltaTime)
        self:Update(deltaTime)
    end)
    
    print("Passive Manager started")
end

-- Stop the passive manager
function PassiveManager:Stop()
    if self.tickConnection then
        self.tickConnection:Disconnect()
    end
    self.tickConnection = nil
    
    -- Unequip all passives
    for passiveId in pairs(self.equippedPassives) do
        self:UnequipPassive(passiveId)
    end
    
    print("Passive Manager stopped")
end

-- Get current state snapshot (simplified)
function PassiveManager:_getCurrentStateSnapshot()
    local character = Player.Character
    local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?
    local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
    
    return {
        timestamp = tick(),
        position = rootPart and rootPart.Position,
        velocity = Vector3.new(0, 0, 0), -- TODO: Get actual velocity
        health = humanoid and humanoid.Health,
        stamina = 100, -- TODO: Get actual stamina from state manager
        cooldowns = {},
        effects = {},
        passiveModifiers = {},
    }
end

-- Apply visual effects for a passive (placeholder)
function PassiveManager:_applyPassiveVisuals(passiveId: string, statModifiers: {[string]: number}?)
    -- This is where you would add visual effects, particle systems, etc.
    -- For example, Keen might add a slight glow or particle effect to the player
    
    if passiveId == "Keen" then
        -- Add visual indicator for Keen passive
        print("Applying Keen visual effects...")
        -- TODO: Add actual visual effects
    end
end

-- Remove visual effects for a passive (placeholder)
function PassiveManager:_removePassiveVisuals(passiveId: string)
    if passiveId == "Keen" then
        -- Remove visual indicator for Keen passive
        print("Removing Keen visual effects...")
        -- TODO: Remove actual visual effects
    end
end

return PassiveManager
