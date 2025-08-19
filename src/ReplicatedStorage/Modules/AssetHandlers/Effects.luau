--!strict
local InsertService = game:GetService("InsertService")

local AssetTypes = require(game.ReplicatedStorage.Modules.Types.AssetTypes)

local assetCache : { [string]: AssetTypes.AssetValue } = {}
local assetIdMap : {[string] : {[string] : number}} = {
    Rem = {
        M1 = 100848112721839,
        Aura = 83733500844066
    }
}

local function loadAsset(assetName: string): AssetTypes.AssetValue?
    if assetCache[assetName] then
        return assetCache[assetName]
    end

    -- Parse the assetName format "Character:AbilityName"
    local parts = assetName:split(":")
    if #parts ~= 2 then
        return nil
    end
    
    local charName = parts[1]
    local abilityName = parts[2]
    
    local charAssets = assetIdMap[charName]
    if not charAssets then
        return nil
    end
    
    local assetId = charAssets[abilityName]
    if not assetId then
        return nil
    end

    -- Lazy load the actual Roblox asset
    local success, result = pcall(function()
        local characterModel = InsertService:LoadAsset(assetId):GetChildren()[1] -- Assuming the asset is a single model
        if not characterModel then
            error("Failed to load character model for asset: " .. assetName)
        end
    
        return characterModel
    end)

    if success and result then
    local assetValue = {
            AssetId = tostring(assetId),
            Instance = result,
        }
        assetCache[assetName] = assetValue
        return assetValue
    else
        warn("Failed to load asset", assetName, assetId, result)
        return nil
    end
end

local CharacterAssets = {}

function CharacterAssets.GetHandlerName(): string
    return "Effects"
end

function CharacterAssets.GetAllAssets(): { [string]: AssetTypes.AssetValue }
    -- Return cached assets without forcing load of all
    -- This maintains lazy loading principle
    return assetCache
end

function CharacterAssets.GetAsset(assetName : string): AssetTypes.AssetValue?
    return loadAsset(assetName)
end

function CharacterAssets.PreloadAssets(assetNames: {string}): ()
    -- Optional: preload specific assets if needed
    for _, name in assetNames do
        loadAsset(name)
    end
end

for charName, effectsList in assetIdMap do
    for effectName, assetId in pairs(effectsList) do
       task.spawn(function()
    -- Load the asset using the assetId
            local success, result = pcall(function()
                local characterModel = InsertService:LoadAsset(assetId):GetChildren()[1]
                if not characterModel then
                    error("Failed to load effect model for: " .. charName .. ":" .. effectName)
                end
                return characterModel
            end)
    
            if success and result then
                local assetValue = {
                    AssetId = tostring(assetId),
                    Instance = result,
                }
                -- Store with the format "Character:AbilityName"
                assetCache[charName .. ":" .. effectName] = assetValue
                print("Loaded effect:", charName .. ":" .. effectName)
            else
                warn("Failed to preload effect:", charName .. ":" .. effectName, result)
            end
       end)
    end
end

return CharacterAssets