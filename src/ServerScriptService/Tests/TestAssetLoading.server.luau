--!strict
-- Simple asset loading test
print("🧪 Testing Asset Loading...")

local success, AssetLoader = pcall(function()
    return require(game.ServerStorage.Modules.Entities.Character.CharacterAssetLoader)
end)

if success then
    print("✅ CharacterAssetLoader loaded successfully!")
    
    local loader = AssetLoader.new()
    print("✅ AssetLoader instance created")
    
    -- Test asset loading
    local asset = loader:GetCharacterAsset("Default")
    if asset then
        print("✅ Default character asset loaded successfully!")
        print("Asset type:", typeof(asset))
        print("Asset name:", asset.Name)
    else
        print("❌ Failed to load default character asset")
    end
else
    warn("❌ CharacterAssetLoader failed to load:", AssetLoader)
end
