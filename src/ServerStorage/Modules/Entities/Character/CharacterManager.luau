--!strict
-- CharacterManager - Optimized character management orchestrator
-- Performance-focused design with improved memory management and type safety

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)
local Constants = require(game.ReplicatedStorage.Modules.Utility.Constants)
local NetworkServer = require(game.ReplicatedStorage.Modules.Network.Server)
local LoadoutRegistry = require(game.ServerStorage.Modules.registry.Loadouts)

-- Import abstracted modules
local characterFolder = ServerStorage.Modules.Entities.Character
local CharacterAssetLoader = require(characterFolder.CharacterAssetLoader)
local CharacterEventManager = require(characterFolder.CharacterEventManager)
local ComponentManager = require(characterFolder.ComponentManager)
local CharacterFactory = require(characterFolder.CharacterFactory)
local CharacterLifecycle = require(characterFolder.CharacterLifecycle)
local CharacterUpdateLoop = require(characterFolder.CharacterUpdateLoop)
local CharacterRegistry = require(characterFolder.CharacterRegistry)

type internalCharacter = CharacterTypes.internalCharacter
type CharacterConfig = CharacterTypes.CharacterConfig
type CharacterData = CharacterTypes.Character
type EntityRef = CharacterTypes.EntityRef

-- Constants for optimization
local COMPONENT_NAMES = {
    HEALTH = "Health",
    STAMINA = "Stamina",
    MOVEMENT = "Movement",
    COMBAT = "Combat",
    EFFECT = "Effect",
    ABILITY = "Ability",
    WEAPON = "Weapon",
    INPUT = "Input",
    MOUSE = "Mouse",
}

local DEFAULT_CONFIG = {
    DefaultRespawnTime = Constants.DEFAULT_RESPAWN_TIME or 5,
    UpdateInterval = 1/60, -- 60 Hz for better balance between performance and responsiveness
    MaxCharacters = 100,
    EnableAutoRespawn = false,
    BatchUpdateSize = 10, -- Process characters in batches
}

-- Cache frequently used values
local mathMax = math.max
local mathMin = math.min
local tableInsert = table.insert
local tableClear = table.clear
local taskSpawn = task.spawn
local tableClone = table.clone
local tableFreeze = table.freeze

-- Memory pools for garbage collection optimization (declared before use)
local EVENT_POOL = {} :: {BindableEvent}
local CLEANUP_POOL = {} :: {{() -> ()}}

-- Performance constants
local MAX_POOL_SIZE = 50
local _DISTANCE_CULL_THRESHOLD = 500 -- studs
local _PRIORITY_UPDATE_DISTANCE = 100 -- studs for high priority updates

-- Memory pool utilities for optimization
local function _getPooledEvent(): BindableEvent
    if #EVENT_POOL > 0 then
        return table.remove(EVENT_POOL) :: BindableEvent
    end
    return Instance.new("BindableEvent")
end

local function _returnPooledEvent(event: BindableEvent)
    if #EVENT_POOL < MAX_POOL_SIZE then
        -- Clear the event before pooling
        table.insert(EVENT_POOL, event)
    else
        event:Destroy()
    end
end

local function _getPooledCleanupList(): {() -> ()}
    if #CLEANUP_POOL > 0 then
        local list = table.remove(CLEANUP_POOL) :: {() -> ()}
        table.clear(list)
        return list
    end
    return {}
end

local function _returnPooledCleanupList(list: {() -> ()})
    if #CLEANUP_POOL < MAX_POOL_SIZE then
        table.clear(list)
        table.insert(CLEANUP_POOL, list)
    end
end

-- Main CharacterManager class
local CharacterManager = {}
CharacterManager.__index = CharacterManager

-- Utility functions for entity handling
local function createEntityRef(input: Player | Model | EntityRef | number): EntityRef?
    if typeof(input) == "Instance" then
        if input:IsA("Player") then
            local player = input :: Player
            return {
                entityType = "Player",
                player = player,
                npcId = nil,
                name = player.Name,
                userId = player.UserId
            }
        elseif input:IsA("Model") then
            local model = input :: Model
            -- This is an NPC model
            local playerId = model:FindFirstChild("PlayerId")
            local npcUserId = (playerId and playerId:IsA("IntValue") and playerId.Value) or nil
            
            -- Generate unique negative userId for NPCs if not explicitly set
            if not npcUserId then
                -- Use a hash of the model name to generate consistent negative userIds
                local nameHash = 0
                for i = 1, #model.Name do
                    nameHash = nameHash + string.byte(model.Name, i)
                end
                npcUserId = -(nameHash + 1000) -- Ensure negative and avoid collision with -1
            end
            
            return {
                entityType = "NPC",
                player = nil,
                npcId = model.Name,
                name = model.Name,
                userId = npcUserId :: number
            }
        end
    elseif typeof(input) == "number" then
        -- Lookup by UserId
        if input > 0 then
            -- Player
            local player = Players:GetPlayerByUserId(input)
            if player then
                return createEntityRef(player)
            end
        else
            -- NPC
            return {
                entityType = "NPC",
                player = nil,
                npcId = `NPC_{-input}`,
                name = `NPC_{-input}`,
                userId = input
            }
        end
    elseif typeof(input) == "table" and input.entityType then
        -- Already an EntityRef
        return input :: EntityRef
    end
    return nil
end

local function getEntityUserId(entity: Player | EntityRef | number): number?
    if typeof(entity) == "Instance" and entity:IsA("Player") then
        return (entity :: Player).UserId
    elseif typeof(entity) == "number" then
        return entity
    elseif typeof(entity) == "table" and entity.userId then
        return (entity :: EntityRef).userId
    end
    return nil
end

export type ICharacterManager = {
    SpawnCharacter: (self: ICharacterManager, entity: Player | EntityRef, config: CharacterConfig?) -> CharacterData?,
    SpawnNPC: (self: ICharacterManager, npcModel: Model, config: CharacterConfig?) -> CharacterData?,
    CleanupCharacter: (self: ICharacterManager, entity: Player | EntityRef | number) -> (),
    GetCharacterData: (self: ICharacterManager, entity: Player | EntityRef | number) -> CharacterData?,
    DamageCharacter: (self: ICharacterManager, entity: Player | EntityRef | number, damage: number) -> boolean,
    HealCharacter: (self: ICharacterManager, entity: Player | EntityRef | number, healAmount: number) -> boolean,
    TakeDamage: (self: ICharacterManager, entity: Player | EntityRef | number, damage: number, canBlock: boolean?) -> number,
    ApplyEffect: (self: ICharacterManager, entity: Player | EntityRef | number, effectOrId: any, ctxExtra: {[string]: any}?) -> boolean,
    RemoveEffect: (self: ICharacterManager, entity: Player | EntityRef | number, effectId: string) -> boolean,
    GetCharacterState: (self: ICharacterManager, entity: Player | EntityRef | number, stateName: string) -> any?,
    SetCharacter: (self: ICharacterManager, entity: Player | EntityRef, config: CharacterConfig?) -> CharacterData?,
    SetCharacterState: (self: ICharacterManager, entity: Player | EntityRef | number, stateName: string, value: any) -> boolean,
    RegisterComponent: (self: ICharacterManager, name: string, component: any) -> (),
    UnregisterComponent: (self: ICharacterManager, name: string) -> (),
    GetAbilityComponent: (self: ICharacterManager) -> any?,
    OnCharacterAdded: (self: ICharacterManager, callback: (CharacterData) -> ()) -> RBXScriptConnection,
    GetPerformanceMetrics: (self: ICharacterManager) -> any,
    UpdateInputState: (self: ICharacterManager, entity: Player | EntityRef | number, input: any, state : boolean) -> boolean,
    Destroy: (self: ICharacterManager) -> (),
}

function CharacterManager.New(): ICharacterManager
    Players.CharacterAutoLoads = false
    
    local self = setmetatable({}, CharacterManager)
    
    -- Configuration (frozen for optimization)
    self.Config = table.freeze(DEFAULT_CONFIG)
    
    -- Pre-allocate subsystems
    self._assetLoader = CharacterAssetLoader.new()
    self._eventManager = CharacterEventManager.new()
    self._componentManager = ComponentManager.new()
    self._lifecycle = CharacterLifecycle.new()
    self._updateLoop = CharacterUpdateLoop.new(self.Config.UpdateInterval)
    self._registry = CharacterRegistry.new()
    
    -- Cache frequently accessed components
    self._componentCache = {} :: {[string]: any}
    
    -- Pre-allocate update batch array
    self._updateBatch = {} :: {internalCharacter}
    
    -- Events
    self._characterAdded = Instance.new("BindableEvent")
    self._connections = {} :: {RBXScriptConnection}
    
    -- Character registry
    self._characterRegistry = self:_LoadCharacterRegistry()
    
    -- Create factory with dependencies
    self._factory = CharacterFactory.new(self._assetLoader, self._eventManager, self._characterRegistry)
    
    -- Character creation hook
    self.OnCharacterCreation = nil :: ((player: Player, characterModel: Model, config: CharacterConfig?) -> ())?
    
    -- Cache remote event
    self._coreRemote = self:_GetCoreRemote()
    
    -- Initialize
    self:_Initialize()
    
    return (self :: any) :: ICharacterManager
end

function CharacterManager:_LoadCharacterRegistry()
    local success, registry = pcall(require, ServerStorage.Modules.registry.Characters)
    if success then
        print(`✅ CharacterRegistry loaded: {registry.Count()} definitions`)
        return registry
    else
        warn(`❌ CharacterRegistry load failed: {registry}`)
        return nil
    end
end

function CharacterManager:_GetCoreRemote(): RemoteEvent?
    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
    return remotesFolder and remotesFolder:FindFirstChild("CoreEvent") :: RemoteEvent?
end

function CharacterManager:_Initialize()
    -- Configure subsystems
    self._updateLoop:SetUpdateCallback(function(dt: number)
        self:_UpdateCharactersBatched(dt)
    end)
    
    self._lifecycle:SetConfig({
        DefaultRespawnTime = self.Config.DefaultRespawnTime,
        EnableAutoRespawn = self.Config.EnableAutoRespawn,
        MaxCharacters = self.Config.MaxCharacters,
    })
    
    -- Register components in parallel
    taskSpawn(function()
        self:_RegisterBuiltinComponents()
        self:_LoadCyclicComponents()
    end)
    
    -- Set up events
    self:_SetupPlayerEvents()
    
    -- Start systems
    self._updateLoop:Start()
end

function CharacterManager:_RegisterBuiltinComponents()
    -- Load and cache core components
    local componentPath = ServerStorage.Modules.Components
    
    local components = {
        [COMPONENT_NAMES.HEALTH] = componentPath.HealthComponent,
        [COMPONENT_NAMES.STAMINA] = componentPath.StaminaComponent,
        [COMPONENT_NAMES.MOVEMENT] = componentPath.MovementComponent,
        [COMPONENT_NAMES.COMBAT] = componentPath.CombatComponent,
        [COMPONENT_NAMES.EFFECT] = componentPath.EffectComponent,
        [COMPONENT_NAMES.INPUT] = componentPath.InputComponent,
        [COMPONENT_NAMES.ABILITY] = componentPath.AbilityComponent,
        [COMPONENT_NAMES.WEAPON] = componentPath.WeaponComponent,
        [COMPONENT_NAMES.MOUSE] = componentPath.MouseComponent,
    }
    
    for name, path in pairs(components) do
        local success, component = pcall(require, path)
        if success then
            self._componentManager:RegisterComponent(name, component :: any)
            self._componentCache[name] = component
        else
            warn(`Failed to load {name}Component:`, component)
        end
    end
end

function CharacterManager:_LoadCyclicComponents()
    -- Load components with potential cyclic dependencies
    local componentPath = ServerStorage.Modules.Components
    
    local cyclicComponents = {
        [COMPONENT_NAMES.ABILITY] = componentPath.AbilityComponent,
        [COMPONENT_NAMES.WEAPON] = componentPath.WeaponComponent,
        [COMPONENT_NAMES.INPUT] = componentPath.InputComponent,
    }
    
    for name, path in pairs(cyclicComponents) do
        local success, component = pcall(require, path)
        if success then
            self._componentManager:RegisterComponent(name, component)
            self._componentCache[name] = component
        else
            warn(`Failed to load {name}Component:`, component)
        end
    end
end

function CharacterManager:_SetupPlayerEvents()
    -- Store connections for cleanup
    tableInsert(self._connections, Players.PlayerAdded:Connect(function(player: Player)
        player:SetAttribute("ClassId", "Rem")
        print(`[CharacterManager] Player {player.Name} ready for manual spawn`)
    end))
    
    tableInsert(self._connections, Players.PlayerRemoving:Connect(function(player: Player)
        self:CleanupCharacter(player)
    end))

end

function CharacterManager:SpawnCharacter(entity: Player | EntityRef, config: CharacterConfig?): CharacterData?
    local entityRef = createEntityRef(entity)
    if not entityRef then
        warn(`Invalid entity provided to SpawnCharacter`)
        return nil
    end
    
    local userId = entityRef.userId
    
    -- Early exit checks with type annotation
    local activeCount: number = self._registry:GetActiveCount()
    if activeCount >= self.Config.MaxCharacters then
        warn(`Character limit reached: {self.Config.MaxCharacters}`)
        return nil
    end
    
    -- Clean existing character
    if self._registry:Get(userId) then
        self:CleanupCharacter(entityRef)
    end
    
    -- Resolve character class
    local classId = self:_ResolveClassId(entityRef, config)
    local classDef = self._characterRegistry and self._characterRegistry.Get(classId)
    
    -- Create character model
    local characterModel = self._factory:CreateCharacterModel(entityRef, config, false)
    if not characterModel then
        warn(`Failed to create character model for {entityRef.name}`)
        return nil
    end
    
    -- Pre-spawn hook
    if self.OnCharacterCreation then
        pcall(self.OnCharacterCreation, entityRef, characterModel, config)
    end
    
    -- Create character data
    local characterData = self._factory:CreateCharacterData(entityRef, characterModel, config)
    if not characterData then
        characterModel:Destroy()
        return nil
    end
    
    -- Initialize character
    self:_InitializeCharacter(characterData, classDef, classId, config)
    
    -- Setup animations asynchronously
    task.spawn(function()
        self:_SetupCharacterAnimations(entityRef, characterData, classId)
    end)
    
    -- Add to workspace
    characterModel.Parent = workspace
    
    -- Register and activate
    self._registry:Register(userId, characterData)
    self._lifecycle:HandleSpawn(characterData)
    
    -- Notify systems
    self._characterAdded:Fire(characterData)
    
    -- Only fire network events for players, not NPCs
    if entityRef.entityType == "Player" and entityRef.player then
        NetworkServer.StartCharacterAnimation.Fire(entityRef.player, "Idle" )

        if self._coreRemote then
            self._coreRemote:FireClient(entityRef.player, "CharacterSpawned", time(), characterData.Character)
        end
    end
    
    return characterData
end

function CharacterManager:SpawnNPC(npcModel: Model, config: CharacterConfig?): CharacterData?
    -- Create EntityRef for NPC
    local entityRef = createEntityRef(npcModel)
    if not entityRef then
        warn(`Failed to create entity reference for NPC model {npcModel.Name}`)
        return nil
    end
    
    -- Mark config as NPC
    local npcConfig: CharacterConfig = config or {}
    npcConfig.IsNPC = true
    npcConfig.NPCName = npcConfig.NPCName or npcModel.Name
    
    return self:SpawnCharacter(entityRef, npcConfig)
end

function CharacterManager:_ResolveClassId(entity: EntityRef, config: CharacterConfig?): string
    return (config and (config.ClassId or (config :: any).classId)) 
        or (entity.entityType == "Player" and entity.player and entity.player:GetAttribute("ClassId") :: string?) 
        or "Default"
end

function CharacterManager:_InitializeCharacter(
    characterData: internalCharacter, 
    classDef: any?, 
    classId: string, 
    config: CharacterConfig?
)
    -- Attach class information
    characterData.Definition = classDef
    characterData.ClassId = classId
    characterData.Custom = {}
    
    -- Merge custom fields
    if classDef and classDef.customFields then
        for k, v in pairs(classDef.customFields) do
            (characterData.Custom :: any)[k] = v
        end
    end
    
    if config and (config :: any).Custom then
        for k, v in pairs((config :: any).Custom) do
            (characterData.Custom :: any)[k] = v
        end
    end
    
    -- Run onInit hook
    if classDef and classDef.hooks and classDef.hooks.onInit then
        pcall(classDef.hooks.onInit, characterData)
    end
    
    -- Initialize components
    self._componentManager:InitializeComponents(characterData, config)
    
    -- Setup events
    self._eventManager:SetupSignalConnections(characterData, function()
        self:_HandleCharacterDeath(characterData.Entity)
    end)
    
    self._eventManager:SetupStateChangeSignals(characterData)
    self:_SetupShiftStateHandling(characterData)
end

function CharacterManager:_SetupCharacterAnimations(entity: EntityRef, characterData: internalCharacter, classId: string)
    local shiftState = self:GetCharacterState(entity, "ShiftState")
    local loadout = LoadoutRegistry.Get(shiftState or classId)
    
    if loadout and loadout.animationPack then
        self._factory:SetupAnimations(characterData.Character, entity, loadout.animationPack)
    end
end

function CharacterManager:CleanupCharacter(entity: Player | EntityRef | number)
    local userId = getEntityUserId(entity)
    if not userId then return end
    
    local characterData = self._registry:Get(userId)
    
    if not characterData then return end
    
    -- Cleanup in order
    self._lifecycle:HandleCleanup(characterData)
    self._componentManager:CleanupComponents(characterData)
    self._eventManager:CleanupSignals(characterData.Signals)
    self._registry:Unregister(userId)
end

function CharacterManager:GetCharacterData(entity: Player | EntityRef | number): CharacterData?
    local userId = getEntityUserId(entity)
    if not userId then return nil end
    return self._registry:Get(userId) :: CharacterData?
end

function CharacterManager:DamageCharacter(entity: Player | EntityRef | number, damage: number): boolean
    local userId = getEntityUserId(entity)
    if not userId then return false end
    
    local characterData: internalCharacter? = self._registry:Get(userId)
    if not characterData or not characterData.Humanoid then
        return false
    end
    
    local currentHealth: number = characterData.Humanoid.Health
    local newHealth = mathMax(currentHealth - damage, 0)
    characterData.Humanoid.Health = newHealth
    characterData.StateManager:Set("Health", newHealth)
    
    -- Also update MaxHealth in StateManager to match Humanoid if not set
    if not characterData.StateManager:Get("MaxHealth") then
        characterData.StateManager:Set("MaxHealth", characterData.Humanoid.MaxHealth)
    end
    
    if newHealth <= 0 then
        self:_HandleCharacterDeath(entity)
    end
    
    return true
end

function CharacterManager:HealCharacter(entity: Player | EntityRef | number, healAmount: number): boolean
    local userId = getEntityUserId(entity)
    if not userId then return false end
    
    local characterData: internalCharacter? = self._registry:Get(userId)
    if not characterData or not characterData.Humanoid then
        return false
    end
    
    local currentHealth: number = characterData.Humanoid.Health
    local maxHealth: number = characterData.Humanoid.MaxHealth
    
    -- Initialize MaxHealth in StateManager if not set
    if not characterData.StateManager:Get("MaxHealth") then
        characterData.StateManager:Set("MaxHealth", maxHealth)
    end
    
    -- Allow overheal by using the StateManager's max health if it's higher
    local stateMaxHealth = characterData.StateManager:Get("MaxHealth") or maxHealth
    local effectiveMaxHealth = mathMax(maxHealth, stateMaxHealth)
    
    local newHealth = mathMin(currentHealth + healAmount, effectiveMaxHealth)
    characterData.Humanoid.Health = mathMin(newHealth, maxHealth) -- Humanoid can't exceed its MaxHealth
    characterData.StateManager:Set("Health", newHealth) -- StateManager can have overheal
    
    return true
end

function CharacterManager:TakeDamage(entity: Player | EntityRef | number, damage: number, canBlock: boolean?): number
    local userId = getEntityUserId(entity)
    if not userId then return 0 end
    
    local characterData = self._registry:Get(userId)
    if not characterData then return 0 end
    
    local combat = self._componentCache[COMPONENT_NAMES.COMBAT]
    if combat and combat.TakeDamage then
        local success, actual = pcall(combat.TakeDamage, characterData, damage, canBlock)
        if success then
            characterData.StateManager:Set("LastDamage", actual)
            return actual
        end
    end
    
    -- Fallback
    local current = characterData.StateManager:Get("Health") or 100
    local actual = mathMax(0, damage)
    characterData.StateManager:Set("Health", mathMax(0, current - actual))
    characterData.StateManager:Set("LastDamage", actual)

    if current - actual <= 0 then
        self:_HandleCharacterDeath(entity)
    end

    return actual
end

function CharacterManager:ApplyEffect(entity: Player | EntityRef | number, effectOrId: any, ctxExtra: {[string]: any}?): boolean
    local userId = getEntityUserId(entity)
    if not userId then return false end
    
    local characterData = self._registry:Get(userId)
    if not characterData then return false end
    
    local effectComp = self._componentCache[COMPONENT_NAMES.EFFECT]
    if effectComp and effectComp.GetService then
        local service = effectComp.GetService()
        local success = pcall(service.Apply, service, characterData, effectOrId, ctxExtra)
        return success
    end
    
    return false
end

function CharacterManager:RemoveEffect(entity: Player | EntityRef | number, effectId: string): boolean
    local userId = getEntityUserId(entity)
    if not userId then return false end
    
    local characterData = self._registry:Get(userId)
    if not characterData then return false end
    
    local effectComp = self._componentCache[COMPONENT_NAMES.EFFECT]
    if effectComp and effectComp.GetService then
        local service = effectComp.GetService()
        local success = pcall(service.Remove, service, characterData, effectId)
        return success
    end
    
    return false
end

function CharacterManager:GetCharacterState(entity: Player | EntityRef | number, stateName: string): any?
    local userId = getEntityUserId(entity)
    if not userId then return nil end
    
    local characterData = self._registry:Get(userId)
    return characterData and characterData.StateManager:Get(stateName)
end

function CharacterManager:SetCharacter(entity: Player | EntityRef, config: CharacterConfig?): CharacterData?
    local entityRef = createEntityRef(entity)
    if not entityRef then return nil end
    
    if config then
        -- Persist configuration for players
        if entityRef.entityType == "Player" and entityRef.player then
            local classId = config.ClassId or (config :: any).classId
            if classId then
                entityRef.player:SetAttribute("ClassId", classId)
            end
            
            local loadoutAssetKey = (config :: any).loadoutAssetKey
            if loadoutAssetKey then
                entityRef.player:SetAttribute("LoadoutAssetKey", loadoutAssetKey)
            end
        end
    end
    
    return self:SpawnCharacter(entityRef, config)
end

function CharacterManager:SetCharacterState(entity: Player | EntityRef | number, stateName: string, value: any): boolean
    local userId = getEntityUserId(entity)
    if not userId then return false end
    
    local characterData = self._registry:Get(userId)
    if characterData and characterData.StateManager then
        characterData.StateManager:Set(stateName, value)
        return true
    end
    return false
end

function CharacterManager:RegisterComponent(name: string, component: any)
    self._componentManager:RegisterComponent(name, component)
    self._componentCache[name] = component
end

function CharacterManager:UnregisterComponent(name: string)
    self._componentManager:UnregisterComponent(name)
    self._componentCache[name] = nil
end

function CharacterManager:GetAbilityComponent()
    return self._componentCache[COMPONENT_NAMES.ABILITY]
end

function CharacterManager:OnCharacterAdded(callback: (CharacterData) -> ()): RBXScriptConnection
    return self._characterAdded.Event:Connect(function(characterData: internalCharacter)
        callback(characterData :: CharacterData)
    end)
end

function CharacterManager:GetPerformanceMetrics()
    local metrics = self._updateLoop:GetPerformanceMetrics()
    metrics.CachedComponents = 0
    for _ in pairs(self._componentCache) do
        metrics.CachedComponents += 1
    end
    return metrics
end

function CharacterManager:Destroy()
    -- Stop systems
    self._updateLoop:Stop()
    
    -- Cleanup all characters
    for playerId, characterData in pairs(self._registry:GetAll()) do
        if characterData.Player then
            self:CleanupCharacter(characterData.Player)
        end
    end
    
    -- Clear registry
    self._registry:Clear()
    
    -- Disconnect events
    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
    tableClear(self._connections)
    
    -- Clear caches
    tableClear(self._componentCache)
    tableClear(self._updateBatch)
    
    -- Destroy events
    self._characterAdded:Destroy()
end

-- Optimized batch update system
function CharacterManager:_UpdateCharactersBatched(dt: number)
    local activeList = self._registry:GetActiveList()
    local count = #activeList
    
    if count == 0 then return end
    
    -- Process in batches to avoid frame spikes
    local batchSize = mathMin(self.Config.BatchUpdateSize, count)
    local metrics = self._updateLoop:GetPerformanceMetrics()
    local frameOffset = math.floor((metrics.UpdateTime * 1000) % math.ceil(count / batchSize))
    local startIdx = frameOffset * batchSize + 1
    local endIdx = mathMin(startIdx + batchSize - 1, count)
    
    for i = startIdx, endIdx do
        local playerId = activeList[i]
        local characterData: internalCharacter? = self._registry:GetActive(playerId)
        
        if characterData then
            self:_UpdateSingleCharacter(characterData, dt)
        else
            self._registry:SetActive(playerId, false)
        end
    end
end

function CharacterManager:_UpdateSingleCharacter(characterData: internalCharacter, dt: number)
    -- Validate character
    if not characterData.Character or not characterData.Character.Parent then
        self:CleanupCharacter(characterData.Entity)
        return
    end
    
    -- Run class update hook
    local def = characterData.Definition
    if def and def.hooks and def.hooks.onUpdate then
        pcall(def.hooks.onUpdate, characterData, dt)
    end
    
    -- Update components
    self._componentManager:UpdateComponents(characterData, dt)
    
    -- Fire update event
    characterData.Signals.OnUpdate:Fire(dt)
    characterData._lastUpdate = time()
end

function CharacterManager:_HandleCharacterDeath(entity: Player | EntityRef | number)
    local userId = getEntityUserId(entity)
    if not userId then return end
    
    local characterData = self._registry:Get(userId)
    if not characterData then return end
    
    self._registry:SetActive(userId, false)
    self._lifecycle:HandleDeath(characterData)
    self:CleanupCharacter(entity)
end

function CharacterManager:_SetupShiftStateHandling(characterData: internalCharacter)
    characterData.StateManager:OnStateChange("ShiftState", function(newVal: any, _oldVal: any)
        local abilityComponent = self._componentCache[COMPONENT_NAMES.ABILITY]
        if not abilityComponent or not abilityComponent.SetLoadout then return end
        
        local loadout = LoadoutRegistry.Get(newVal)
        if loadout then
            abilityComponent.SetLoadout(characterData, loadout)
        end
    end)
end

function CharacterManager:UpdateInputState(characterData: internalCharacter, input : any, state : boolean)
    local inputComponent = self._componentCache[COMPONENT_NAMES.INPUT]
    if not inputComponent then return end

    local states : {[string] : any} = characterData.StateManager:Get("ActiveKeys") :: any
    if not states then return end

    local copy = tableClone(states)
    copy[input.Value] = state

    characterData.StateManager:Set("ActiveKeys", tableFreeze(copy))
end


return CharacterManager.New()