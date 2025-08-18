--!strict
local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")

local AssetTypes = require(game.ReplicatedStorage.Modules.Types.AssetTypes)

-- Animation packs keyed by pack name; each pack contains map of animationName -> assetId
type PackName = string
type Animation = string
type PackAnimationKey = string -- "PackName:Animation" combined key

local packs: {[PackName]: {[Animation]: string}} = {
    Rem = {
        Idle = "109703334185897",
        Walk = "77410537283170",
        Jump = "77410537283170",
        BackWalk = "85307657699318",
        Fall = "77410537283170",
        M1 = "77031697494140",
        Special = "131251175705402"
    },
}

-- Cache of loaded Animation instances: packName/clipName -> AssetValue
local cache: {[string]: AssetTypes.AssetValue} = {}

local function key(packName: PackName, animation: Animation): PackAnimationKey
    -- Guard against bad inputs to avoid "attempt to concatenate table with string"
    if type(packName) ~= "string" or type(animation) ~= "string" then
        error(`Animations.MakeKey expects (string, string), got ({typeof(packName)}, {typeof(animation)})`)
    end
    return packName .. ":" .. animation
end

local function loadClip(packName: PackName, animation: any): AssetTypes.AssetValue?
    -- Accept either a single animation (string) or a list/table of animation names
    if type(animation) ~= "string" then
        if type(animation) == "table" then
            -- Preload a list of names
            for _, n in ipairs(animation) do
                if type(n) == "string" then
                    loadClip(packName, n)
                else
                    warn("Animations: non-string in animation list for pack", packName, n)
                end
            end
        else
            warn("Animations: animation must be string or {string}, got", typeof(animation))
        end
        return nil
    end

    local k = key(packName, animation)
    local existing = cache[k]
    if existing then return existing end

    local pack = packs[packName]
    if not pack then
        warn("Animations: unknown pack", packName)
        return nil
    end
    local assetId = pack[animation]
    if not assetId then
        warn("Animations: unknown animation in pack", packName, animation)
        return nil
    end

    local ok, valueOrErr = pcall(function()
        local model = InsertService:LoadAsset(tonumber(assetId))
        if not model then error("LoadAsset returned nil for " .. tostring(assetId)) end
        local instance = model:GetChildren()[1]
        if not instance then error("No instance inside asset " .. tostring(assetId)) end

        -- Find an Animation inside a folder if needed
        local anim: Instance? = nil
        if instance:IsA("Animation") then
            anim = instance
        elseif instance:IsA("Folder") then
            anim = instance:FindFirstChildOfClass("Animation")
            if not anim then
                -- fallback to any first child if no Animation found
                anim = instance:GetChildren()[1]
            end
        else
            anim = instance
        end
        if not anim then error("No usable Animation found in asset " .. tostring(assetId)) end

        -- Clone the asset out of the container model so destroying the model doesn't destroy our instance
        local out = anim:Clone()
        model:Destroy()
        return out
    end)

    if not ok then
        warn("Failed to load animation", packName, animation, assetId, valueOrErr)
        return nil
    end

    local instance = valueOrErr :: Instance
    local value: AssetTypes.AssetValue = { AssetId = assetId, Instance = instance }
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

function AnimAssets.GetAsset(assetName: string): AssetTypes.AssetValue?
    local p, a = string.match(assetName, "([^:]+):([^:]+)")
    if p and a then
        return loadClip(p, a)
    end
    -- Search all packs for an animation named `assetName`
    for packName, pack in pairs(packs) do
        if pack[assetName] ~= nil then
            return loadClip(packName, assetName)
        end
    end
    warn("Animations.GetAsset: could not find animation named", assetName, "in any pack")
    return nil
end

function AnimAssets.PreloadPack(packName: PackName, names: {Animation}?)
    local pack = packs[packName]
    if not pack then
        warn("Animations.PreloadPack: unknown pack", packName)
        return
    end
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

function AnimAssets.DefinePack(packName: PackName, map: {[Animation]: string})
    packs[packName] = map
end

function AnimAssets.MakeKey(packName: PackName, animation: Animation): PackAnimationKey
    return key(packName, animation)
end

-- Auto-preload all assets on the server so everything is ready for consumers
function AnimAssets.PreloadAll()
    for packName, pack in pairs(packs) do
        for animName in pairs(pack) do
            task.spawn(loadClip, packName, animName)
        end
    end
end

-- Only auto-preload on the server (InsertService is server-only)
local didAutoPreload = false
if RunService:IsServer() and not didAutoPreload then
    didAutoPreload = true
    AnimAssets.PreloadAll()
end

return AnimAssets