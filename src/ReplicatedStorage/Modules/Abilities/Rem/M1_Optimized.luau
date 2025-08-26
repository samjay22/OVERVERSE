--!strict
-- M1 Ability - Optimized for continuous fire with burst mechanics

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Types = require(game.ReplicatedStorage.Modules.Types.AbilityTypes)

-- Configuration
local Config = {
    -- Timing
    ShotCooldown = 0.65,      -- Time between shots
    BurstCooldown = 1.0,      -- Time between bursts
    ReloadTime = 5.0,         -- Full reload time
    
    -- Resources
    BurstSize = 3,            -- Shots per burst
    Magazine = 12,            -- Total shots before reload
    
    -- Combat
    Range = 100,              -- Max projectile range
    ProjectileSpeed = 100,    -- Studs per second
    
    -- Input
    Enum = Enum.UserInputType.MouseButton1,
    
    -- Visuals
    AnimationList = {"1", "2", "3"},
}

-- State tracking per player
local PlayerStates = {} :: {[number]: {
    ammo: number,
    burst: number,
    lastShotTime: number,
    burstEndTime: number,
    reloadEndTime: number,
}}

local function getOrCreateState(userId: number)
    if not PlayerStates[userId] then
        PlayerStates[userId] = {
            ammo = Config.Magazine,
            burst = Config.BurstSize,
            lastShotTime = 0,
            burstEndTime = 0,
            reloadEndTime = 0,
        }
    end
    return PlayerStates[userId]
end

local Ability: Types.AbilityModule = {
    Name = "M1_Optimized",
    Enum = Config.Enum,
    
    Client = {
        InternalState = {
            Animations = {},
            Effects = {},
            Sounds = {},
        },
        AbilityEffects = game.ReplicatedStorage.Modules.Effects,
        AbilitySounds = Instance.new("Folder"),
        
        OnUse = function(self, player: Player): boolean
            local state = getOrCreateState(player.UserId)
            local currentTime = tick()
            
            -- Check reload cooldown
            if currentTime < state.reloadEndTime then
                return true -- Stay active but can't shoot
            end
            
            -- Check burst cooldown
            if currentTime < state.burstEndTime then
                return true -- Stay active but can't shoot
            end
            
            -- Check shot cooldown
            if currentTime - state.lastShotTime < Config.ShotCooldown then
                return true -- Stay active, waiting for next shot
            end
            
            -- Check resources
            if state.ammo <= 0 or state.burst <= 0 then
                return true -- Stay active but need reload/cooldown
            end
            
            -- Fire shot
            state.ammo = state.ammo - 1
            state.burst = state.burst - 1
            state.lastShotTime = currentTime
            
            -- Visual feedback
            print(`Shot fired! Burst: {state.burst}/{Config.BurstSize}, Ammo: {state.ammo}/{Config.Magazine}`)
            
            -- Handle resource depletion
            if state.ammo <= 0 then
                -- Out of ammo - full reload
                state.reloadEndTime = currentTime + Config.ReloadTime
                task.delay(Config.ReloadTime, function()
                    state.ammo = Config.Magazine
                    state.burst = Config.BurstSize
                    print("Reload complete!")
                end)
            elseif state.burst <= 0 then
                -- Burst depleted - burst cooldown
                state.burstEndTime = currentTime + Config.BurstCooldown
                task.delay(Config.BurstCooldown, function()
                    state.burst = Config.BurstSize
                    print("Burst recharged!")
                end)
            end
            
            -- Continue ability (return true to keep checking for next shot)
            return true
        end,
        
        OnCancel = function(self, player: Player): boolean
            -- Ability naturally completes, no forced cancellation needed
            return false
        end,
        
        OnReplicate = function(self, player: Player): boolean
            -- Handle replication for other players
            return true
        end,
        
        GetCharacterAnimations = function(self, player: Player)
            return player.Character and player.Character:FindFirstChild("Animations")
        end,
        
        OnStateSync = function(self, syncData: {[string]: any}): boolean
            -- Handle state synchronization from server
            return true
        end,
    },
    
    Server = {
        InternalState = {},
        
        Validate = function(self, player: Player, ctxExtra: any?): boolean
            local state = getOrCreateState(player.UserId)
            local currentTime = tick()
            
            -- Same validation as client
            if currentTime < state.reloadEndTime then
                return false
            end
            
            if currentTime < state.burstEndTime then
                return false
            end
            
            if currentTime - state.lastShotTime < Config.ShotCooldown then
                return false
            end
            
            if state.ammo <= 0 or state.burst <= 0 then
                return false
            end
            
            -- Update server state
            state.ammo = state.ammo - 1
            state.burst = state.burst - 1
            state.lastShotTime = currentTime
            
            -- Handle resource depletion
            if state.ammo <= 0 then
                state.reloadEndTime = currentTime + Config.ReloadTime
                task.delay(Config.ReloadTime, function()
                    if PlayerStates[player.UserId] then
                        PlayerStates[player.UserId].ammo = Config.Magazine
                        PlayerStates[player.UserId].burst = Config.BurstSize
                    end
                end)
            elseif state.burst <= 0 then
                state.burstEndTime = currentTime + Config.BurstCooldown
                task.delay(Config.BurstCooldown, function()
                    if PlayerStates[player.UserId] then
                        PlayerStates[player.UserId].burst = Config.BurstSize
                    end
                end)
            end
            
            return true
        end,
        
        OnUpdate = function(self, dt: number): boolean
            -- Clean up disconnected players
            for userId, _ in pairs(PlayerStates) do
                local player = Players:GetPlayerByUserId(userId)
                if not player then
                    PlayerStates[userId] = nil
                end
            end
            return true
        end,
        
        _SyncToClient = function(self, player: Player, sm: any): boolean
            -- Sync handled through network events
            return true
        end,
    }
}

-- Clean up on player leaving
Players.PlayerRemoving:Connect(function(player)
    PlayerStates[player.UserId] = nil
end)

return Ability