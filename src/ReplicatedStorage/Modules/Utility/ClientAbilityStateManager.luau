--!strict
-- ClientAbilityStateManager: Centralized state management for all client abilities
-- Provides single source of truth for ability states, resources, and cooldowns

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateManager = require(script.Parent.StateManager)
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

-- Import configuration modules
local Configuration = ReplicatedStorage.Modules:WaitForChild("Configuration")
local ResourceTypes = require(Configuration:WaitForChild("ResourceTypes"))
local AbilityConfiguration = require(Configuration:WaitForChild("AbilityConfiguration"))

type AbilityCategory = Types.AbilityCategory
type AbilityConfig = Types.AbilityConfig

export type ResourceState = ResourceTypes.ResourceState & {
    abilityId: string,
    category: AbilityCategory,
    ready: boolean,
    fireRate: number?,
}

export type ClientAbilityStateManager = {
    -- Core methods
    RegisterAbility: (self: ClientAbilityStateManager, abilityId: string, config: AbilityConfig) -> (),
    UnregisterAbility: (self: ClientAbilityStateManager, abilityId: string) -> (),
    GetAbilityState: (self: ClientAbilityStateManager, abilityId: string) -> ResourceState?,
    GetAllAbilityStates: (self: ClientAbilityStateManager) -> {[string]: ResourceState},
    
    -- Resource management
    UseAbility: (self: ClientAbilityStateManager, abilityId: string) -> boolean,
    StartReload: (self: ClientAbilityStateManager, abilityId: string) -> (),
    SetCooldown: (self: ClientAbilityStateManager, abilityId: string, duration: number) -> (),
    ResetAbility: (self: ClientAbilityStateManager, abilityId: string) -> (),
    
    -- State queries
    IsReady: (self: ClientAbilityStateManager, abilityId: string) -> boolean,
    GetRemainingCooldown: (self: ClientAbilityStateManager, abilityId: string) -> number,
    GetRemainingReloadTime: (self: ClientAbilityStateManager, abilityId: string) -> number,
    GetReloadProgress: (self: ClientAbilityStateManager, abilityId: string) -> number,
    
    -- Event subscriptions
    OnAbilityStateChanged: (self: ClientAbilityStateManager, abilityId: string, callback: (state: ResourceState) -> ()) -> () -> (),
    OnAnyAbilityStateChanged: (self: ClientAbilityStateManager, callback: (abilityId: string, state: ResourceState) -> ()) -> () -> (),
    
    -- Sync methods
    ApplyServerState: (self: ClientAbilityStateManager, abilityId: string, serverState: {[string]: any}) -> (),
    ApplyServerCooldowns: (self: ClientAbilityStateManager, cooldowns: {[string]: number}) -> (),
}

local ClientAbilityStateManager = {}
ClientAbilityStateManager.__index = ClientAbilityStateManager

function ClientAbilityStateManager.new(): ClientAbilityStateManager
    local self = setmetatable({}, ClientAbilityStateManager)
    
    -- Internal state management
    self._stateManager = StateManager.New()
    self._abilityConfigs = {} :: {[string]: AbilityConfig}
    self._updateConnection = nil :: RBXScriptConnection?
    self._listeners = {} :: {[string]: {(state: ResourceState) -> ()}}
    self._globalListeners = {} :: {(abilityId: string, state: ResourceState) -> ()}
    
    -- Start update loop
    self:_startUpdateLoop()
    
    return self :: any
end

function ClientAbilityStateManager:RegisterAbility(abilityId: string, config: AbilityConfig)
    if self._abilityConfigs[abilityId] then
        print(`[ClientAbilityStateManager] Ability {abilityId} already registered`)
        return
    end
    
    print(`[ClientAbilityStateManager] Registering ability {abilityId} with category {config.ABILITY_CATEGORY}`)
    self._abilityConfigs[abilityId] = config
    
    -- Get ability definition from configuration
    local abilityDef = AbilityConfiguration.GetAbility(abilityId)
    local resourceType = "cooldown"
    local resourceConfig = nil
    
    if abilityDef and abilityDef.resource then
        resourceType = abilityDef.resource.type
        resourceConfig = abilityDef.resource
    else
        -- Fallback to old logic
        if config.ABILITY_CATEGORY == "Passive" then
            resourceType = "cooldown"
            resourceConfig = {type = "cooldown", cooldownTime = 0}
        elseif config.ABILITY_CATEGORY == "Primary" and config.MAX_AMMO then
            resourceType = "ammo"
            resourceConfig = {
                type = "ammo",
                maxAmmo = config.MAX_AMMO,
                reloadTime = config.RELOAD_TIME or 5,
                autoReload = true,
                fireRate = config.FIRE_RATE,
            }
        else
            resourceType = "cooldown"
            resourceConfig = {
                type = "cooldown",
                cooldownTime = config.COOLDOWN_TIME or 1,
                fireRate = config.FIRE_RATE,
            }
        end
    end
    
    -- Create resource state using ResourceTypes
    local resourceState = ResourceTypes.CreateResource(resourceType, resourceConfig)
    if not resourceState then
        warn(`[ClientAbilityStateManager] Failed to create resource for {abilityId}`)
        return
    end
    
    -- Enhance with ability-specific fields
    local initialState: ResourceState = resourceState :: any
    initialState.abilityId = abilityId
    initialState.category = config.ABILITY_CATEGORY
    initialState.ready = ResourceTypes.CanUseResource(resourceState)
    initialState.fireRate = config.FIRE_RATE
    
    -- Register state
    self._stateManager:DefineState(abilityId, initialState)
    
    -- Notify listeners
    self:_notifyStateChange(abilityId, initialState)
end

function ClientAbilityStateManager:UnregisterAbility(abilityId: string)
    self._abilityConfigs[abilityId] = nil
    -- State remains for potential re-registration
end

function ClientAbilityStateManager:GetAbilityState(abilityId: string): ResourceState?
    local state = self._stateManager:Get(abilityId)
    if not state then
        -- Try to get config and register if exists
        local config = self._abilityConfigs[abilityId]
        if not config then
            print(`[ClientAbilityStateManager] No state for {abilityId} - not registered`)
        end
    end
    if state and typeof(state) == "table" then
        return state :: ResourceState
    end
    return nil
end

function ClientAbilityStateManager:GetAllAbilityStates(): {[string]: ResourceState}
    local states = {}
    for abilityId, _ in pairs(self._abilityConfigs) do
        local state = self:GetAbilityState(abilityId)
        if state then
            states[abilityId] = state
        end
    end
    return states
end

function ClientAbilityStateManager:UseAbility(abilityId: string): boolean
    local state = self:GetAbilityState(abilityId)
    if not state then 
        -- If ability is not registered, allow it to be used (it will be registered on first use)
        print(`[ClientAbilityStateManager] {abilityId} not registered yet - allowing first use`)
        return true
    end
    
    -- Use precise server time for accuracy
    local now = workspace:GetServerTimeNow()
    
    -- Check fire rate FIRST with precise timing
    if state.fireRate then
        local timeSinceLastUse = now - (state.lastUseTime or 0)
        if timeSinceLastUse < state.fireRate then
            return false
        end
    end
    
    -- Check if resource allows use
    if not ResourceTypes.CanUseResource(state) then
        -- Auto-reload for ammo types if empty
        if state.type == "ammo" and state.current <= 0 and not state.isReloading then
            self:StartReload(abilityId)
        end
        return false
    end
    
    -- Use the resource
    local newState = ResourceTypes.UseResource(state)
    
    -- Update fire rate tracking
    newState.lastUseTime = now
    
    -- Update ready state
    newState.ready = ResourceTypes.CanUseResource(newState)
    
    -- Update state
    self._stateManager:Set(abilityId, newState)
    self:_notifyStateChange(abilityId, newState)
    
    -- Handle auto-reload for ammo types
    if newState.type == "ammo" and newState.current <= 0 then
        if newState.metadata and newState.metadata.autoReload then
            task.spawn(function()
                task.wait(0.1) -- Small delay for visual feedback
                self:StartReload(abilityId)
            end)
        end
    end
    
    return true
end

function ClientAbilityStateManager:StartReload(abilityId: string)
    local state = self:GetAbilityState(abilityId)
    if not state or state.type ~= "ammo" then return end
    
    -- Use ResourceTypes to start reload
    local newState = ResourceTypes.StartReload(state)
    if newState == state then
        return -- No change (already reloading or full)
    end
    
    newState.ready = false
    
    -- Update state
    self._stateManager:Set(abilityId, newState)
    self:_notifyStateChange(abilityId, newState)
end

function ClientAbilityStateManager:SetCooldown(abilityId: string, duration: number)
    local state = self:GetAbilityState(abilityId)
    if not state then return end
    
    local now = workspace:GetServerTimeNow()
    
    if state.type == "cooldown" then
        -- Set the cooldown by updating lastUseTime
        state.lastUseTime = now
        state.max = duration -- Update cooldown duration
        state.ready = false
    else
        -- For other abilities, just track last use time
        state.lastUseTime = now
    end
    
    self._stateManager:Set(abilityId, state)
    self:_notifyStateChange(abilityId, state)
end

function ClientAbilityStateManager:ResetAbility(abilityId: string)
    local state = self:GetAbilityState(abilityId)
    local config = self._abilityConfigs[abilityId]
    if not state or not config then return end
    
    -- Re-create initial state using ResourceTypes
    local abilityDef = AbilityConfiguration.GetAbility(abilityId)
    local resourceConfig = nil
    
    if abilityDef and abilityDef.resource then
        resourceConfig = abilityDef.resource
    else
        -- Fallback config
        resourceConfig = {
            type = state.type,
            maxAmmo = config.MAX_AMMO,
            reloadTime = config.RELOAD_TIME,
            cooldownTime = config.COOLDOWN_TIME,
        }
    end
    
    local resetState = ResourceTypes.CreateResource(state.type, resourceConfig)
    if resetState then
        resetState.abilityId = abilityId
        resetState.category = config.ABILITY_CATEGORY
        resetState.ready = ResourceTypes.CanUseResource(resetState)
        resetState.fireRate = config.FIRE_RATE
        
        self._stateManager:Set(abilityId, resetState)
        self:_notifyStateChange(abilityId, resetState)
    end
end

function ClientAbilityStateManager:IsReady(abilityId: string): boolean
    local state = self:GetAbilityState(abilityId)
    if not state then 
        -- If no state, ability is not registered yet - allow it to proceed
        -- It will be registered when executed
        return true
    end
    
    -- Check fire rate FIRST - this is the most important check
    if state.fireRate then
        local now = workspace:GetServerTimeNow()
        local timeSinceLastUse = now - (state.lastUseTime or 0)
        if timeSinceLastUse < state.fireRate then
            return false
        end
    end
    
    -- Then check resource availability
    return ResourceTypes.CanUseResource(state)
end

function ClientAbilityStateManager:GetRemainingCooldown(abilityId: string): number
    local state = self:GetAbilityState(abilityId)
    if not state or state.type ~= "cooldown" then return 0 end
    
    local now = workspace:GetServerTimeNow()
    local elapsed = now - (state.lastUseTime or 0)
    local remaining = (state.max or 0) - elapsed
    return math.max(0, remaining)
end

function ClientAbilityStateManager:GetRemainingReloadTime(abilityId: string): number
    local state = self:GetAbilityState(abilityId)
    if not state or state.type ~= "ammo" or not state.isReloading then return 0 end
    
    if state.metadata and state.reloadStartTime then
        local now = workspace:GetServerTimeNow()
        local elapsed = now - state.reloadStartTime
        local remaining = (state.metadata.reloadTime or 0) - elapsed
        return math.max(0, remaining)
    end
    
    return 0
end

function ClientAbilityStateManager:GetReloadProgress(abilityId: string): number
    local state = self:GetAbilityState(abilityId)
    if not state or state.type ~= "ammo" or not state.isReloading then return 0 end
    
    local displayInfo = ResourceTypes.GetDisplayInfo(state)
    if displayInfo then
        return displayInfo.progress
    end
    
    return 0
end

function ClientAbilityStateManager:OnAbilityStateChanged(abilityId: string, callback: (state: ResourceState) -> ()): () -> ()
    if not self._listeners[abilityId] then
        self._listeners[abilityId] = {}
    end
    
    table.insert(self._listeners[abilityId], callback)
    
    -- Call immediately with current state
    local currentState = self:GetAbilityState(abilityId)
    if currentState then
        callback(currentState)
    end
    
    -- Return disconnect function
    return function()
        local listeners = self._listeners[abilityId]
        if listeners then
            local index = table.find(listeners, callback)
            if index then
                table.remove(listeners, index)
            end
        end
    end
end

function ClientAbilityStateManager:OnAnyAbilityStateChanged(callback: (abilityId: string, state: ResourceState) -> ()): () -> ()
    table.insert(self._globalListeners, callback)
    
    -- Call immediately with all current states
    for abilityId, state in pairs(self:GetAllAbilityStates()) do
        callback(abilityId, state)
    end
    
    -- Return disconnect function
    return function()
        local index = table.find(self._globalListeners, callback)
        if index then
            table.remove(self._globalListeners, index)
        end
    end
end

function ClientAbilityStateManager:ApplyServerState(abilityId: string, serverState: {[string]: any})
    local state = self:GetAbilityState(abilityId)
    if not state then return end
    
    -- Apply server state updates based on resource type
    if state.type == "ammo" then
        if serverState.current ~= nil then
            state.current = serverState.current
        end
        if serverState.isReloading ~= nil then
            state.isReloading = serverState.isReloading
            if not serverState.isReloading then
                state.reloadStartTime = nil
            end
        end
    elseif state.type == "cooldown" then
        if serverState.lastUseTime ~= nil then
            state.lastUseTime = serverState.lastUseTime
        end
    elseif state.type == "energy" then
        if serverState.current ~= nil then
            state.current = serverState.current
        end
    elseif state.type == "charges" then
        if serverState.current ~= nil then
            state.current = serverState.current
        end
    elseif state.type == "heat" then
        if serverState.current ~= nil then
            state.current = serverState.current
        end
        if serverState.metadata and serverState.metadata.overheated ~= nil then
            if not state.metadata then
                state.metadata = {}
            end
            state.metadata.overheated = serverState.metadata.overheated
        end
    end
    
    -- Recalculate ready state
    state.ready = ResourceTypes.CanUseResource(state)
    
    self._stateManager:Set(abilityId, state)
    self:_notifyStateChange(abilityId, state)
end

function ClientAbilityStateManager:ApplyServerCooldowns(cooldowns: {[string]: number})
    local now = workspace:GetServerTimeNow()
    
    for abilityId, cooldownDuration in pairs(cooldowns) do
        local state = self:GetAbilityState(abilityId)
        if state then
            if state.type == "cooldown" then
                -- Set the cooldown by updating last use time
                state.lastUseTime = now
                state.max = cooldownDuration
                state.ready = false
                self._stateManager:Set(abilityId, state)
                self:_notifyStateChange(abilityId, state)
            end
        end
    end
end

-- Private methods
function ClientAbilityStateManager:_notifyStateChange(abilityId: string, state: ResourceState)
    -- Notify specific listeners
    local listeners = self._listeners[abilityId]
    if listeners then
        for _, callback in ipairs(listeners) do
            task.spawn(callback, state)
        end
    end
    
    -- Notify global listeners
    for _, callback in ipairs(self._globalListeners) do
        task.spawn(callback, abilityId, state)
    end
end

function ClientAbilityStateManager:_startUpdateLoop()
    -- Use Heartbeat for frame-perfect timing
    self._updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
        for abilityId, config in pairs(self._abilityConfigs) do
            local state = self:GetAbilityState(abilityId)
            if not state then continue end
            
            local previousReady = state.ready
            local previousState = state
            
            -- Update resource state using ResourceTypes system
            local updatedState = ResourceTypes.UpdateResource(state, deltaTime)
            
            -- Update ready state based on resource availability
            local newReady = ResourceTypes.CanUseResource(updatedState)
            
            -- Also check fire rate separately
            if newReady and updatedState.fireRate and updatedState.lastUseTime then
                local now = workspace:GetServerTimeNow()
                local timeSinceUse = now - updatedState.lastUseTime
                if timeSinceUse < updatedState.fireRate then
                    newReady = false
                end
            end
            
            updatedState.ready = newReady
            
            -- Only update if state actually changed
            if updatedState ~= previousState or newReady ~= previousReady then
                self._stateManager:Set(abilityId, updatedState)
                self:_notifyStateChange(abilityId, updatedState)
                
                -- Log important state changes
                if newReady and not previousReady then
                    if updatedState.type == "ammo" and updatedState.isReloading then
                        print(`[ClientAbilityStateManager] {abilityId} reload complete`)
                    elseif updatedState.type == "cooldown" then
                        print(`[ClientAbilityStateManager] {abilityId} cooldown complete`)
                    end
                end
            end
        end
    end)
end

function ClientAbilityStateManager:Destroy()
    if self._updateConnection then
        self._updateConnection:Disconnect()
        self._updateConnection = nil
    end
    
    table.clear(self._listeners)
    table.clear(self._globalListeners)
    table.clear(self._abilityConfigs)
end

-- Create singleton instance
local instance: ClientAbilityStateManager? = nil

return {
    GetInstance = function(): ClientAbilityStateManager
        if not instance then
            instance = ClientAbilityStateManager.new()
        end
        return instance :: ClientAbilityStateManager
    end,
    
    new = ClientAbilityStateManager.new,
}