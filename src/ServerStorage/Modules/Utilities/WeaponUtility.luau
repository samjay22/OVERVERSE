--!nonstrict
-- WeaponUtility.luau
-- Handles weapon instancing and attachment for characters

local WeaponAssets = require(game.ReplicatedStorage.Modules.AssetHandlers).OnModuleLoaded("Weapons")
local WeldUtility = require(game.ServerStorage.Modules.Utilities.WeldUtility)

local WeaponUtility = {}

-- Creates and attaches a weapon to the character, welding the handle to the sheath
function WeaponUtility.AttachWeaponToCharacter(characterModel: Model, sheathPart: BasePart)
    local weaponModel = WeaponAssets.GetAsset("Default").Instance:Clone()
    weaponModel.Parent = characterModel
    weaponModel.Name = "Weapon"

    local handle = weaponModel:FindFirstChild("Handle")
    if handle and sheathPart then
        WeldUtility.WeldParts(sheathPart, handle, CFrame.new(0, 0, 0))
    end
    return weaponModel
end

return WeaponUtility
