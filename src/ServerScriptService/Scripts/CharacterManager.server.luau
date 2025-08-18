local CharacterManager = require(game.ServerStorage.Modules.Entities.Character)
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)

local configuredOnce: {[number]: boolean} = {}

CharacterManager:OnCharacterAdded(function(character)
    -- Change class only once per player to avoid recursive respawn loops
    local pid = character.PlayerId or character.Player.UserId
    if not configuredOnce[pid] then
        configuredOnce[pid] = true
        task.defer(function()
            CharacterManager:SetCharacter(character.Player, { classId = "Rem", loadoutAssetKey = "Rem" })
        end)
    end
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
    
    task.delay(2, function()
        CharacterManager:CastAbility(character.Player, Enums.AbilityId.Heal)
    end)
end)
