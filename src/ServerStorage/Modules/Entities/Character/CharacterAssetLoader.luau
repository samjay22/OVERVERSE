--!strict
-- CharacterAssetLoader - Handles loading and caching of character assets
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetHandlerModule = require(ReplicatedStorage.Modules.AssetHandlers)
local CharacterAssets = AssetHandlerModule.OnModuleLoaded("Characters")
local AnimationAssets = AssetHandlerModule.OnModuleLoaded("Animations")

local CharacterAssetLoader = {}
CharacterAssetLoader.__index = CharacterAssetLoader

export type ICharacterAssetLoader = {
	GetCharacterAsset: (self: ICharacterAssetLoader, assetKey: string?) -> Model?,
	GetAnimationAsset: (self: ICharacterAssetLoader, packName: string?) -> any?,
	PreloadAssets: (self: ICharacterAssetLoader, assetKeys: {string}) -> (),
}

function CharacterAssetLoader.new(): ICharacterAssetLoader
	local self = setmetatable({}, CharacterAssetLoader)
	
	-- High-performance LRU caches with size limits
	self._assetCache = {} :: {[string]: Model}
	self._assetCacheOrder = {} :: {string} -- LRU order tracking
	self._assetCacheSize = 0
	self._maxAssetCache = 50 -- Limit asset cache size
	
	self._animationCache = {} :: {[string]: {[string]: any}}
	self._animationCacheOrder = {} :: {string}
	self._animationCacheSize = 0 
	self._maxAnimationCache = 20 -- Limit animation pack cache
	
	return self
end

function CharacterAssetLoader:GetCharacterAsset(assetKey: string?): Model?
	local key = assetKey or "Default"
    
	-- Check cache first with LRU update
	local cached = self._assetCache[key]
	if cached then
		-- Move to end of LRU order (most recently used)
		self:_updateAssetLRU(key)
		return cached
	end
	
	-- Load from asset handler
	local handler: any = CharacterAssets
	if handler and handler.GetAsset then
		local val = handler.GetAsset(key)
		local inst = val and val.Instance
		if inst and inst:IsA("Model") then
			-- Cache with LRU eviction
			self:_cacheAsset(key, inst)
			return inst
		end
	end
	
	warn(`[CharacterAssetLoader] Character asset not found: {key}`)
	return nil
end

function CharacterAssetLoader:GetAnimationAsset(packName: string?): any?
	local key = packName or "Default"
	
	-- Check cache first with LRU update
	local cached = self._animationCache[key]
	if cached then
		self:_updateAnimationLRU(key)
		return cached
	end
	
	-- Load all animations for the pack using the PreloadPack method
	local handler: any = AnimationAssets
	if handler and handler.PreloadPack then
		-- PreloadPack loads all animations for the pack into the handler's cache
		handler.PreloadPack(key)
		
		-- Now get all assets and filter for this pack
		if handler.GetAllAssets then
			local allAssets = handler.GetAllAssets()
			local packAnimations = {}
			
			-- Filter assets that belong to this pack (format: "packName:animationName")
			for assetKey, assetValue in pairs(allAssets) do
				local packPart, animPart = string.match(assetKey, "([^:]+):([^:]+)")
				if packPart == key and animPart then
					packAnimations[animPart] = assetValue
				end
			end
			
			if next(packAnimations) then
				-- Cache with LRU eviction
				self:_cacheAnimation(key, packAnimations)
				return packAnimations
			end
		end
	end
	
	-- If the requested pack doesn't exist and it's not "Default", try "Default" as fallback
	if key ~= "Default" then
		warn(`Animation pack not found: {key}, trying Default fallback`)
		return self:GetAnimationAsset("Default")
	end
	
	warn(`Animation pack not found: {key}`)
	return nil
end

function CharacterAssetLoader:PreloadAssets(assetKeys: {string})
	-- Preload assets into cache
	for _, key in ipairs(assetKeys) do
		self:GetCharacterAsset(key)
	end
end

-- High-performance LRU cache management methods
function CharacterAssetLoader:_updateAssetLRU(key: string)
	-- Find and move key to end (most recently used)
	local order = self._assetCacheOrder
	for i = 1, #order do
		if order[i] == key then
			-- Fast removal and append
			table.remove(order, i)
			table.insert(order, key)
			return
		end
	end
end

function CharacterAssetLoader:_cacheAsset(key: string, asset: Model)
	-- Check if we need to evict
	if self._assetCacheSize >= self._maxAssetCache then
		local evictKey = table.remove(self._assetCacheOrder, 1) -- Remove oldest
		if evictKey then
			self._assetCache[evictKey] = nil
			self._assetCacheSize = self._assetCacheSize - 1
		end
	end
	
	-- Add new asset
	self._assetCache[key] = asset
	table.insert(self._assetCacheOrder, key)
	self._assetCacheSize = self._assetCacheSize + 1
end

function CharacterAssetLoader:_updateAnimationLRU(key: string)
	local order = self._animationCacheOrder
	for i = 1, #order do
		if order[i] == key then
			table.remove(order, i)
			table.insert(order, key)
			return
		end
	end
end

function CharacterAssetLoader:_cacheAnimation(key: string, animations: {[string]: any})
	-- Check if we need to evict
	if self._animationCacheSize >= self._maxAnimationCache then
		local evictKey = table.remove(self._animationCacheOrder, 1)
		if evictKey then
			self._animationCache[evictKey] = nil
			self._animationCacheSize = self._animationCacheSize - 1
		end
	end
	
	-- Add new animation pack
	self._animationCache[key] = animations
	table.insert(self._animationCacheOrder, key)
	self._animationCacheSize = self._animationCacheSize + 1
end

return CharacterAssetLoader
