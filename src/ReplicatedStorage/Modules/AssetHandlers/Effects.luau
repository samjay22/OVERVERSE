--!strict
local InsertService = game:GetService("InsertService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local AssetTypes = require(game.ReplicatedStorage.Modules.Types.AssetTypes)

local assetCache : { [string]: AssetTypes.AssetValue } = {}
local assetIdMap : {[string] : {[string] : number}} = {
    Rem = {
        M1 = 100848112721839,
        Aura = 83733500844066,
        M2 = 104983325154104,
    }
}

-- Preloading optimization
local preloadInProgress = false

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

    -- Optimized loading with ContentProvider preload
    local success, result = pcall(function()
        -- Preload first for better performance
        ContentProvider:PreloadAsync({tostring(assetId)})
        
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

-- Auto-preload all effects on server startup for optimal performance
function CharacterAssets.PreloadAllEffects()
    if preloadInProgress then
        return -- Already preloading
    end
    
    preloadInProgress = true
    print("🚀 Starting optimized effects preload...")
    local startTime = tick()
    local totalEffects = 0
    
    -- Count total effects
    for _, effectsList in assetIdMap do
        for _ in pairs(effectsList) do
            totalEffects = totalEffects + 1
        end
    end
    
    local loadedCount = 0
    local batchSize = 4 -- Smaller batch size for effects due to larger file sizes
    
    for charName, effectsList in assetIdMap do
        local effectBatch = {}
        
        for effectName, assetId in pairs(effectsList) do
            table.insert(effectBatch, {
                charName = charName,
                effectName = effectName,
                assetId = assetId
            })
            
            -- Process batch when it reaches the desired size
            if #effectBatch >= batchSize then
                local batchPromises = {}
                
                for _, effectInfo in effectBatch do
                    table.insert(batchPromises, task.spawn(function()
                        local effectKey = effectInfo.charName .. ":" .. effectInfo.effectName
                        local success, result = pcall(function()
                            -- Preload using ContentProvider first
                            ContentProvider:PreloadAsync({tostring(effectInfo.assetId)})
                            
                            local characterModel = InsertService:LoadAsset(effectInfo.assetId):GetChildren()[1]
                            if not characterModel then
                                error("Failed to load effect model for: " .. effectKey)
                            end
                            return characterModel
                        end)
                
                        if success and result then
                            local assetValue = {
                                AssetId = tostring(effectInfo.assetId),
                                Instance = result,
                            }
                            assetCache[effectKey] = assetValue
                            loadedCount = loadedCount + 1
                            print(`📦 Loaded effect: ${effectKey} ({loadedCount}/{totalEffects})`)
                        else
                            warn("Failed to preload effect:", effectKey, result)
                        end
                    end))
                end
                
                -- Wait for batch to complete
                for _, promise in batchPromises do
                    while coroutine.status(promise) ~= "dead" do
                        task.wait()
                    end
                end
                
                effectBatch = {} -- Clear batch
                task.wait() -- Yield to prevent script timeout
            end
        end
        
        -- Process remaining effects in the batch
        if #effectBatch > 0 then
            local batchPromises = {}
            
            for _, effectInfo in effectBatch do
                table.insert(batchPromises, task.spawn(function()
                    local effectKey = effectInfo.charName .. ":" .. effectInfo.effectName
                    local success, result = pcall(function()
                        ContentProvider:PreloadAsync({tostring(effectInfo.assetId)})
                        
                        local characterModel = InsertService:LoadAsset(effectInfo.assetId):GetChildren()[1]
                        if not characterModel then
                            error("Failed to load effect model for: " .. effectKey)
                        end
                        return characterModel
                    end)
            
                    if success and result then
                        local assetValue = {
                            AssetId = tostring(effectInfo.assetId),
                            Instance = result,
                        }
                        assetCache[effectKey] = assetValue
                        loadedCount = loadedCount + 1
                        print(`📦 Loaded effect: ${effectKey} ({loadedCount}/{totalEffects})`)
                    else
                        warn("Failed to preload effect:", effectKey, result)
                    end
                end))
            end
            
            -- Wait for final batch to complete
            for _, promise in batchPromises do
                while coroutine.status(promise) ~= "dead" do
                    task.wait()
                end
            end
        end
    end
    
    local endTime = tick()
    local duration = endTime - startTime
    local charCount = 0
    for _ in pairs(assetIdMap) do
        charCount = charCount + 1
    end
    
    print(`✅ Effects preload completed in {math.round(duration * 100) / 100}s`)
    print(`📊 Loaded {loadedCount} effects from {charCount} characters`)
    preloadInProgress = false
end

-- Replace the old auto-preload section
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