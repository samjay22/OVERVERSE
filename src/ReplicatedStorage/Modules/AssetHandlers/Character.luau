--!nonstrict
local InsertService = game:GetService("InsertService")

local AssetTypes = require(game.ReplicatedStorage.Modules.Types.AssetTypes)

local assetCache : { [string]: AssetTypes.AssetValue } = {}
local assetIdMap = {
    Default = "124643087679097",
}

local function wrapper(characterModel, robloxAnimationScript)
    return setmetatable({
                Clone = function(self)
                    local clone : Instance = characterModel:Clone()
                    clone.AncestryChanged:Connect(function(_, parent)
                        if parent == game.Workspace then
                            --need to force script load on client
                            game.ReplicatedStorage.Remotes.CoreEvent:FireClient(game.Players:FindFirstChild(clone.Name), "StartBaseAnimations")
                        end
                    end)
                    return clone
                end,

            }, {__index = characterModel})
end

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
        local characterModel = InsertService:LoadAsset(tonumber(assetId)):GetChildren()[1] -- Assuming the asset is a single model
        if not characterModel then
            error("Failed to load character model for asset: " .. assetName)
        end
        
        -- Ensure the character has a Humanoid
        local humanoid = characterModel:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            error("Character model missing Humanoid")
        end
        
        if characterModel:FindFirstChild("Animate") then
            characterModel.Animate:Destroy()
        end

    
        return wrapper(characterModel)
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

local CharacterAssets = {}

function CharacterAssets.GetHandlerName(): string
    return "Characters"
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

return CharacterAssets