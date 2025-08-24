--!strict
local AssetTypes = require(game.ReplicatedStorage.Modules.Types.AssetTypes)

export type AssetHandlers = {
    OnModuleLoaded: (assetType: string) -> AssetTypes.AssetHandler?
}

local AssetHandlers: {[string]: AssetTypes.AssetHandler} = {}

for _, module in ipairs(script:GetChildren()) do
    if module:IsA("ModuleScript") then
        local handler = require(module) :: any
        if handler.GetHandlerName and handler.GetAllAssets and handler.GetAsset then
            local handlerName = handler:GetHandlerName()
            AssetHandlers[handlerName] = handler :: AssetTypes.AssetHandler
        else
            warn("Invalid asset handler module: " .. module.Name)
        end
    end
end

local AssetHandlerModule: AssetHandlers = {
    OnModuleLoaded = function(assetType: string): AssetTypes.AssetHandler?
        return AssetHandlers[assetType]
    end
}

return AssetHandlerModule