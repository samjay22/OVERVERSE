--!nonstrict
local AssetTypes = require(game.ReplicatedStorage.Modules.Types.AssetTypes)

local AssetHandlers : {[string]: AssetTypes.AssetHandler} = {}

for _, module in ipairs(script:GetChildren()) do
    if module:IsA("ModuleScript") then
        local handler = require(module)
        if handler.GetHandlerName and handler.GetAllAssets and handler.GetAsset then
            AssetHandlers[handler.GetHandlerName()] = handler
        else
            warn("Invalid asset handler module: " .. module.Name)
        end
    end
end

return {
    OnModuleLoaded = function(assetType : string): AssetTypes.AssetHandler?
        return AssetHandlers[assetType]
    end
}