local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharacterTypes = require(ServerStorage.Modules.Types.CharacterTypes)
local AbilityComponent = require(game.ServerStorage.Modules.Components.AbilityComponent)
local AbilityInputHandler = require(game.ServerStorage.Modules.Handlers.AbilityInputHandler)
local NetworkServer = require(ReplicatedStorage.Modules.Network.Server)
local CharacterManager = require(ServerStorage.Modules.Entities.Character.CharacterManager)

AbilityInputHandler.onAbilityActivated = function(inputType, abilityName, characterData)
    -- characterData is a table containing { loadout, keyBindings, character, name }
    local character = characterData.character
    
    if not character then
        warn("No character in characterData for ability activation")
        return
    end
    
    -- Commented out to reduce spam
    -- print(`Ability activated: ${abilityName} for ${characterName}`)
    
    -- Get the player - character has Entity field with player reference
    local player = nil
    if character.Entity and character.Entity.player then
        player = character.Entity.player
    elseif character.Player then
        player = character.Player
    elseif character.PlayerId then
        -- PlayerId is actually the UserId for players
        for _, p in ipairs(Players:GetPlayers()) do
            if p.UserId == character.PlayerId then
                player = p
                break
            end
        end
    end
    
    if player then
        -- Get target data from MouseComponent if available
        local targetData = nil
        if character.Components and character.Components.Mouse then
            local mouseComponent = character.Components.Mouse
            targetData = {
                position = mouseComponent.MouseHitPosition,
                target = mouseComponent.MouseTarget,
                normal = mouseComponent.MouseHitNormal
            }
        elseif character.StateManager then
            -- Fallback to StateManager if MouseComponent not directly accessible
            targetData = {
                position = character.StateManager:Get("MouseHitPosition"),
                target = character.StateManager:Get("MouseTarget"),
                normal = character.StateManager:Get("MouseHitNormal")
            }
        end

        warn(`Ability activated: ${abilityName} for ${character.Name}`)
        AbilityComponent.Activate((character :: CharacterTypes.internalCharacter).Entity.player, abilityName, targetData)
    else
        warn("Could not find player for ability activation - PlayerId:", character.PlayerId)
    end
end

-- Initialize the input handler
AbilityInputHandler.initialize()

-- ===============================
-- NETWORK PING COMPENSATION SYSTEM
-- ===============================

-- Handle client ability cast requests with network latency compensation
NetworkServer.RequestAbilityCast.On(function(player: Player, data: { AbilityId: number, Target: Model?, Position: Vector3 })
    local characterData = CharacterManager:GetCharacterData(player)
    if not characterData then
        warn(`[AbilityManager] No character data found for player {player.Name}`)
        return
    end

    -- Get network ping for latency compensation
    local networkPing = player:GetNetworkPing()
    local clientTimestamp = tick()

    -- Convert AbilityId to ability name (assuming numeric IDs map to ability names)
    local abilityName = tostring(data.AbilityId) -- You may need to implement proper ID->name mapping

    -- Prepare target data with network compensation
    local targetData = {
        position = data.Position,
        target = data.Target,
        networkPing = networkPing,
        clientTimestamp = clientTimestamp,
        serverTimestamp = tick()
    }

    -- Execute ability with network-aware timing
    local success = AbilityComponent.Activate(player, abilityName, targetData)

    if success then
        print(`[AbilityManager] Successfully processed ability cast: {abilityName} for {player.Name} (ping: {math.floor(networkPing * 1000)}ms)`)
    else
        warn(`[AbilityManager] Failed to process ability cast: {abilityName} for {player.Name}`)
    end
end)