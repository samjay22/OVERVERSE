local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Abilities = game.ReplicatedStorage.Modules.Abilities

local Types = require(game.ReplicatedStorage.Modules.Types.AbilityTypes)

local SetCharacter : RemoteEvent = game.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SetCharacter")
local CastAbility : RemoteEvent = game.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CastAbility")

local CharacterName : string?
local ActiveInputs : {[Enum.KeyCode | Enum.UserInputType]: {
    ability: Types.AbilityModule,
    lastFired: number,
    lastServerFired: number,
}} = {}

-- Cache loaded ability modules
local loadedAbilities : {[string]: {[Enum.KeyCode | Enum.UserInputType]: Types.AbilityModule}} = {}

-- Track RenderStepped connection
local renderConnection: RBXScriptConnection?

-- Constants
local SERVER_FIRE_RATE = 0.05 -- Fire to server at same rate as processing

SetCharacter.OnClientEvent:Connect(function(name: string)
    CharacterName = name
    -- Preload abilities for this character
    if name then
        local abilities = Abilities:FindFirstChild(name)
        if abilities then
            local success, data = pcall(require, abilities)
            if success then
                loadedAbilities[name] = data
            end
        end
    end
end)

-- Process abilities on RenderStepped
local function processAbilities(_deltaTime: number)
    local hasActiveAbilities = false
    local currentTime = tick()
    
    for inputKey, inputData in pairs(ActiveInputs) do
        hasActiveAbilities = true
        
        -- Execute client-side ability (visual/animation)
        local success, result = pcall(function()
            return inputData.ability.Client:OnUse(Players.LocalPlayer)
        end)
        
        if not success then
            warn("Ability execution error:", result)
            ActiveInputs[inputKey] = nil
        elseif result then
            -- Only fire to server if client ability actually fired (not on cooldown)
            -- The client OnUse returns true even on cooldown, but only fires when CanAttack is true
            -- So we check the internal state to see if it actually fired
            if inputData.ability.Client.InternalState and not inputData.ability.Client.InternalState.CanAttack then
                -- Just fired, send to server
                if currentTime - inputData.lastServerFired >= SERVER_FIRE_RATE then
                    local abilityName = inputData.ability.Name or "Unknown"
                    CastAbility:FireServer(CharacterName .. "-" .. abilityName)
                    inputData.lastServerFired = currentTime
                end
            end
        end
    end
    
    -- Auto-disconnect if no active abilities
    if not hasActiveAbilities and renderConnection then
        renderConnection:Disconnect()
        renderConnection = nil
    end
end

-- Get ability for input
local function getAbilityForInput(input: InputObject): Types.AbilityModule?
    if not CharacterName then
        return nil
    end
    
    -- Check cache first
    local characterAbilities = loadedAbilities[CharacterName]
    if not characterAbilities then
        -- Load if not cached
        local abilitiesFolder = Abilities:FindFirstChild(CharacterName)
        if not abilitiesFolder then
            return nil
        end
        
        local success, data = pcall(require, abilitiesFolder)
        if success then
            loadedAbilities[CharacterName] = data
            characterAbilities = data
        else
            return nil
        end
    end
    
    -- Get ability by input
    return characterAbilities[input.UserInputType] or characterAbilities[input.KeyCode]
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
    if gameProcessed then
        return
    end
    
    local ability = getAbilityForInput(input)
    if not ability or not ability.Client or not ability.Client.OnUse then
        return
    end
    
    local inputKey = input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode or input.UserInputType
    
    -- Add to active inputs
    ActiveInputs[inputKey] = {
        ability = ability,
        lastFired = 0,
        lastServerFired = 0,
    }
    
    -- Start RenderStepped if not already running
    if not renderConnection then
        renderConnection = RunService.RenderStepped:Connect(processAbilities)
    end
end)

UserInputService.InputEnded:Connect(function(input: InputObject, gameProcessed: boolean)
    if gameProcessed then
        return
    end
    
    local inputKey = input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode or input.UserInputType
    
    -- Get ability data before removing
    local inputData = ActiveInputs[inputKey]
    
    -- Remove from active inputs
    ActiveInputs[inputKey] = nil
    
    -- Call OnCancel if ability has it
    if inputData and inputData.ability and inputData.ability.Client.OnCancel then
        pcall(function()
            inputData.ability.Client:OnCancel(Players.LocalPlayer)
        end)
    end
end)