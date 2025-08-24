--!strict
-- WeaponUtility.luau
-- Handles weapon instancing and attachment for characters

local AssetHandlers = require(game.ReplicatedStorage.Modules.AssetHandlers)
local WeldUtility = require(game.ServerStorage.Modules.Utilities.WeldUtility)

export type WeaponUtility = {
    AttachWeaponToCharacter: (characterModel: Model, sheathPart: BasePart) -> Model?,
}

local WeaponUtility = {}

-- Creates and attaches a weapon to the character, welding the handle to the sheath
function WeaponUtility.AttachWeaponToCharacter(characterModel: Model, sheathPart: BasePart): Model?
    local weaponHandler = AssetHandlers.OnModuleLoaded("Weapons")
    if not weaponHandler then
        warn("Failed to get weapon handler")
        return nil
    end
    
    local weaponAsset = weaponHandler:GetAsset("Default")
    if not weaponAsset or not weaponAsset.Instance then
        warn("Failed to get default weapon asset")
        return nil
    end
    
    local weaponModel = weaponAsset.Instance:Clone()
    if not weaponModel:IsA("Model") then
        warn("Weapon asset instance is not a Model")
        return nil
    end
    
    weaponModel.Parent = characterModel
    weaponModel.Name = "Weapon"

    local handle = weaponModel:FindFirstChild("Handle") :: BasePart?
    if handle and sheathPart then
        WeldUtility.WeldParts(sheathPart, handle, CFrame.new(0, 0, 0))
    end
    return weaponModel
end

return WeaponUtility
