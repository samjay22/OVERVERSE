--!nonstrict
-- Character Manager - Handles all character-related functionality
-- TODO: Convert to strict mode after resolving type compatibility issues
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CharacterAdded = Instance.new("BindableEvent")
local CollectionService = game:GetService("CollectionService")

local CharacterTypes = require(ServerStorage.Modules.Types.CharacterTypes)
local CharacterRegistry: any = nil
do
    local ok, mod = pcall(function()
        return require((game.ServerStorage.Modules.registery :: any).Characters)
    end)
    if ok then CharacterRegistry = mod end
end

type internalCharacter = CharacterTypes.internalCharacter
type CharacterConfig = CharacterTypes.CharacterConfig
type ComponentInterface = CharacterTypes.ComponentInterface
type CharacterData = CharacterTypes.Character

-- Dependencies
local Constants = require(ReplicatedStorage.Modules.Utility.Constants)
local _WeldUtility = require(ServerStorage.Modules.Utilities.WeldUtility)
local StateManager = require(ReplicatedStorage.Modules.Utility.StateManager)
local _WeaponUtility = require(ServerStorage.Modules.Utilities.WeaponUtility)
local CharacterStates = require(ServerStorage.Modules.Utilities.CharacterStates)
local UpdateScheduler = require(ServerStorage.Modules.Utilities.UpdateScheduler)
local AbilityLoadouts = require(ServerStorage.Modules.registery.Loadouts)
local NetworkServer = require(ServerStorage.Modules.Core.NetworkServer)



local CharacterAssets = require(ReplicatedStorage.Modules.AssetHandlers).OnModuleLoaded("Characters")
local AnimationAssets = require(ReplicatedStorage.Modules.AssetHandlers).OnModuleLoaded("Animations")

-- Character Manager Class
local Character = {}
Character.__index = Character

-- small helper for dictionary sizes
function Character:_dictCount(t: {[any]: any}): number
    local c = 0
    for _ in pairs(t) do
        c += 1
    end
    return c
end

function Character.New()
    local self = setmetatable({}, Character)
    Players.CharacterAutoLoads = false -- Disable auto character loading
    
    -- Remotes
    self._coreRemote = nil :: RemoteEvent?
    
    -- Character creation hook - called before character is put in workspace
    self.OnCharacterCreation = nil :: ((player: Player, characterModel: Model, config: CharacterConfig?) -> ())?
    
    -- Configuration
    self.Config = {
        DefaultRespawnTime = Constants.DEFAULT_RESPAWN_TIME or 5,
        UpdateInterval = 1/30, -- default 30 Hz fixed-step to reduce server load
        MaxCharacters = 100,
        EnableAutoRespawn = true
    }
    
    -- Storage
    self.CharacterRegistry = {} :: {[number]: internalCharacter}
    self.ActiveCharacters = {} :: {[number]: internalCharacter}
    -- Fast int-indexed iteration structures for active characters
    self._activeList = {} :: {number} -- array of playerIds
    self._activeIndex = {} :: {[number]: number} -- playerId -> index
    self.Components = {} :: {[string]: any}
    self._updaters = {} :: { {name: string, fn: (any, number) -> ()} }
    self.StateDefinitions = {}
    
    -- Performance tracking
    self.PerformanceMetrics = {
        UpdateTime = 0,
        CharacterCount = 0,
        LastCleanup = 0
    }
    
    -- Event connections
    self._connections = {}
    self._updateAccumulator = 0
    self._scheduler = nil :: any
    
    self:_Initialize()
    return self
end

-- Load components that have cyclic dependencies
function Character:_LoadCyclicComponents()
    -- Load these components after the Character manager is fully initialized
    task.spawn(function()
        local success, AbilityComponent = pcall(require, game.ServerStorage.Modules.Components.AbilityComponent)
        if success then
            self:RegisterComponent("Ability", AbilityComponent)
        else
            warn("Failed to load AbilityComponent:", AbilityComponent)
        end
        
        local success2, WeaponComponent = pcall(require, game.ServerStorage.Modules.Components.WeaponComponent)
        if success2 then
            self:RegisterComponent("Weapon", WeaponComponent)
        else
            warn("Failed to load WeaponComponent:", WeaponComponent)
        end

        local success3, InputComponent = pcall(require, game.ServerStorage.Modules.Components.InputComponent)
        if success3 then
            self:RegisterComponent("Input", InputComponent)
        else
            warn("Failed to load InputComponent:", InputComponent)
        end
    end)
end
 
function Character:_Initialize()
    -- Disable auto character loading (already set in constructor for safety)
    Players.CharacterAutoLoads = false
    
    -- Cache core remote if present
    local ok, remote = pcall(function()
        return ReplicatedStorage:WaitForChild("Remotes", 1) and ReplicatedStorage.Remotes:FindFirstChild("CoreEvent")
    end)
    if ok then
        self._coreRemote = remote :: RemoteEvent?
    end
    
    -- Load state definitions
    self:_LoadStateDefinitions()
    
    -- Register built-in components with proper typing
    local HealthComponent = require(game.ServerStorage.Modules.Components.HealthComponent)
    local StaminaComponent = require(game.ServerStorage.Modules.Components.StaminaComponent)
    local MovementComponent = require(game.ServerStorage.Modules.Components.MovementComponent)
    local CombatComponent = require(game.ServerStorage.Modules.Components.CombatComponent)
    local EffectComponent = require(game.ServerStorage.Modules.Components.EffectComponent)
    
    self:RegisterComponent("Health", HealthComponent :: any)
    self:RegisterComponent("Stamina", StaminaComponent :: any)
    self:RegisterComponent("Movement", MovementComponent :: any)
    self:RegisterComponent("Combat", CombatComponent :: any)
    self:RegisterComponent("Effect", EffectComponent :: any)

    -- Effects registry
    local EffectRegistry = require(game.ServerStorage.Modules.registery.Effects)
    local effectCount: number = 0
    -- Safe check for GetAllEffects method
    if EffectRegistry.GetAllEffects then
        for _ in pairs(EffectRegistry.GetAllEffects()) do effectCount += 1 end
    end
    print("Effect registry loaded with", effectCount, "effects")

    -- Set up player events
    self:_SetupPlayerEvents()
    
    -- Load cyclic components after initial setup
    self:_LoadCyclicComponents()
    
    -- Start update loop
    self:_StartUpdateLoop()
    
    -- Spawn for any players already present
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character then
            self:SpawnCharacter(plr)
        end
        plr.CharacterAdded:Connect(function(character: Model)
            self:SpawnCharacter(plr)
        end)
    end
end

function Character:_LoadStateDefinitions()
    self.StateDefinitions = CharacterStates.GetDefinitions()
end

function Character:RegisterComponent(name: string, component)
    if self.Components[name] then
        warn(`Component {name} already registered, overwriting`)
    end
    self.Components[name] = component
    -- cache updater if present
    if component and component.Update and typeof(component.Update) == "function" then
        table.insert(self._updaters, { name = name, fn = component.Update })
    end
end

function Character:UnregisterComponent(name: string)
    self.Components[name] = nil
    -- remove any cached updater entries for this component name
    for i = #self._updaters, 1, -1 do
        if self._updaters[i].name == name then
            table.remove(self._updaters, i)
        end
    end
end

function Character:SpawnCharacter(player: Player, config: CharacterConfig?): CharacterData?
    local playerId = player.UserId
    
    -- Check limits (use fast int list size)
    if #self._activeList >= self.Config.MaxCharacters then
        warn(`Maximum character limit ({self.Config.MaxCharacters}) reached`)
        return nil
    end
    
    -- Clean up existing character
    self:CleanupCharacter(player)
    
    -- Resolve character class definition
    local classId: CharacterTypes.CharacterClassId = (config and config.ClassId) or (player:GetAttribute("ClassId") :: any) or "Default"
    local classDef = nil
    if CharacterRegistry and CharacterRegistry.Get then
        classDef = CharacterRegistry.Get(classId)
    end
    
    -- Create character model (but don't put it in workspace yet)
    local characterModel = self:_CreateCharacterModel(player, config, false) -- false = don't parent to workspace
    if not characterModel then
        return nil
    end
    
    -- Call OnCharacterCreation hook before the character is put in workspace
    -- This allows modification of the character model (weapons, animations, etc.)
    if self.OnCharacterCreation then
        local okHook = pcall(self.OnCharacterCreation, player, characterModel, config)
        if not okHook then
            warn(`OnCharacterCreation hook failed for {player.Name}`)
        end
    end

    local characterData = self:_CreateCharacterData(player, characterModel, config)
    if not characterData then
        characterModel:Destroy()
        return nil
    end

    -- Create and tag animations folder, then populate from class pack or Default
    local characterAnimationsFolder: Folder = Instance.new("Folder")
    characterAnimationsFolder.Name = "Animations"
    characterAnimationsFolder.Parent = characterModel
    local animTag = tostring(player.UserId) .. "_Animations"
    CollectionService:AddTag(characterAnimationsFolder, animTag)

    task.delay(1, function()
        -- Determine animation pack
        local loadoutData = AbilityLoadouts.Get(characterData.StateManager:Get("ShiftState") or classId)
        local packName = (loadoutData and loadoutData.animationPack) or "Default"
        do
            local handler: any = AnimationAssets
            local assets: {[string]: any} = handler.GetAllAssets()
            for key, assetVal in pairs(assets) do
                -- key is "Pack:Animation"; only take entries for the chosen pack
                if type(key) == "string" and key:sub(1, #packName + 1) == (packName .. ":") then
                    local inst = (assetVal :: any).Instance
                    print(inst)
                    if inst and inst:IsA("Animation") then
                        local clone = inst:Clone()
                        -- optional: name the clone as just the clip name (after "Pack:")
                        clone.Name = key:sub(#packName + 2)
                        clone.Parent = characterAnimationsFolder
                        print(clone)
                    end
                end
            end
        end

    end)
    -- Now put the character in the workspace
    characterModel.Parent = workspace
        
    -- Attach class information and custom fields
    characterData.Definition = classDef
    characterData.ClassId = classId
    characterData.Custom = {}
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
    
    -- Run class onInit hook before components
    if classDef and classDef.hooks and classDef.hooks.onInit then
        local okInit, errInit = pcall(classDef.hooks.onInit, characterData)
        if not okInit then warn("Class onInit failed:", errInit) end
    end

    -- Initialize components
    for componentName, component in pairs(self.Components) do
        if component.Initialize then
            -- Inject a default ability loadout if not provided
            local cfg = config
            if componentName == "Ability" then
                local assetKey = Constants.CHARACTER_ASSET_DEFAULT
                local loadout = AbilityLoadouts.Get(assetKey)
                local merged = table.clone(cfg or {}) :: any
                local abilityLoadout = (cfg and ((cfg :: any).AbilityLoadout :: any)) or loadout
                merged.AbilityLoadout = abilityLoadout
                cfg = merged :: any
            end

            -- Initialize component with character data and config
            local okInitComp = pcall(component.Initialize, characterData, cfg)
            if not okInitComp then
                warn(`Failed to initialize component {componentName}`)
            end
        end
    end
    
    task.delay(1, function()
        NetworkServer:FireClient("StartCharacterAnimation", player, { "Idle" })
    end)
    -- Register character (dict + int-indexed list)
    self.CharacterRegistry[playerId] = characterData
    self.ActiveCharacters[playerId] = characterData
    local list = self._activeList
    list[#list + 1] = playerId
    self._activeIndex[playerId] = #list
    
    CharacterAdded:Fire(characterData) -- Notify listeners
    characterData.Signals.OnSpawn:Fire(characterData.Character)

    -- Notify client camera + animation hookup
    if self._coreRemote then
        pcall(function()
            (self._coreRemote :: RemoteEvent):FireClient(player, "CharacterSpawned", time(), characterData.Character)
        end)
    end

    return characterData
end

function Character:_CreateCharacterModel(player: Player, config: CharacterConfig?, parentToWorkspace: boolean?): Model?
    -- Get character asset
    local characterAsset = self:_GetCharacterAsset()
    if not characterAsset then
        warn(`No character assets available for player {player.Name}`)
        return nil
    end
    
    -- Clone and set up character
    local characterModel = characterAsset:Clone()
    characterModel.Name = player.Name
    
    -- Only parent to workspace if explicitly requested (default true for backwards compatibility)
    if parentToWorkspace ~= false then
        characterModel.Parent = workspace
    end
    
    -- Guard non-standard APIs
    local modelAny = characterModel :: any
    if typeof(modelAny.AddPersistentPlayer) == "function" then
        pcall(function()
            modelAny:AddPersistentPlayer(player)
        end)
    end

    -- Set up humanoid
    local humanoid : Humanoid= characterModel:WaitForChild("Humanoid") :: Humanoid
    local maxHealth = (config and config.MaxHealth) or 100
    humanoid.MaxHealth = maxHealth
    humanoid.Health = maxHealth
    humanoid.WalkSpeed = (config and config.WalkSpeed) or 16
    
    -- Set player character
    player.Character = characterModel
    local primary: BasePart? = characterModel.PrimaryPart or characterModel:FindFirstChild("HumanoidRootPart") :: BasePart?
    if primary then
        humanoid.TargetPoint = (primary :: BasePart).Position
    end

    return characterModel
end

function Character:DamageCharacter(player : Player, damage: number): boolean
    local characterData : internalCharacter = self.CharacterRegistry[player.UserId]
    if not characterData or not characterData.Humanoid then
        warn(`Character data not found for player {player.Name}`)
        return false
    end
    
    local newHealth = math.max(characterData.Humanoid.Health - damage, 0)
    characterData.Humanoid.Health = newHealth
    characterData.StateManager:Set("Health", newHealth)
    
    if newHealth <= 0 then
        self:HandleCharacterDeath(player)
    end
    
    return true
    
end

function Character:_CreateCharacterData(player: Player, characterModel: Model, config: CharacterConfig?): internalCharacter?
    local humanoid = characterModel:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        warn(`No humanoid found in character model for {player.Name}`)
        return nil
    end
    
    -- Create all character-level signals
    local signals = {
        OnSpawn = Instance.new("BindableEvent"),
        OnDeath = Instance.new("BindableEvent"),
        OnDamage = Instance.new("BindableEvent"),
        OnAttack = Instance.new("BindableEvent"),
        OnUpdate = Instance.new("BindableEvent"),
        OnStaminaChange = Instance.new("BindableEvent"),
        OnGuardChange = Instance.new("BindableEvent"),
        OnStateChange = Instance.new("BindableEvent"),
        OnCleanup = Instance.new("BindableEvent"),
    }
    
    local sheathInst = characterModel:FindFirstChild("WeaponSheath")
    local sheathPart: BasePart? = nil
    if sheathInst and sheathInst:IsA("BasePart") then
        sheathPart = sheathInst
    end
    local characterData: internalCharacter = {
        PlayerId = player.UserId,
        Player = player,
        Character = characterModel,
        Humanoid = humanoid,
        -- Route state changes into the OnStateChange event
        StateManager = StateManager.New(signals.OnStateChange),
        WeaponSheath = sheathPart,
        Components = {},
        -- Expose signals at root for type compatibility and under Signals for convenience
        OnSpawn = signals.OnSpawn,
        OnDeath = signals.OnDeath,
        OnDamage = signals.OnDamage,
        OnAttack = signals.OnAttack,
        OnUpdate = signals.OnUpdate,
        OnStaminaChange = signals.OnStaminaChange,
        OnGuardChange = signals.OnGuardChange,
        OnStateChange = signals.OnStateChange,
        Signals = signals,
        OnCleanup = signals.OnCleanup,
        _connections = {},
        _cleanupTasks = {},
        _lastUpdate = time(),
    Animations = characterModel:FindFirstChild("Animations"),
        Definition = nil,
        Custom = {},
    }
    
    -- Initialize state manager
    self:_InitializeStateManager(characterData, config)

    -- Route OnDeath to manager death handler
    if characterData.Signals then
        table.insert(characterData._connections, characterData.Signals.OnDeath.Event:Connect(function()
            self:HandleCharacterDeath(player)
        end))
    end

    -- Wire specific state change signals
    characterData.StateManager:OnStateChange("Stamina", function(newVal, oldVal)
        characterData.Signals.OnStaminaChange:Fire(newVal, oldVal)
    end)
    characterData.StateManager:OnStateChange("Guard", function(newVal, oldVal)
        characterData.Signals.OnGuardChange:Fire(newVal, oldVal)
    end)

    -- Hook ShiftState to swap ability loadouts between Human and Beast forms
    characterData.StateManager:OnStateChange("ShiftState", function(newVal: any, _oldVal: any)
        local AbilityComponentMod = self.Components["Ability"]
        if not AbilityComponentMod or not AbilityComponentMod.SetLoadout then return end
        -- Choose loadout assetKey per form; fallback to Default
        local loadout = AbilityLoadouts.Get(newVal)
        AbilityComponentMod.SetLoadout(characterData, loadout)
        print("Shift state changed")
    end)
    
    return characterData
end

function Character:SetCharacter(...)
    warn(...)
end

function Character:_InitializeStateManager(characterData: internalCharacter, config: CharacterConfig?)
    local stateManager = characterData.StateManager
    
    -- Define states
    CharacterStates.applyTo(stateManager, self.StateDefinitions)
    -- Apply character-class initial states if any
    local def = characterData.Definition
    if def and def.initialStates then
        for stateName, v in pairs(def.initialStates :: any) do
            if typeof(v) == "table" and (v :: any).default ~= nil then
                stateManager:DefineState(stateName, (v :: any).default, (v :: any).validator)
            else
                stateManager:DefineState(stateName, v, nil)
            end
        end
    end

    -- Debug: stateManager:GetAllStates() can be printed when needed
    
    -- Apply config overrides
    if config then
        if config.MaxHealth then stateManager:Set("MaxHealth", config.MaxHealth) end
        if config.MaxStamina then stateManager:Set("MaxStamina", config.MaxStamina) end
        if config.MaxGuard then stateManager:Set("MaxGuard", config.MaxGuard) end
    end
    
    -- Set initial values
    stateManager:Set("Health", characterData.Humanoid.Health)
    stateManager:Set("MaxHealth", characterData.Humanoid.MaxHealth)
end

-- O(1) swap-remove for active character list
function Character:_swapRemoveActive(playerId: number)
    local list = self._activeList
    local index = self._activeIndex
    local idx = index[playerId]
    if idx then
        local last = #list
        local lastId = list[last]
        if lastId then
            list[idx] = lastId
            index[lastId] = idx
            list[last] = nil
        end
        index[playerId] = nil
    end
end

function Character:CleanupCharacter(player: Player)
    local playerId = player.UserId
    local characterData = self.CharacterRegistry[playerId]
    
    if not characterData then return end
    
    -- Class onCleanup hook
    local characterDataForHook = self.CharacterRegistry[playerId]
    if characterDataForHook and characterDataForHook.Definition and characterDataForHook.Definition.hooks and characterDataForHook.Definition.hooks.onCleanup then
        pcall(characterDataForHook.Definition.hooks.onCleanup, characterDataForHook)
    end

    -- Cleanup components
    for componentName, component in pairs(self.Components) do
        if component.Cleanup then
            local okCleanup = pcall(component.Cleanup, characterData)
            if not okCleanup then
                warn(`Failed to cleanup component {componentName}`)
            end
        end
    end
    
    -- Disconnect connections
    for _, connection in pairs(characterData._connections) do
        if connection then
            connection:Disconnect()
        end
    end
    
    -- Execute cleanup tasks
    for _, cleanupTask in pairs(characterData._cleanupTasks) do
        if typeof(cleanupTask) == "function" then
            task.defer(function()
                local okTask = pcall(cleanupTask)
                if not okTask then
                    warn("Cleanup task failed")
                end
            end)
        end
    end
    
    -- Fire cleanup signal before destruction
    characterData.Signals.OnCleanup:Fire()

    -- Clean up character model
    if characterData.Character then
        characterData.Character:Destroy()
    end

    -- Destroy signals
    if characterData.Signals then
        for _, obj in pairs(characterData.Signals) do
            if typeof(obj) == "Instance" and obj.Destroy then
                obj:Destroy()
            end
        end
    end
    
    -- Remove from registries (list first for safe in-loop removal)
    self:_swapRemoveActive(playerId)
    self.CharacterRegistry[playerId] = nil
    self.ActiveCharacters[playerId] = nil
    
    print(`Character cleaned up for {player.Name}`)
end

function Character:HandleCharacterDeath(player: Player)
    local characterData : internalCharacter = self.CharacterRegistry[player.UserId]
    if not characterData then return end
    
    -- Set death state
    characterData.StateManager:Set("IsDead", true)
    
    -- Remove from active characters
    self.ActiveCharacters[player.UserId] = nil
    local tagged = CollectionService:GetTagged(tostring(player.UserId) .. "_Animations")
    if tagged and #tagged > 0 then
        for _, inst in ipairs(tagged) do
            pcall(function()
                CollectionService:RemoveTag(inst, tostring(player.UserId) .. "_Animations")
                inst:Destroy()
            end)
        end
    end
    
    -- Schedule respawn if enabled
    if self.Config.EnableAutoRespawn then
        local respawnTime = self.Config.DefaultRespawnTime
        table.insert(characterData._cleanupTasks, function()
            task.wait(respawnTime)
            if Players:FindFirstChild(player.Name) then
                self:SpawnCharacter(player)
            end
        end)
    end

    -- Clean up immediately after death (triggers scheduled respawn task)
    self:CleanupCharacter(player)
end

function Character:_UpdateCharacters(dt: number)
    local startTime = time()
    local now = startTime

    local list = self._activeList
    local byId = self.ActiveCharacters
    local updaters = self._updaters

    -- Reverse int loop so we can safely remove during iteration
    for i = #list, 1, -1 do
        local playerId = list[i]
        local characterData = byId[playerId]
        if not characterData then
            -- Orphan entry; swap-remove and continue
            self:_swapRemoveActive(playerId)
            continue
        end

        -- Validate character still exists
        local char = characterData.Character
        if not char or not char.Parent then
            -- Clean up (also swap-removes from list)
            local plr = characterData.Player or Players:GetPlayerByUserId(playerId)
            if plr then
                self:CleanupCharacter(plr)
            else
                -- Fallback if player vanished
                self:_swapRemoveActive(playerId)
                self.CharacterRegistry[playerId] = nil
                self.ActiveCharacters[playerId] = nil
            end
            continue
        end

        -- Class onUpdate hook
        local def = characterData.Definition
        if def and def.hooks and def.hooks.onUpdate then
            local okH, errH = pcall(def.hooks.onUpdate, characterData, dt)
            if not okH then warn("Class onUpdate failed:", errH) end
        end

        -- Update components (fixed numeric list, pcall isolation)
        for u = 1, #updaters do
            local entry = updaters[u]
            local ok, err = pcall(entry.fn, characterData, dt)
            if not ok then
                warn(`Component {entry.name} update failed: {err}`)
            end
        end

        -- Per-tick update event
        characterData.Signals.OnUpdate:Fire(dt)

        characterData._lastUpdate = now
    end
    
    -- Update performance metrics (O(1))
    self.PerformanceMetrics.UpdateTime = time() - startTime
    self.PerformanceMetrics.CharacterCount = #self._activeList
end

function Character:_SetupPlayerEvents()
    table.insert(self._connections, Players.PlayerAdded:Connect(function(player: Player)
        player:SetAttribute("ClassId", "Rem")
        -- Wait a heartbeat to ensure player is fully replicated, then spawn
        task.defer(function()
            self:SpawnCharacter(player)
        end)
    end))
    
    table.insert(self._connections, Players.PlayerRemoving:Connect(function(player: Player)
        self:CleanupCharacter(player)
    end))
end

function Character:_StartUpdateLoop()
    -- Use UpdateScheduler for fixed-step updates
    if self._scheduler then
        self._scheduler:Destroy()
        self._scheduler = nil
    end
    self._scheduler = UpdateScheduler.New(self.Config.UpdateInterval)
    local disconnect = self._scheduler:OnStep(function(stepDt: number)
        self:_UpdateCharacters(stepDt)
    end)
    -- Ensure fixed-step interval if configured
    if self.Config.UpdateInterval and self.Config.UpdateInterval > 0 then
        self._scheduler:SetInterval(self.Config.UpdateInterval)
    end
    self._scheduler:Start()
    table.insert(self._connections, { Disconnect = function()
        disconnect()
        if self._scheduler then
            self._scheduler:Destroy()
            self._scheduler = nil
        end
    end } :: any)
end

function Character:_GetCharacterAsset(): Model?
    local handler: any = CharacterAssets
    if handler and handler.GetAsset then
        local val = handler.GetAsset("Default")
        local inst = val and val.Instance
        if inst and inst:IsA("Model") then
            return inst
        end
    end
    return nil
end

-- Public API
function Character:GetCharacterState(player: Player, stateName: string): any?
    local characterData = self.CharacterRegistry[player.UserId]
    return characterData and characterData.StateManager:Get(stateName) or nil
end

function Character:SetCharacterState(player: Player, stateName: string, value: any): boolean
    local characterData = self.CharacterRegistry[player.UserId]
    if characterData and characterData.StateManager then
        characterData.StateManager:Set(stateName, value)
        return true
    end
    return false
end

function Character:GetCharacterData(player: Player): CharacterData?
    local data = self.CharacterRegistry[player.UserId]
    return data and (data :: CharacterData) or nil
end

function Character:TakeDamage(player: Player, damage: number, canBlock: boolean?): number
    local characterData: internalCharacter? = self.CharacterRegistry[player.UserId]
    if not characterData then return 0 end
    local combat = self.Components["Combat"]
    local actual = damage
    if combat and combat.TakeDamage then
        local ok, res = pcall(combat.TakeDamage, characterData, damage, canBlock)
        if ok then actual = res end
    else
        -- Fallback direct health change
        local current = characterData.StateManager:Get("Health")
        characterData.StateManager:Set("Health", math.max(0, current - damage))
    end
    characterData.StateManager:Set("LastDamage", actual)
    return actual
end

function Character:GetPerformanceMetrics()
    return table.clone(self.PerformanceMetrics)
end

-- Effect helpers
function Character:ApplyEffect(player: Player, effectOrId: any, ctxExtra: {[string]: any}?): boolean
    local characterData: internalCharacter? = self.CharacterRegistry[player.UserId]
    if not characterData then return false end
    local effectComp = self.Components["Effect"]
    if not effectComp or not effectComp.GetService then return false end
    local service = effectComp.GetService()
    local ok, err = pcall(function()
        service:Apply(characterData, effectOrId, ctxExtra)
    end)
    if not ok then
        warn(`ApplyEffect failed for {player.Name}: {err}`)
    end
    return ok
end

function Character:RemoveEffect(player: Player, effectId: string): boolean
    local characterData: internalCharacter? = self.CharacterRegistry[player.UserId]
    if not characterData then return false end
    local effectComp = self.Components["Effect"]
    if not effectComp or not effectComp.GetService then return false end
    local service = effectComp.GetService()
    local ok, err = pcall(function()
        service:Remove(characterData, effectId)
    end)
    if not ok then
        warn(`RemoveEffect failed for {player.Name}: {err}`)
    end
    return ok
end

function Character:GetAbilityComponent()
    return self.Components["Ability"]
end

function Character:Destroy()
    for _, connection in pairs(self._connections) do
        connection:Disconnect()
    end
    
    local playersToCleanup = {}
    for _, characterData in pairs(self.CharacterRegistry) do
        table.insert(playersToCleanup, characterData.Player)
    end
    for _, plr in ipairs(playersToCleanup) do
        self:CleanupCharacter(plr)
    end
    
    table.clear(self.CharacterRegistry)
    table.clear(self.ActiveCharacters)
    table.clear(self.Components)
end

function Character:OnCharacterAdded(callback: (CharacterData) -> ())
    return CharacterAdded.Event:Connect(function(characterData: internalCharacter)
        callback(characterData :: CharacterData)
    end)
end

return Character.New()