local CharacterManager = require(game.ServerStorage.Modules.Entities.Character)
local Players = game:GetService("Players")

local NPCS = {}

-- Initialize NPCs found in workspace
local npcCounter = 1

for _, model in game.Workspace:GetDescendants() do
    if model:IsA("Humanoid") then
        local char = model.Parent
        if char and char:IsA("Model") and not Players:GetPlayerFromCharacter(char) then
            -- This is an NPC (has humanoid but no associated player)
            
            -- Create PlayerId folder for consistency with player characters
            local playerId = Instance.new("IntValue")
            playerId.Name = "PlayerId"
            playerId.Value = -npcCounter -- Negative ID for NPCs
            playerId.Parent = char

            local playerMock = Instance.new("StringValue")
            playerMock.Name = "Player"
            playerMock.Value = "NPC_" .. npcCounter
            playerMock.Parent = char

            local nameMock = Instance.new("StringValue")
            nameMock.Name = "Name"
            nameMock.Value = char.Name
            nameMock.Parent = playerMock

            -- Set default NPC attributes if not already set
            if not char:GetAttribute("NPCClass") then
                char:SetAttribute("NPCClass", "Default")
            end
            if not char:GetAttribute("NPCLoadout") then
                char:SetAttribute("NPCLoadout", "Default")
            end
        
            -- Add NPC to our tracking
            NPCS[char.Name] = {
                character = char,
                npcId = npcCounter
            }
            
            -- Spawn NPC character through CharacterManager
            task.spawn(function()
                -- Give the character some basic configuration
                local npcConfig = {
                    classId = char:GetAttribute("NPCClass") or "Default",
                    loadoutAssetKey = char:GetAttribute("NPCLoadout") or "Default",
                    MaxHealth = char:GetAttribute("NPCMaxHealth") or 100,
                    WalkSpeed = char:GetAttribute("NPCWalkSpeed") or 16,
                    IsNPC = true,
                    NPCName = char.Name
                }
                
                -- Spawn NPC character through CharacterManager
                local success, result = pcall(function()
                    return CharacterManager:SpawnNPC(char, npcConfig)
                end)
                
                if success and result then
                    print(`✅ NPC {char.Name} successfully registered with CharacterManager`)
                    NPCS[char.Name].characterData = result
                else
                    warn(`❌ Failed to register NPC {char.Name} with CharacterManager: {result}`)
                end
            end)
            
            npcCounter = npcCounter + 1
        end
    end
end

-- Utility functions for NPC management
local NPCManager = {}

function NPCManager.GetNPC(npcName: string)
    return NPCS[npcName]
end

function NPCManager.GetAllNPCs()
    return NPCS
end

function NPCManager.DamageNPC(npcName: string, damage: number)
    local npc = NPCS[npcName]
    if npc and npc.characterData then
        -- Use the NPC's negative user ID for damage
        return CharacterManager:DamageCharacter(-npc.npcId, damage)
    end
    return false
end

function NPCManager.ApplyEffectToNPC(npcName: string, effectId: string, context: {[string]: any}?)
    local npc = NPCS[npcName]
    if npc and npc.characterData then
        return CharacterManager:ApplyEffect(-npc.npcId, effectId, context)
    end
    return false
end

function NPCManager.SetNPCState(npcName: string, stateName: string, value: any)
    local npc = NPCS[npcName]
    if npc and npc.characterData then
        return CharacterManager:SetCharacterState(-npc.npcId, stateName, value)
    end
    return false
end

-- Export NPCManager for use by other scripts
_G.NPCManager = NPCManager

print(`✅ NPC initialization completed. Found and processed {npcCounter - 1} NPCs.`)

