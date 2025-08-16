--!strict
local InsertService = game:GetService("InsertService")

local AssetTypes = require(game.ReplicatedStorage.Modules.Types.AssetTypes)

-- Animation packs keyed by pack name; each pack contains map of clipName -> assetId
type PackName = string
type ClipName = string

local packs: {[PackName]: {[ClipName]: string}} = {
    Default = {
        Idle = "109703334185897",
        Walk = "77410537283170",
    },
}

-- Cache of loaded Animation instances: packName/clipName -> AssetValue
local cache: {[string]: AssetTypes.AssetValue} = {}

local function key(packName: PackName, clip: ClipName): string
    return packName .. ":" .. clip
end

local function loadClip(packName: PackName, clip: ClipName): AssetTypes.AssetValue?
    local k = key(packName, clip)
    local existing = cache[k]
    if existing then return existing end

    local pack = packs[packName]
    if not pack then return nil end
    local assetId = pack[clip]
    if not assetId then return nil end

    local ok, result = pcall(function()
        local model = InsertService:LoadAsset(tonumber(assetId))
        local instance = model and model:GetChildren()[1]
        if not instance then error("No animation instance in asset " .. tostring(assetId)) end
        if instance:IsA("Animation") then
            -- ok
        elseif instance:IsA("Folder") then
            -- find a child Animation named like clip
            local child = instance:FindFirstChildOfClass("Animation")
            instance = child or instance
        end
        return instance
    end)
    if not ok or not result then
        warn("Failed to load animation clip", packName, clip, assetId, result)
        return nil
    end
    local value: AssetTypes.AssetValue = { AssetId = assetId, Instance = result }
    cache[k] = value
    return value
end

local AnimAssets = {}

function AnimAssets.GetHandlerName(): string
    return "Animations"
end

function AnimAssets.GetAllAssets(): { [string]: AssetTypes.AssetValue }
    return table.clone(cache)
end

function AnimAssets.GetClip(packName: PackName, clip: ClipName): AssetTypes.AssetValue?
    return loadClip(packName, clip)
end

function AnimAssets.GetAsset(assetName: string): AssetTypes.AssetValue?
    -- Back-compat: allow direct access by "Pack:Clip" or single clip in Default
    local p, c = string.match(assetName, "([^:]+):([^:]+)")
    if p and c then
        return loadClip(p, c)
    end
    return loadClip("Default", assetName)
end

function AnimAssets.PreloadPack(packName: PackName, names: {ClipName}?)
    local pack = packs[packName]
    if not pack then return end
    if names then
        for _, n in ipairs(names) do
            loadClip(packName, n)
        end
    else
        for n in pairs(pack) do
            loadClip(packName, n)
        end
    end
end

function AnimAssets.DefinePack(packName: PackName, map: {[ClipName]: string})
    packs[packName] = map
end

return AnimAssets