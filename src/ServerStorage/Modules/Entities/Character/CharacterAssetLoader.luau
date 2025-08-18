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
	
	-- Asset cache for frequently used assets
	self._assetCache = {} :: {[string]: Model}
	self._animationCache = {} :: {[string]: {[string]: any}} -- packName -> {animationName -> AssetValue}
	
	return self
end

function CharacterAssetLoader:GetCharacterAsset(assetKey: string?): Model?
	local key = assetKey or "Default"
    
	-- Check cache first
	if self._assetCache[key] then
		return self._assetCache[key]
	end
	
	-- Load from asset handler
	local handler: any = CharacterAssets
	if handler and handler.GetAsset then
		local val = handler.GetAsset(key)
		local inst = val and val.Instance
		if inst and inst:IsA("Model") then
			-- Cache the asset
			self._assetCache[key] = inst
			return inst
		end
	end
	
	warn(`[CharacterAssetLoader] Character asset not found: {key}`)
	return nil
end

function CharacterAssetLoader:GetAnimationAsset(packName: string?): any?
	local key = packName or "Default"
	
	-- Check cache first
	if self._animationCache[key] then
		return self._animationCache[key]
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
				-- Cache the animation pack
				self._animationCache[key] = packAnimations
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

return CharacterAssetLoader
