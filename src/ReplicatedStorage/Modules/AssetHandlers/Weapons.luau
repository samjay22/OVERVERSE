--!strict
local InsertService = game:GetService("InsertService")

local AssetTypes = require(game.ReplicatedStorage.Modules.Types.AssetTypes)

local assetCache: { [string]: AssetTypes.AssetValue } = {}
local assetIdMap: {[string]: string} = {
    Default = "121165247373475",
}

local function loadAsset(assetName: string): AssetTypes.AssetValue?
    if assetCache[assetName] then
        return assetCache[assetName]
    end

    local assetId = assetIdMap[assetName]
    if not assetId then
        return nil
    end

    -- Lazy load the actual Roblox asset
    local success, result = pcall(function()
        local assetModel = InsertService:LoadAsset(tonumber(assetId) :: number)
        local weaponModel = assetModel:GetChildren()[1] -- Assuming the asset is a single model
        if not weaponModel then
            error("Failed to load weapon model for asset: " .. assetName)
        end
        
        -- Ensure the weapon has a Handle part
        local handle = weaponModel:FindFirstChild("Handle")
        if not handle then
            error("Weapon model missing Handle part")
        end
        
        return weaponModel
    end)

    if success and result then
        local assetValue: AssetTypes.AssetValue = { 
            AssetId = assetId,
            Instance = result,
        }
        assetCache[assetName] = assetValue
        return assetValue
    else
        warn("Failed to load asset", assetName, assetId, result)
        return nil
    end
end

local WeaponAssets = {} :: AssetTypes.AssetHandler

function WeaponAssets:GetHandlerName(): string
    return "Weapons"
end

function WeaponAssets:GetAllAssets(): { [string]: AssetTypes.AssetValue }
    -- Return cached assets without forcing load of all
    -- This maintains lazy loading principle
    return assetCache
end

function WeaponAssets:GetAsset(assetName: string): AssetTypes.AssetValue?
    return loadAsset(assetName)
end

-- Optional utility function (not part of the interface)
local function _PreloadAssets(assetNames: {string}): ()
    -- Optional: preload specific assets if needed
    for _, name in assetNames do
        loadAsset(name)
    end
end

return WeaponAssets