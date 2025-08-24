local CharacterManager = require(game.ServerStorage.Modules.Entities.Character)
local Players = game:GetService("Players")

local NPC = nil

-- Create a single NPC
local function createNPC()
    -- Create the NPC model
    local npcModel = Instance.new("Model")
    npcModel.Name = "TestNPC"
    npcModel.Parent = game.Workspace
    
    -- Create basic humanoid structure
    local humanoid = Instance.new("Humanoid")
    humanoid.Parent = npcModel
    
    -- Create PlayerId folder for consistency with player characters
    local playerId = Instance.new("IntValue")
    playerId.Name = "PlayerId"
    playerId.Value = -1 -- Negative ID for NPC
    playerId.Parent = npcModel

    local playerMock = Instance.new("StringValue")
    playerMock.Name = "Player"
    playerMock.Value = "NPC_1"
    playerMock.Parent = npcModel

    local nameMock = Instance.new("StringValue")
    nameMock.Name = "Name"
    nameMock.Value = npcModel.Name
    nameMock.Parent = playerMock

    -- Set NPC attributes
    npcModel:SetAttribute("NPCClass", "Default")
    npcModel:SetAttribute("NPCLoadout", "Default")
    npcModel:SetAttribute("NPCMaxHealth", 100)
    npcModel:SetAttribute("NPCWalkSpeed", 16)
    
    -- Store NPC reference
    NPC = {
        character = npcModel,
        npcId = 1
    }
    
    -- Spawn NPC character through CharacterManager
    task.spawn(function()
        local npcConfig = {
            classId = npcModel:GetAttribute("NPCClass"),
            loadoutAssetKey = npcModel:GetAttribute("NPCLoadout"),
            MaxHealth = npcModel:GetAttribute("NPCMaxHealth"),
            WalkSpeed = npcModel:GetAttribute("NPCWalkSpeed"),
            IsNPC = true,
            NPCName = npcModel.Name
        }
        
        local success, result = pcall(function()
            return CharacterManager:SpawnNPC(npcModel, npcConfig)
        end)
        
        if success and result then
            print(`✅ NPC {npcModel.Name} successfully registered with CharacterManager`)
            NPC.characterData = result
        else
            warn(`❌ Failed to register NPC {npcModel.Name} with CharacterManager: {result}`)
        end
    end)
end

-- Utility functions for NPC management
local NPCManager = {}

function NPCManager.GetNPC()
    return NPC
end

function NPCManager.DamageNPC(damage: number)
    if NPC and NPC.characterData then
        return CharacterManager:DamageCharacter(-NPC.npcId, damage)
    end
    return false
end

function NPCManager.ApplyEffectToNPC(effectId: string, context: {[string]: any}?)
    if NPC and NPC.characterData then
        return CharacterManager:ApplyEffect(-NPC.npcId, effectId, context)
    end
    return false
end

function NPCManager.SetNPCState(stateName: string, value: any)
    if NPC and NPC.characterData then
        return CharacterManager:SetCharacterState(-NPC.npcId, stateName, value)
    end
    return false
end

-- Create the NPC
createNPC()

-- Export NPCManager for use by other scripts
_G.NPCManager = NPCManager

print(`✅ Single NPC initialization completed.`)