--!strict
--[[
    AssetPreloader - Optimized batch asset loading system
    
    Features:
    - Batch loading of multiple assets in parallel
    - Priority-based loading (critical assets first)
    - ContentProvider integration for better performance
    - Progress tracking and callbacks
    - Error handling and retry logic
    
    @author: GitHub Copilot (Optimization)
    @version: 2.0.0
]]

local ContentProvider = game:GetService("ContentProvider")
local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")

type AssetInfo = {
    id: string | number,
    priority: number, -- 1 = highest, 3 = lowest
    retryCount: number?,
    category: string, -- "animations", "effects", "characters", etc.
}

type LoadResult = {
    success: boolean,
    asset: Instance?,
    error: string?,
    assetId: string | number,
}

type ProgressCallback = (loaded: number, total: number, category: string?) -> ()
type CompletionCallback = (results: {[string]: LoadResult}) -> ()

local AssetPreloader = {}
AssetPreloader.__index = AssetPreloader

export type AssetPreloader = {
    queueAsset: (self: AssetPreloader, assetId: string | number, priority: number?, category: string?) -> (),
    queueAssets: (self: AssetPreloader, assets: {{id: string | number, priority: number?, category: string?}}) -> (),
    startPreloading: (self: AssetPreloader, progressCallback: ProgressCallback?, completionCallback: CompletionCallback?) -> (),
    getAsset: (self: AssetPreloader, assetId: string | number) -> Instance?,
    getAllAssets: (self: AssetPreloader) -> {[string]: LoadResult},
    stop: (self: AssetPreloader) -> (),
    clear: (self: AssetPreloader) -> (),
    
    _loadQueue: {AssetInfo},
    _loadedAssets: {[string]: LoadResult},
    _isLoading: boolean,
    _totalAssets: number,
    _loadedCount: number,
}

-- Configuration
local BATCH_SIZE = 8 -- Load assets in batches of 8
local MAX_RETRIES = 3
local RETRY_DELAY = 1 -- seconds
local HEARTBEAT_YIELD_INTERVAL = 50 -- Yield every N assets to prevent timeouts

function AssetPreloader.new(): AssetPreloader
    local self: AssetPreloader = setmetatable({} :: any, AssetPreloader) :: any
    
    self._loadQueue = {} :: {AssetInfo}
    self._loadedAssets = {} :: {[string]: LoadResult}
    self._isLoading = false
    self._totalAssets = 0
    self._loadedCount = 0
    
    return self
end

--[[
    Adds an asset to the preload queue
    
    @param assetId - The asset ID to load
    @param priority - Loading priority (1=highest, 3=lowest)
    @param category - Asset category for organization
]]
function AssetPreloader:queueAsset(assetId: string | number, priority: number?, category: string?)
    priority = priority or 2
    category = category or "general"
    
    local assetInfo: AssetInfo = {
        id = assetId,
        priority = priority :: number,
        retryCount = 0,
        category = category :: string,
    }
    
    table.insert(self._loadQueue, assetInfo)
    self._totalAssets = self._totalAssets + 1
end

--[[
    Queues multiple assets at once
    
    @param assets - Array of asset information
]]
function AssetPreloader:queueAssets(assets: {{id: string | number, priority: number?, category: string?}})
    for _, asset in assets do
        self:queueAsset(asset.id, asset.priority, asset.category)
    end
end

--[[
    Starts the preloading process with optional callbacks
    
    @param progressCallback - Called periodically with progress updates
    @param completionCallback - Called when all assets are loaded
]]
function AssetPreloader:startPreloading(progressCallback: ProgressCallback?, completionCallback: CompletionCallback?)
    if self._isLoading then
        warn("AssetPreloader: Already loading assets")
        return
    end
    
    self._isLoading = true
    self._loadedCount = 0
    
    -- Sort queue by priority (lower number = higher priority)
    table.sort(self._loadQueue, function(a: AssetInfo, b: AssetInfo)
        return a.priority < b.priority
    end)
    
    print(`🚀 AssetPreloader: Starting batch preload of {#self._loadQueue} assets`)
    
    task.spawn(function()
        self:_batchLoadAssets(progressCallback, completionCallback)
    end)
end

--[[
    Internal batch loading implementation
]]
function AssetPreloader:_batchLoadAssets(progressCallback: ProgressCallback?, completionCallback: CompletionCallback?)
    local startTime = tick()
    local assetQueue = table.clone(self._loadQueue)
    local batchResults = {}
    
    while #assetQueue > 0 and self._isLoading do
        -- Create batch
        local batch = {}
        local batchSize = math.min(BATCH_SIZE, #assetQueue)
        
        for i = 1, batchSize do
            table.insert(batch, table.remove(assetQueue, 1))
        end
        
        -- Load batch in parallel
        local batchPromises = {}
        for _, assetInfo in batch do
            table.insert(batchPromises, task.spawn(function()
                return self:_loadSingleAsset(assetInfo)
            end))
        end
        
        -- Wait for batch completion
        for i, promise in batchPromises do
            local result = self:_waitForTask(promise)
            local batchItem = batch[i]
            if batchItem then
                local assetId = tostring(batchItem.id)
                
                batchResults[assetId] = result
                self._loadedAssets[assetId] = result
                self._loadedCount = self._loadedCount + 1
                
                -- Progress callback
                if progressCallback then
                    progressCallback(self._loadedCount, self._totalAssets, batchItem.category)
                end
            end
        end
        
        -- Yield periodically to prevent script timeout
        if self._loadedCount % HEARTBEAT_YIELD_INTERVAL == 0 then
            RunService.Heartbeat:Wait()
        end
        
        print(`📦 AssetPreloader: Loaded batch ({self._loadedCount}/{self._totalAssets})`)
    end
    
    local endTime = tick()
    local duration = endTime - startTime
    
    print(`✅ AssetPreloader: Completed in {math.round(duration * 100) / 100}s`)
    print(`📊 Success rate: {self:_calculateSuccessRate()}%`)
    
    self._isLoading = false
    
    if completionCallback then
        completionCallback(batchResults)
    end
end

--[[
    Loads a single asset with retry logic
]]
function AssetPreloader:_loadSingleAsset(assetInfo: AssetInfo): LoadResult
    local assetId = assetInfo.id
    local attempts = 0
    
    repeat
        attempts += 1
        
        -- Try ContentProvider first (faster for preloading)
        local success, result = pcall(function()
            local assets = {tostring(assetId)}
            ContentProvider:PreloadAsync(assets)
            
            -- Then load the actual asset
            local assetNumber = tonumber(assetId)
            if not assetNumber then
                error("Invalid asset ID: " .. tostring(assetId))
            end
            return InsertService:LoadAsset(assetNumber)
        end)
        
        if success and result then
            local instance = result:GetChildren()[1]
            if instance then
                -- Clean up the container model
                local clonedInstance = instance:Clone()
                result:Destroy()
                
                return {
                    success = true,
                    asset = clonedInstance,
                    error = nil,
                    assetId = assetId,
                }
            end
        end
        
        -- Retry logic
        if attempts < MAX_RETRIES then
            task.wait(RETRY_DELAY * attempts) -- Exponential backoff
            assetInfo.retryCount = (assetInfo.retryCount or 0) + 1
        end
        
    until attempts >= MAX_RETRIES
    
    return {
        success = false,
        asset = nil,
        error = `Failed to load asset {assetId} after {MAX_RETRIES} attempts`,
        assetId = assetId,
    }
end

--[[
    Helper to wait for a task completion
]]
function AssetPreloader:_waitForTask(taskThread): LoadResult
    while coroutine.status(taskThread) ~= "dead" do
        task.wait()
    end
    
    -- Get the result from the coroutine
    local success, result = coroutine.resume(taskThread)
    if success and typeof(result) == "table" then
        return result :: LoadResult
    else
        return {
            success = false,
            asset = nil,
            error = tostring(result) or "Unknown error",
            assetId = "unknown",
        }
    end
end

--[[
    Calculates success rate of loaded assets
]]
function AssetPreloader:_calculateSuccessRate(): number
    if self._loadedCount == 0 then return 0 end
    
    local successCount = 0
    for _, result in self._loadedAssets do
        if result.success then
            successCount += 1
        end
    end
    
    return math.floor((successCount / self._loadedCount) * 100)
end

--[[
    Gets a loaded asset by ID
]]
function AssetPreloader:getAsset(assetId: string | number): Instance?
    local result = self._loadedAssets[tostring(assetId)]
    return result and result.asset
end

--[[
    Gets all loaded assets
]]
function AssetPreloader:getAllAssets(): {[string]: LoadResult}
    return table.clone(self._loadedAssets)
end

--[[
    Stops the preloading process
]]
function AssetPreloader:stop()
    self._isLoading = false
end

--[[
    Clears all queued and loaded assets
]]
function AssetPreloader:clear()
    self:stop()
    self._loadQueue = {}
    self._loadedAssets = {}
    self._totalAssets = 0
    self._loadedCount = 0
end

return AssetPreloader
