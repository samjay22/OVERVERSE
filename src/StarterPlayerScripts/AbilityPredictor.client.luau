--!strict
-- AbilityPredictor: Simplified client prediction using RenderStepped for input handling
-- Uses ClientAbilityStateManager and AbilityCategoryRegistry for all state

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local ClientAbilities = require(ReplicatedStorage.Modules.ClientAbilities)
local ClientCategoryHandler = require(ReplicatedStorage.Modules.Utility.ClientCategoryHandler)
local ClientAbilityStateManager = require(ReplicatedStorage.Modules.Utility.ClientAbilityStateManager)
local AbilityCategoryRegistry = require(ReplicatedStorage.Modules.Utility.AbilityCategoryRegistry)
local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)
local Enums = require(ReplicatedStorage.Modules.Types.Enums)

-- Import configuration modules
local Configuration = ReplicatedStorage.Modules:WaitForChild("Configuration")
local AbilityConfiguration = require(Configuration:WaitForChild("AbilityConfiguration"))
local InputConfiguration = require(Configuration:WaitForChild("InputConfiguration"))

type SharedAbilityContext = Types.SharedAbilityContext
type AbilityResult = Types.AbilityResult
type StateSnapshot = Types.StateSnapshot

-- Build numeric ID mapping from configuration
local function buildAbilityIdMap()
    local map = {}
    local abilities = AbilityConfiguration.GetConfig().abilities
    for id, ability in pairs(abilities) do
        map[id] = ability.numericId
    end
    return map
end

local ABILITY_ID_MAP = buildAbilityIdMap()

type AbilityInput = {
    direction: Vector3?,
    target: Vector3?,
    mouseHit: Vector3?,
    extraData: {[string]: any}?,
}

type PredictionData = {
    id: string,
    abilityId: string,
    timestamp: number,
    context: SharedAbilityContext,
    sent: boolean,
}

local ClientPredictor = {}
ClientPredictor.__index = ClientPredictor

function ClientPredictor.new()
    local self = setmetatable({}, ClientPredictor)
    
    self.player = Players.LocalPlayer
    self.stateManager = ClientAbilityStateManager.GetInstance()
    self.registry = AbilityCategoryRegistry.GetInstance()
    
    -- Prediction tracking
    self.predictions = {} :: {[string]: PredictionData}
    self.predictionCounter = 0
    
    -- Track which abilities are currently being held
    self.heldAbilities = {} :: {[string]: boolean}
    self.lastExecuteTimes = {} :: {[string]: number}
    
    -- Network
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    self.predictionRemote = remotes:WaitForChild("AbilityPrediction") :: RemoteEvent
    self.validationRemote = remotes:WaitForChild("AbilityValidation") :: RemoteEvent
    
    -- Server validation
    self.validationRemote.OnClientEvent:Connect(function(data)
        self:HandleServerValidation(data)
    end)
    
    return self :: any
end

function ClientPredictor:GeneratePredictionId(): string
    self.predictionCounter = self.predictionCounter + 1
    return `pred_{self.player.UserId}_{self.predictionCounter}`
end

function ClientPredictor:GetMouseInput(character: Model): AbilityInput?
    local mouse = self.player:GetMouse()
    if not mouse then return nil end
    
    local characterPos = character:GetPivot().Position
    local mousePos = mouse.Hit.Position
    
    -- Calculate direction
    local horizontalMousePos = Vector3.new(mousePos.X, characterPos.Y, mousePos.Z)
    local direction = (horizontalMousePos - characterPos)
    
    if direction.Magnitude > 0.001 then
        direction = direction.Unit
    else
        direction = character:GetPivot().LookVector
    end
    
    return {
        direction = direction,
        target = mousePos,
        mouseHit = mousePos,
    }
end

function ClientPredictor:ExecuteAbility(abilityId: string, input: AbilityInput): boolean
    print(`[ClientPredictor] Attempting to execute {abilityId}`)
    
    -- Get ability handler first to ensure it's loaded
    local ability = ClientAbilities.GetAbility(abilityId)
    if not ability then
        warn(`[ClientPredictor] Ability {abilityId} not found`)
        return false
    end
    
    -- Register ability if not already registered
    local registration = self.registry:GetAbility(abilityId)
    if not registration then
        if ability.GetSharedModule then
            local shared = ability.GetSharedModule()
            if shared and shared.GetConfig then
                local config = shared.GetConfig()
                if config then
                    print(`[ClientPredictor] Registering ability {abilityId} on first use`)
                    local success = self.registry:RegisterAbility(abilityId, config, ability)
                    if not success then
                        warn(`[ClientPredictor] Failed to register {abilityId}`)
                        return false
                    end
                else
                    warn(`[ClientPredictor] No config for {abilityId}`)
                    return false
                end
            else
                warn(`[ClientPredictor] No GetConfig for {abilityId}`)
                return false
            end
        else
            warn(`[ClientPredictor] No GetSharedModule for {abilityId}`)
            return false
        end
    end
    
    -- Check if ability is ready via state manager
    if not self.stateManager:IsReady(abilityId) then
        return false -- Don't spam console
    end
    
    -- Validate character
    local character = self.player.Character
    if not character then return false end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    
    -- Build context
    local numericId = ABILITY_ID_MAP[abilityId] or 0
    local now = workspace:GetServerTimeNow()
    
    local context: SharedAbilityContext = {
        playerId = self.player.UserId,
        abilityId = numericId,
        timestamp = now,
        inputData = {
            position = character:GetPivot().Position,
            direction = input.direction,
            target = input.target or input.mouseHit,
            mouseHit = input.mouseHit,
            extraData = input.extraData,
        },
        characterState = {
            timestamp = now,
            position = character:GetPivot().Position,
            velocity = character.PrimaryPart and character.PrimaryPart.AssemblyLinearVelocity or Vector3.zero,
            health = humanoid.Health,
            stamina = 100,
            cooldowns = {},
            effects = {},
        },
    }
    
    -- Use the ability through state manager to track cooldowns/ammo
    local canUse = self.stateManager:UseAbility(abilityId)
    print(`[ClientPredictor] UseAbility returned {canUse} for {abilityId}`)
    if not canUse then
        print(`[ClientPredictor] State manager rejected {abilityId}`)
        return false
    end
    
    print(`[ClientPredictor] About to execute {abilityId} via CategoryHandler`)
    print(`[ClientPredictor] ability = {ability}, context.abilityId = {context.abilityId}`)
    
    -- Execute via category handler
    ClientCategoryHandler.ExecuteAbility(ability, context)
    
    print(`[ClientPredictor] Executed {abilityId}`)
    
    -- Create prediction for server validation
    local predictionId = self:GeneratePredictionId()
    self.predictions[predictionId] = {
        id = predictionId,
        abilityId = abilityId,
        timestamp = now,
        context = context,
        sent = false,
    }
    
    -- Send to server
    task.spawn(function()
        self.predictionRemote:FireServer({
            predictionId = predictionId,
            abilityId = abilityId,
            inputData = input,
            timestamp = now,
            originalState = context.characterState,
        })
        
        local prediction = self.predictions[predictionId]
        if prediction then
            prediction.sent = true
        end
    end)
    
    -- Clean up old predictions
    task.delay(10, function()
        self.predictions[predictionId] = nil
    end)
    
    -- Track last execute time
    self.lastExecuteTimes[abilityId] = now
    
    return true
end

function ClientPredictor:HandleReload()
    print("[ClientPredictor] HandleReload called")
    -- Find all abilities that use ammo and reload them
    local reloadedAbilities = {}
    local allAbilities = self.registry:GetAllAbilities()
    
    local count = 0
    for _ in pairs(allAbilities) do count = count + 1 end
    print(`[ClientPredictor] Checking {count} abilities for reload`)
    
    for abilityId, registration in pairs(allAbilities) do
        print(`[ClientPredictor] Checking ability: {abilityId}`)
        
        -- Get config from AbilityConfiguration to check resource type
        local AbilityConfiguration = require(ReplicatedStorage.Modules.Configuration.AbilityConfiguration)
        local abilityConfig = AbilityConfiguration.GetAbility(abilityId)
        
        if abilityConfig and abilityConfig.resource and abilityConfig.resource.type == "ammo" then
            print(`[ClientPredictor] {abilityId} uses ammo - starting reload`)
            self.stateManager:StartReload(abilityId)
            table.insert(reloadedAbilities, abilityId)
        else
            local resourceType = abilityConfig and abilityConfig.resource and abilityConfig.resource.type or "unknown"
            print(`[ClientPredictor] {abilityId} uses {resourceType} - skipping`)
        end
    end
    
    if #reloadedAbilities == 0 then
        print("[ClientPredictor] No ammo-based abilities to reload")
    else
        print(`[ClientPredictor] Reloading {#reloadedAbilities} abilities: {table.concat(reloadedAbilities, ", ")}`)
    end
end

function ClientPredictor:HandleServerValidation(data: any)
    local prediction = self.predictions[data.predictionId]
    if not prediction then return end
    
    if data.success then
        -- Apply server cooldowns to state manager
        if data.cooldowns then
            self.stateManager:ApplyServerCooldowns(data.cooldowns)
        end
        
        -- Apply any server state corrections
        if data.correctedState then
            local character = self.player.Character
            if character then
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if humanoid and data.correctedState.health then
                    humanoid.Health = data.correctedState.health
                end
            end
        end
    else
        -- Server rejected - notify ability handler
        warn(`[ClientPredictor] Server rejected {prediction.abilityId}: {data.reason or "Unknown"}`)
        
        local ability = ClientAbilities.GetAbility(prediction.abilityId)
        if ability and ability.OnCancel then
            pcall(ability.OnCancel, prediction.context, data.reason)
        end
        
        -- Reset ability state if needed
        if data.resetState then
            self.stateManager:ResetAbility(prediction.abilityId)
        end
    end
    
    -- Clean up prediction
    self.predictions[data.predictionId] = nil
end

function ClientPredictor:SetupInputHandling()
    -- Initialize input configuration
    InputConfiguration.Initialize()
    
    -- Track input state
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        local character = self.player.Character
        if not character then return end
        
        -- Get ability from configured input
        local slotId = InputConfiguration.GetSlotFromInput(input)
        if not slotId then 
            -- Check for reload
            if input.KeyCode == Enum.KeyCode.R then
                print("[ClientPredictor] R key pressed - triggering reload")
                self:HandleReload()
            end
            return
        end
        
        local abilityId = InputConfiguration.GetAbilityForSlot(slotId)
        if not abilityId then return end
        
        -- Check if ability is enabled in configuration
        local abilityConfig = AbilityConfiguration.GetAbility(abilityId)
        if not abilityConfig or not abilityConfig.enabled then
            return
        end
        
        -- Check if ability is holdable from configuration
        local binding = InputConfiguration.GetBinding(slotId)
        if binding and binding.holdable then
            -- Mark as held for RenderStepped to handle
            self.heldAbilities[abilityId] = true
            print(`[ClientPredictor] Started holding {abilityId}`)
        else
            -- Single press - execute immediately
            local inputData = self:GetMouseInput(character)
            if inputData then
                self:ExecuteAbility(abilityId, inputData)
            end
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        local slotId = InputConfiguration.GetSlotFromInput(input)
        if slotId then
            local abilityId = InputConfiguration.GetAbilityForSlot(slotId)
            if abilityId then
                self.heldAbilities[abilityId] = false
                print(`[ClientPredictor] Stopped holding {abilityId}`)
            end
        end
    end)
end

function ClientPredictor:StartRenderSteppedLoop()
    -- Use RenderStepped for frame-perfect input handling
    RunService.RenderStepped:Connect(function(deltaTime)
        local character = self.player.Character
        if not character then return end
        
        local now = workspace:GetServerTimeNow()
        
        -- Process held abilities
        for abilityId, isHeld in pairs(self.heldAbilities) do
            if isHeld then
                -- Check if we can execute again (respecting fire rate)
                local lastTime = self.lastExecuteTimes[abilityId] or 0
                local config = AbilityConfiguration.GetAbility(abilityId)
                
                if config and config.resource then
                    local fireRate = config.resource.fireRate or 0.1
                    
                    if now - lastTime >= fireRate then
                        -- Check if ability is ready
                        if self.stateManager:IsReady(abilityId) then
                            local inputData = self:GetMouseInput(character)
                            if inputData then
                                self:ExecuteAbility(abilityId, inputData)
                            end
                        end
                    end
                end
            end
        end
    end)
end

function ClientPredictor:Initialize()
    -- Wait for abilities to load
    print("[ClientPredictor] Waiting for abilities to load...")
    local attempts = 0
    repeat
        task.wait(0.5)
        attempts = attempts + 1
        local hasM1 = ClientAbilities.GetAbility("RemM1") ~= nil
        local hasM2 = ClientAbilities.GetAbility("RemM2") ~= nil
        if hasM1 or hasM2 then
            print("[ClientPredictor] Abilities loaded!")
            break
        end
    until attempts > 10
    
    -- Setup input handling
    self:SetupInputHandling()
    
    -- Start the RenderStepped loop for held abilities
    self:StartRenderSteppedLoop()
    
    -- Force scan for abilities on startup
    local registered = self.registry:ScanAndRegisterAbilities()
    print(`[ClientPredictor] Initial scan registered {registered} abilities`)
    
    print("[ClientPredictor] Initialized with RenderStepped input handling")
    
    -- Print configured controls
    local enabledAbilities = AbilityConfiguration.GetEnabledAbilities()
    if #enabledAbilities > 0 then
        print("Configured abilities:")
        for _, ability in ipairs(enabledAbilities) do
            local slot = InputConfiguration.GetSlotForAbility(ability.id)
            if slot then
                local binding = InputConfiguration.GetBinding(slot)
                if binding then
                    local display = InputConfiguration.GetBindingDisplay(binding)
                    print(`  {display} - {ability.displayName} ({ability.id})`)
                end
            end
        end
        print("  R - Reload ammo abilities")
    end
end

-- Create and initialize
local predictor = ClientPredictor.new()
predictor:Initialize()

return predictor