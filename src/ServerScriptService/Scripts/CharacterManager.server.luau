local Players = game:GetService("Players")

local PlayerQueue = {}

Players.PlayerAdded:Connect(function(plr)
    table.insert(PlayerQueue, plr)
end)

local CharacterManager = require(game.ServerStorage.Modules.Entities.Character)
CharacterManager:OnCharacterAdded(function(character)
    -- Use Entity.name instead of Player.Name to support both players and NPCs
    local entityName = character.Entity and character.Entity.name or "Unknown"
    character.OnDamage.Event:Connect(function(damage)
        print(`Character {entityName} took {damage} damage`)
    end)

    -- CharacterManager:SetCharacterState(character.Player, "IsRunning", true)
    -- CharacterManager:DamageCharacter(character.Player, 10)
    -- Apply an effect via Character API
    -- CharacterManager:ApplyEffect(character.Player, "Fortify", { duration = 20 })
    -- CharacterManager:ApplyEffect(character.Player, "Bleed", { duration = 1, damage = 99 })
end)

 while true do 
    task.wait()
    local plr = table.remove(PlayerQueue, 1)
    if plr then
        -- Manual character spawning with configuration - trigger when needed           
           -- Example: Spawn character with a passive ability in their loadout
           local exampleLoadout = {
               primaryAttacks = { "Rem-M1", "Rem-M2" },
               actives = { "Dash" }, -- Active ability in slot 1
               passive = "Keen",     -- Keen passive for critical hit bonuses
               animationPack = "Rem"
           }
           
           print("ran")
           CharacterManager:SpawnCharacter(plr, { 
               classId = "Rem", 
               loadoutAssetKey = "Rem",
               AbilityLoadout = exampleLoadout 
           })
    end
end