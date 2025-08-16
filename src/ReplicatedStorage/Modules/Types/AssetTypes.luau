--!nonstrict
export type AssetValue = {
    AssetId : string,
    Instance : Instance? -- Optional, can be nil if not loaded
}

export type AssetHandler = {
    GetHandlerName : () -> string,    
    GetAsset : (assetName: string) -> AssetValue?,
    GetAllAssets : () -> { [string]: AssetValue },
}

return 0