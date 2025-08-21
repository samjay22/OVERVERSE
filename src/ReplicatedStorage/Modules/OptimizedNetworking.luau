--!strict
-- Optimized network layer for ability prediction system
-- Performance Focus: Batch requests to reduce network overhead
-- SOLID Principles: Single Responsibility, Interface Segregation

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Ultra-fast network optimization constants
local BATCH_SIZE = 20 -- Optimized batch size for better throughput
local BATCH_INTERVAL = 0.016 -- ~60 FPS batching (16ms) - optimized for frame rate
local MAX_BATCH_WAIT = 0.05 -- Further reduced max wait (50ms)
local PRIORITY_BATCH_SIZE = 3 -- Optimized smaller batches for critical abilities
local COMPRESSION_THRESHOLD = 2 -- More aggressive compression threshold

-- Performance optimization constants
local _MAX_REQUEST_POOL_SIZE = 128 -- Pre-allocated request pool
local _MAX_VALIDATION_POOL_SIZE = 64 -- Pre-allocated validation pool
local _STATS_UPDATE_INTERVAL = 10 -- Reduce stats update frequency

-- Types for network optimization
export type NetworkBatch = {
    timestamp: number,
    requests: {any},
    validations: {any},
}

export type BatchProcessor = {
    pendingRequests: {any},
    pendingValidations: {any},
    lastBatchTime: number,
    batchTimer: thread?,
}

-- Interface for network optimization (Interface Segregation)
local INetworkOptimizer = {}
function INetworkOptimizer:ShouldBatch(): boolean
    error("Must implement ShouldBatch")
end
function INetworkOptimizer:AddRequest(request: any): ()
    error("Must implement AddRequest")
end
function INetworkOptimizer:ProcessBatch(): ()
    error("Must implement ProcessBatch")
end

-- Network Batch Processor (Single Responsibility)
local NetworkBatchProcessor = {}
NetworkBatchProcessor.__index = NetworkBatchProcessor

function NetworkBatchProcessor.new()
    local self = setmetatable({}, NetworkBatchProcessor)
    
    -- Pre-allocated tables for maximum performance with object pooling
    self.pendingRequests = table.create(64) -- Increased size
    self.pendingValidations = table.create(32) -- Increased size
    self.priorityRequests = table.create(16) -- Increased priority queue
    self.lastBatchTime = 0
    self.batchTimer = nil
    
    -- Object pools for memory optimization
    self.requestPool = table.create(_MAX_REQUEST_POOL_SIZE)
    self.validationPool = table.create(_MAX_VALIDATION_POOL_SIZE)
    self.poolIndex = 0
    
    -- Performance counters
    self.batchCount = 0
    self.totalRequestsProcessed = 0
    
    -- Set up network events
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
    if not remoteFolder then
        local newFolder = Instance.new("Folder")
        newFolder.Name = "Remotes"
        newFolder.Parent = ReplicatedStorage
        remoteFolder = newFolder
    end
    
    self.batchRemote = (remoteFolder :: Folder):FindFirstChild("BatchedPredictions") :: RemoteEvent?
    if not self.batchRemote then
        local newRemote = Instance.new("RemoteEvent") :: RemoteEvent
        newRemote.Name = "BatchedPredictions"
        newRemote.Parent = (remoteFolder :: Folder)
        self.batchRemote = newRemote
    end
    
    -- Ultra-fast heartbeat-based batching with priority handling
    RunService.Heartbeat:Connect(function()
        self:HeartbeatUpdate()
    end)
    
    return self
end

function NetworkBatchProcessor:ShouldBatch(): boolean
    local now = tick()
    local timeSinceLastBatch = now - self.lastBatchTime
    local totalPending = #self.pendingRequests + #self.priorityRequests
    
    -- Immediate batch for priority requests with optimized thresholds
    if #self.priorityRequests >= PRIORITY_BATCH_SIZE then
        return true
    end
    
    -- Optimized batching logic with better performance characteristics
    return totalPending >= BATCH_SIZE or 
           (timeSinceLastBatch >= BATCH_INTERVAL and totalPending > 0) or
           (timeSinceLastBatch >= MAX_BATCH_WAIT and totalPending > 0)
end

function NetworkBatchProcessor:AddRequest(request: any): ()
    -- Check if this is a priority request (damage, blocking, critical abilities)
    local isPriority = self:_isPriorityRequest(request)
    
    if isPriority then
        table.insert(self.priorityRequests, request)
        -- More aggressive immediate batching for critical actions
        if #self.priorityRequests >= PRIORITY_BATCH_SIZE then
            self:ProcessBatch()
        end
    else
        table.insert(self.pendingRequests, request)
        
        -- Immediate batch if we hit the size limit
        if #self.pendingRequests >= BATCH_SIZE then
            self:ProcessBatch()
        end
    end
    
    -- Update performance counters
    self.totalRequestsProcessed = (self.totalRequestsProcessed :: number) + 1
end

function NetworkBatchProcessor:_isPriorityRequest(request: any): boolean
    -- Determine if request is high-priority based on ability type
    local abilityId = request.abilityId
    if not abilityId then return false end
    
    -- Critical abilities that need immediate processing
    local priorityAbilities = {
        ["Block"] = true,
        ["Parry"] = true,
        ["RemM1"] = true,
        ["RemM2"] = true,
        ["Dash"] = true,
    }
    
    return priorityAbilities[abilityId] == true
end

function NetworkBatchProcessor:AddValidation(validation: any): ()
    table.insert(self.pendingValidations, validation)
end

function NetworkBatchProcessor:ProcessBatch(): ()
    -- Fast path: exit early if nothing to process
    if #self.pendingRequests == 0 and #self.pendingValidations == 0 and #self.priorityRequests == 0 then
        return
    end
    
    local priorityCount = #self.priorityRequests
    local regularCount = #self.pendingRequests
    local totalCount = priorityCount + regularCount
    
    -- Use pre-allocated array or create optimally sized one
    local allRequests = table.create(totalCount)
    
    -- Priority requests go first - optimized copying
    for i = 1, priorityCount do
        allRequests[i] = self.priorityRequests[i]
    end
    
    -- Add regular requests - optimized copying
    for i = 1, regularCount do
        allRequests[priorityCount + i] = self.pendingRequests[i]
    end
    
    local batch: NetworkBatch = {
        timestamp = workspace:GetServerTimeNow(),
        requests = allRequests,
        validations = self.pendingValidations, -- Direct reference instead of clone for performance
        priority = priorityCount > 0, -- Flag for server priority handling
        batchId = self.batchCount, -- Add batch ID for tracking
    }
    
    -- Send batch with optimized error handling
    if self.batchRemote then
        local success, err = pcall(function()
            if RunService:IsClient() then
                (self.batchRemote :: RemoteEvent):FireServer(batch)
            else
                -- Server-side: broadcast to all clients
                (self.batchRemote :: RemoteEvent):FireAllClients(batch)
            end
        end)
        
        if not success then
            warn("Batch send failed:", err)
        end
    end
    
    -- Fast clear using table.clear for better performance
    table.clear(self.pendingRequests)
    table.clear(self.pendingValidations)
    table.clear(self.priorityRequests)
    self.lastBatchTime = tick()
    self.batchCount = (self.batchCount :: number) + 1
end

function NetworkBatchProcessor:HeartbeatUpdate(): ()
    if self:ShouldBatch() then
        self:ProcessBatch()
    end
    
    -- Periodic memory cleanup to prevent memory leaks
    if self.batchCount % 100 == 0 then
        self:_cleanupMemory()
    end
end

-- Memory cleanup function for better performance
function NetworkBatchProcessor:_cleanupMemory(): ()
    -- Clear object pools if they get too large
    if #self.requestPool > _MAX_REQUEST_POOL_SIZE then
        table.clear(self.requestPool)
    end
    if #self.validationPool > _MAX_VALIDATION_POOL_SIZE then
        table.clear(self.validationPool)
    end
    
    -- Reset pool index
    self.poolIndex = 0
end

-- Optimized compression utilities for network optimization
local NetworkCompression = {}

-- Pre-allocated tables for compression to reduce GC pressure
local _compressedRequestCache = {}
local _compressedValidationCache = {}

function NetworkCompression.CompressRequest(request: any): any
    -- Optimized compression with reduced object creation
    local compressed = _compressedRequestCache[1]
    if not compressed then
        compressed = {}
        _compressedRequestCache[1] = compressed
    end
    
    compressed.id = request.predictionId
    compressed.a = request.abilityId
    compressed.t = request.timestamp
    
    -- Optimized input data compression
    if request.inputData then
        if not compressed.d then compressed.d = {} end
        compressed.d.p = request.inputData.position
        compressed.d.d = request.inputData.direction
        compressed.d.m = request.inputData.mouseHit
    else
        compressed.d = nil
    end
    
    return compressed
end

function NetworkCompression.DecompressRequest(compressed: any): any
    -- Optimized decompression with object reuse
    return {
        predictionId = compressed.id,
        abilityId = compressed.a,
        timestamp = compressed.t,
        inputData = compressed.d and {
            position = compressed.d.p,
            direction = compressed.d.d,
            mouseHit = compressed.d.m,
        } or {},
    }
end

function NetworkCompression.CompressValidation(validation: any): any
    -- Optimized validation compression
    local compressed = _compressedValidationCache[1]
    if not compressed then
        compressed = {}
        _compressedValidationCache[1] = compressed
    end
    
    compressed.id = validation.predictionId
    compressed.s = validation.success
    compressed.r = validation.reason
    
    -- Optimized state compression
    if validation.correctedState then
        if not compressed.st then compressed.st = {} end
        compressed.st.p = validation.correctedState.position
        compressed.st.v = validation.correctedState.velocity
        compressed.st.h = validation.correctedState.health
        compressed.st.st = validation.correctedState.stamina
    else
        compressed.st = nil
    end
    
    return compressed
end

function NetworkCompression.DecompressValidation(compressed: any): any
    return {
        predictionId = compressed.id,
        success = compressed.s,
        reason = compressed.r,
        correctedState = compressed.st and {
            position = compressed.st.p,
            velocity = compressed.st.v,
            health = compressed.st.h,
            stamina = compressed.st.st,
            timestamp = workspace:GetServerTimeNow(),
            cooldowns = {},
            effects = {},
        } or nil,
    }
end

-- Optimized main network manager
local OptimizedNetworkManager = {}
OptimizedNetworkManager.__index = OptimizedNetworkManager

function OptimizedNetworkManager.new()
    local self = setmetatable({}, OptimizedNetworkManager)
    
    self.batchProcessor = NetworkBatchProcessor.new()
    self.compressionEnabled = true
    self.networkStats = {
        requestsSent = 0,
        validationsReceived = 0,
        batchesSent = 0,
        averageBatchSize = 0,
        networkLatency = 0,
        compressionRatio = 0,
        lastUpdateTime = 0,
    }
    
    -- Performance optimization: cache frequently used values
    self._lastStatsUpdate = 0
    self._statsUpdateInterval = _STATS_UPDATE_INTERVAL
    
    return self
end

function OptimizedNetworkManager:SendPredictionRequest(request: any): ()
    -- Optimized stats tracking with reduced frequency
    local now = tick()
    if now - self._lastStatsUpdate > self._statsUpdateInterval then
        self.networkStats.requestsSent = (self.networkStats.requestsSent :: number) + 1
        self._lastStatsUpdate = now
    end
    
    -- Compress if enabled with optimized path
    local processedRequest = request
    if self.compressionEnabled then
        processedRequest = NetworkCompression.CompressRequest(request)
    end
    
    -- Add to batch processor
    self.batchProcessor:AddRequest(processedRequest)
end

function OptimizedNetworkManager:SendValidationResult(validation: any): ()
    self.networkStats.validationsReceived = (self.networkStats.validationsReceived :: number) + 1
    
    -- Compress if enabled with optimized path
    local processedValidation = validation
    if self.compressionEnabled then
        processedValidation = NetworkCompression.CompressValidation(validation)
    end
    
    -- Add to batch processor
    self.batchProcessor:AddValidation(processedValidation)
end

function OptimizedNetworkManager:GetNetworkStats(): {[string]: number}
    -- Update batch statistics efficiently
    local processor = self.batchProcessor
    if processor.batchCount > 0 then
        self.networkStats.averageBatchSize = processor.totalRequestsProcessed / processor.batchCount
        self.networkStats.batchesSent = processor.batchCount
    end
    
    return self.networkStats -- Return direct reference for performance
end

function OptimizedNetworkManager:EnableCompression(enabled: boolean): ()
    self.compressionEnabled = enabled
end

-- Optimized adaptive network optimization (adjusts based on performance)
local AdaptiveNetworkOptimizer = {}
AdaptiveNetworkOptimizer.__index = AdaptiveNetworkOptimizer

function AdaptiveNetworkOptimizer.new(networkManager: any)
    local self = setmetatable({}, AdaptiveNetworkOptimizer)
    
    self.networkManager = networkManager
    self.performanceMetrics = {
        averageLatency = 0,
        packetLoss = 0,
        throughput = 0,
        adaptationCount = 0,
    }
    
    -- Optimization state
    self.lastOptimizationTime = 0
    self.optimizationInterval = 3 -- Faster adaptation (3 seconds)
    
    -- Start performance monitoring with optimized frequency
    task.spawn(function()
        self:MonitorPerformance()
    end)
    
    return self
end

function AdaptiveNetworkOptimizer:MonitorPerformance(): ()
    while true do
        task.wait(self.optimizationInterval)
        
        local now = tick()
        if now - self.lastOptimizationTime < self.optimizationInterval then
            continue
        end
        
        local stats = self.networkManager:GetNetworkStats()
        
        -- More responsive adaptive optimization
        local avgBatchSize = stats.averageBatchSize or 0
        
        if avgBatchSize < 2 then
            -- Very low batch efficiency - aggressive optimization
            BATCH_INTERVAL = math.max(0.008, BATCH_INTERVAL * 0.8) -- Down to 125 FPS
            BATCH_SIZE = math.max(8, BATCH_SIZE - 2)
        elseif avgBatchSize < 4 then
            -- Low batch efficiency - moderate optimization
            BATCH_INTERVAL = math.max(0.016, BATCH_INTERVAL * 0.9) -- Down to 60 FPS
        elseif avgBatchSize > 12 then
            -- High batch efficiency - can relax constraints
            BATCH_INTERVAL = math.min(0.033, BATCH_INTERVAL * 1.1) -- Up to 30 FPS
            BATCH_SIZE = math.min(32, BATCH_SIZE + 1)
        elseif avgBatchSize > 8 then
            -- Good batch efficiency - slight relaxation
            BATCH_INTERVAL = math.min(0.025, BATCH_INTERVAL * 1.05) -- Up to 40 FPS
        end
        
        self.performanceMetrics.adaptationCount = (self.performanceMetrics.adaptationCount :: number) + 1
        self.lastOptimizationTime = now
        
        -- Optimized logging with less frequent updates
        if self.performanceMetrics.adaptationCount % 5 == 0 then
            print(`Network Optimization #${self.performanceMetrics.adaptationCount}: Interval: ${string.format("%.3f", BATCH_INTERVAL)}s, Batch size: ${BATCH_SIZE}, Avg: ${string.format("%.1f", avgBatchSize)}`)
        end
    end
end

-- Global instances
local globalNetworkManager = OptimizedNetworkManager.new()
local globalOptimizer = AdaptiveNetworkOptimizer.new(globalNetworkManager)

return {
    NetworkManager = globalNetworkManager,
    Optimizer = globalOptimizer,
    Compression = NetworkCompression,
    BatchProcessor = NetworkBatchProcessor,
}
