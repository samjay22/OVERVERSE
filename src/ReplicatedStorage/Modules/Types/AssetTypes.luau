--!strict
export type AssetValue = {
    AssetId: string,
    Instance: Instance?, -- Optional, can be nil if not loaded
}

export type AssetHandler = {
    GetHandlerName: (self: AssetHandler) -> string,    
    GetAsset: (self: AssetHandler, assetName: string) -> AssetValue?,
    GetAllAssets: (self: AssetHandler) -> { [string]: AssetValue },
}

return 0