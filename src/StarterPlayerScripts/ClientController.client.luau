--!strict
-- ClientController: Unified client-side input and ability management
-- Handles input capture, ability execution, and server communication

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies
local NetworkClient = require(ReplicatedStorage.Modules.Network.Client)
local AbilityTypes = require(ReplicatedStorage.Modules.Types.AbilityTypes)

-- Constants
local INPUT_DEBOUNCE_TIME = 0.016 -- Prevent duplicate inputs within a frame
local ABILITY_FOLDER = ReplicatedStorage.Modules.Abilities
local LOCAL_PLAYER = Players.LocalPlayer

-- Types
type InputKey = Enum.KeyCode | Enum.UserInputType

type AbilityState = {
    module: AbilityTypes.AbilityModule,
    isActive: boolean,
    startTime: number,
    lastUpdateTime: number,
    inputState: InputState,
}

type InputState = {
    isPressed: boolean,
    pressTime: number,
    releaseTime: number?,
}

type CharacterData = {
    name: string,
    abilities: {[InputKey]: AbilityTypes.AbilityModule},
    loadTime: number,
}

-- State Management
local currentCharacter: CharacterData? = nil
local characterCache: {[string]: CharacterData} = {}
local abilityStates: {[InputKey]: AbilityState} = {}
local inputStates: {[InputKey]: InputState} = {}

-- Connections
local connections: {[string]: RBXScriptConnection?} = {}
local networkListeners: {[string]: (() -> ())?} = {}

-- Utility Functions
local function debugPrint(message: string)
    print(`[ClientController] {message}`)
end

local function debugWarn(message: string)
    warn(`[ClientController] {message}`)
end

-- Character Management Functions
local function loadCharacterAbilities(characterName: string): CharacterData?
    -- Check cache first
    local cached = characterCache[characterName]
    if cached then
        debugPrint(`Loaded character from cache: {characterName}`)
        return cached
    end
    
    -- Find character ability folder
    local characterFolder = ABILITY_FOLDER:FindFirstChild(characterName)
    if not characterFolder then
        debugWarn(`No abilities found for character: {characterName}`)
        return nil
    end
    
    -- Load ability modules
    local success, abilityModule = pcall(require, characterFolder)
    if not success then
        debugWarn(`Failed to load abilities for {characterName}: {abilityModule}`)
        return nil
    end
    
    -- Build character data structure
    local characterData: CharacterData = {
        name = characterName,
        abilities = {},
        loadTime = tick(),
    }
    
    -- Map abilities by their input key
    for inputKey, ability in pairs(abilityModule) do
        if typeof(inputKey) == "EnumItem" and typeof(ability) == "table" then
            -- Ensure it's a valid input key type
            local key = inputKey :: InputKey
            characterData.abilities[key] = ability
        end
    end
    
    -- Cache for future use
    characterCache[characterName] = characterData
    
    -- Count abilities properly
    local abilityCount = 0
    for _ in pairs(characterData.abilities) do
        abilityCount += 1
    end
    debugPrint(`Loaded character: {characterName} with {abilityCount} abilities`)
    return characterData
end

local function setCurrentCharacter(characterName: string?)
    -- Handle empty or nil character name
    if not characterName or characterName == "" then
        -- Unload current character
        if currentCharacter then
            debugPrint(`Unloading character: {currentCharacter.name}`)
            
            -- Cancel all active abilities
            for inputKey, abilityState in pairs(abilityStates) do
                local ability = abilityState.module
                if ability.Client and ability.Client.OnCancel then
                    pcall(function()
                        ability.Client:OnCancel(LOCAL_PLAYER)
                    end)
                end
            end
            
            table.clear(abilityStates)
            table.clear(inputStates)
            currentCharacter = nil
        end
        return
    end
    
    -- Load new character
    local characterData = loadCharacterAbilities(characterName)
    if characterData then
        currentCharacter = characterData
        debugPrint(`Set current character to: {characterName}`)
    end
end

-- Ability Execution Functions
local function executeAbility(inputKey: InputKey, abilityState: AbilityState): boolean
    local ability = abilityState.module
    
    -- Ensure client module exists
    if not ability.Client or not ability.Client.OnUse then
        debugWarn(`Ability {ability.Name} missing Client.OnUse`)
        return false
    end
    
    -- Execute ability with error handling
    local success, result = pcall(function()
        return ability.Client:OnUse(LOCAL_PLAYER)
    end)
    
    if not success then
        debugWarn(`Ability execution error for {ability.Name}: {result}`)
        return false
    end
    
    -- Return whether ability should continue
    return result == true
end

local function updateActiveAbilities(deltaTime: number)
    local hasActiveAbilities = false
    local currentTime = tick()
    
    -- Process each active ability
    for inputKey, abilityState in pairs(abilityStates) do
        if abilityState.isActive then
            hasActiveAbilities = true
            
            -- Execute ability update
            local shouldContinue = executeAbility(inputKey, abilityState)
            
            if shouldContinue then
                -- Update timing
                abilityState.lastUpdateTime = currentTime
            else
                -- Ability finished, clean up
                local ability = abilityState.module
                if ability.Client and ability.Client.OnCancel then
                    pcall(function()
                        ability.Client:OnCancel(LOCAL_PLAYER)
                    end)
                end
                
                -- Remove from active abilities
                abilityStates[inputKey] = nil
            end
        end
    end
    
    -- Stop update loop if no active abilities
    if not hasActiveAbilities and connections.updateLoop then
        connections.updateLoop:Disconnect()
        connections.updateLoop = nil
    end
end

local function startAbilityUpdateLoop()
    if not connections.updateLoop then
        connections.updateLoop = RunService.Heartbeat:Connect(updateActiveAbilities)
    end
end

-- Input Processing Functions
local function processInputBegan(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end
    
    local inputKey: InputKey = if input.KeyCode ~= Enum.KeyCode.Unknown 
        then input.KeyCode 
        else input.UserInputType
    
    local currentTime = tick()
    
    -- Check for debounce
    local inputState = inputStates[inputKey]
    if inputState and inputState.isPressed and (currentTime - inputState.pressTime) < INPUT_DEBOUNCE_TIME then
        return
    end
    
    -- Update input state
    inputStates[inputKey] = {
        isPressed = true,
        pressTime = currentTime,
        releaseTime = nil,
    }
    
    -- Send raw input to server
    NetworkClient.ClientInputEvent.Fire({
        KeyCode = input.KeyCode.Name,
        UserInputType = input.UserInputType.Name,
        IsPressed = true,
    })
    
    -- Check if this input triggers an ability
    if currentCharacter then
        local ability = currentCharacter.abilities[inputKey]
        if ability and ability.Client and ability.Client.OnUse then
            -- Create ability state
            abilityStates[inputKey] = {
                module = ability,
                isActive = true,
                startTime = currentTime,
                lastUpdateTime = currentTime,
                inputState = inputStates[inputKey],
            }
            
            -- Start update loop
            startAbilityUpdateLoop()
        end
    end
end

local function processInputEnded(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end
    
    local inputKey: InputKey = if input.KeyCode ~= Enum.KeyCode.Unknown 
        then input.KeyCode 
        else input.UserInputType
    
    -- Update input state
    local inputState = inputStates[inputKey]
    if inputState then
        inputState.isPressed = false
        inputState.releaseTime = tick()
    end
    
    -- Send raw input to server
    NetworkClient.ClientInputEvent.Fire({
        KeyCode = input.KeyCode.Name,
        UserInputType = input.UserInputType.Name,
        IsPressed = false,
    })
    
    -- Mark ability as inactive (let it finish naturally)
    local abilityState = abilityStates[inputKey]
    if abilityState then
        abilityState.isActive = false
    end
end

-- Network Event Handlers
local function handleAbilityReplication(data: {
    AbilityName: string,
    CharacterName: string,
    PlayerCaster: Player,
    Direction: Vector3,
    Position: Vector3,
})
    -- Don't replicate our own abilities
    if data.PlayerCaster == LOCAL_PLAYER then
        return
    end
    
    -- Load character abilities if needed
    local characterData = characterCache[data.CharacterName]
    if not characterData then
        local loaded = loadCharacterAbilities(data.CharacterName)
        if not loaded then
            return
        end
        characterData = loaded
    end
    
    -- Find and execute ability replication
    for _, ability in pairs(characterData.abilities) do
        if ability.Name == data.AbilityName then
            if ability.Client and ability.Client.OnReplicate then
                pcall(function()
                    ability.Client:OnReplicate(data.PlayerCaster)
                end)
            end
            break
        end
    end
end

local function handleStateSync(syncData: {States: {[string]: any}})
    if not currentCharacter then
        return
    end
    
    -- Forward state sync to all active abilities
    for _, abilityState in pairs(abilityStates) do
        local ability = abilityState.module
        if ability.Client and ability.Client.OnStateSync then
            pcall(function()
                ability.Client:OnStateSync(syncData.States)
            end)
        end
    end
end

-- Initialize Controller
local function initialize()
    debugPrint("Initializing...")
    
    -- Setup input connections
    connections.inputBegan = UserInputService.InputBegan:Connect(processInputBegan)
    connections.inputEnded = UserInputService.InputEnded:Connect(processInputEnded)
    
    -- Setup network event listeners
    networkListeners.setCharacter = NetworkClient.SetCharacter.On(setCurrentCharacter)
    networkListeners.castAbility = NetworkClient.CastAbility.On(handleAbilityReplication)
    
    -- StateSync with capital S
    if NetworkClient.StateSync then
        networkListeners.stateSync = NetworkClient.StateSync.On(handleStateSync)
    end
    
    debugPrint("Initialization complete")
end

-- Cleanup on script removal
local function cleanup()
    debugPrint("Cleaning up...")
    
    -- Cancel all active abilities
    for inputKey, abilityState in pairs(abilityStates) do
        local ability = abilityState.module
        if ability.Client and ability.Client.OnCancel then
            pcall(function()
                ability.Client:OnCancel(LOCAL_PLAYER)
            end)
        end
    end
    
    -- Disconnect all connections
    for name, connection in pairs(connections) do
        if connection then
            connection:Disconnect()
        end
    end
    
    -- Remove network listeners
    for name, listener in pairs(networkListeners) do
        if listener then
            listener()
        end
    end
    
    -- Clear state
    table.clear(abilityStates)
    table.clear(inputStates)
    table.clear(connections)
    table.clear(networkListeners)
    
    debugPrint("Cleanup complete")
end

-- Setup cleanup handler
script.AncestryChanged:Connect(function()
    if not script.Parent then
        cleanup()
    end
end)

-- Start the controller
initialize()