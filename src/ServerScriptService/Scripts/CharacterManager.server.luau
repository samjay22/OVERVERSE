local CharacterManager = require(game.ServerStorage.Modules.Entities.Character)
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local Players = game:GetService("Players")

CharacterManager:OnCharacterAdded(function(character)
    print(`Character added: {character.Player.Name}`)
    character.OnDamage.Event:Connect(function(damage)
        print(`Character {character.Player.Name} took {damage} damage`)
    end)
    print("Called")
    -- CharacterManager:SetCharacterState(character.Player, "IsRunning", true)
    -- CharacterManager:DamageCharacter(character.Player, 10)
    -- Apply an effect via Character API
    -- CharacterManager:ApplyEffect(character.Player, "Fortify", { duration = 20 })
    -- CharacterManager:ApplyEffect(character.Player, "Bleed", { duration = 1, damage = 99 })
end)

-- Manual character spawning with configuration - trigger when needed
task.wait(3)

-- Example: Spawn character with a passive ability in their loadout
local exampleLoadout = {
    primaryAttacks = { "RemM1", "RemM2" },
    actives = { "Dash" }, -- Active ability in slot 1
    passive = "Keen",     -- Keen passive for critical hit bonuses
    animationPack = "Rem"
}

CharacterManager:SpawnCharacter(Players.samjay22, { 
    classId = "Rem", 
    loadoutAssetKey = "Rem",
    AbilityLoadout = exampleLoadout 
})