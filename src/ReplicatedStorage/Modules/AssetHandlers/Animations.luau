--!nonstrict
local InsertService = game:GetService("InsertService")

local AssetTypes = require(game.ReplicatedStorage.Modules.Types.AssetTypes)

local assetCache : { [string]: AssetTypes.AssetValue } = {}
local assetIdMap = {
    RemIdle = "109703334185897",
    RemWalk = "77410537283170",

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
        local animationModel = InsertService:LoadAsset(tonumber(assetId)):GetChildren()[1] -- Assuming the asset is a single model
        if not animationModel then
            error("Failed to load animation model for asset: " .. assetName)
        end
    
        return animationModel
    end)

    if success and result then
        local assetValue = { 
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

local WeaponAssets = {}

function WeaponAssets.GetHandlerName(): string
    return "Animations"
end

function WeaponAssets.GetAllAssets(): { [string]: AssetTypes.AssetValue }
    -- Return cached assets without forcing load of all
    -- This maintains lazy loading principle
    return assetCache
end

function WeaponAssets.GetAsset(assetName : string): AssetTypes.AssetValue?
    return loadAsset(assetName)
end

function WeaponAssets.PreloadAssets(assetNames: {string}): ()
    -- Optional: preload specific assets if needed
    for _, name in assetNames do
        loadAsset(name)
    end
end

return WeaponAssets