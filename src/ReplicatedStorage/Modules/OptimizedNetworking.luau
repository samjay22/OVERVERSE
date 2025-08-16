--!strict
-- Optimized network layer for ability prediction system
-- Performance Focus: Batch requests to reduce network overhead
-- SOLID Principles: Single Responsibility, Interface Segregation

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Network optimization constants
local BATCH_SIZE = 10 -- Maximum requests per batch
local BATCH_INTERVAL = 0.033 -- ~30 FPS batching (33ms)
local MAX_BATCH_WAIT = 0.1 -- Maximum time to wait for batch (100ms)

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
    
    self.pendingRequests = {}
    self.pendingValidations = {}
    self.lastBatchTime = 0
    self.batchTimer = nil
    
    -- Set up network events
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remoteFolder then
        remoteFolder = Instance.new("Folder")
        remoteFolder.Name = "Remotes"
        remoteFolder.Parent = ReplicatedStorage
    end
    
    self.batchRemote = remoteFolder:FindFirstChild("BatchedPredictions") :: RemoteEvent?
    if not self.batchRemote then
        local newRemote = Instance.new("RemoteEvent") :: RemoteEvent
        newRemote.Name = "BatchedPredictions"
        newRemote.Parent = remoteFolder
        self.batchRemote = newRemote
    end
    
    -- Set up heartbeat-based batching for consistent performance
    RunService.Heartbeat:Connect(function()
        self:HeartbeatUpdate()
    end)
    
    return self
end

function NetworkBatchProcessor:ShouldBatch(): boolean
    local now = tick()
    local timeSinceLastBatch = now - self.lastBatchTime
    
    -- Batch if we have enough requests or enough time has passed
    return #self.pendingRequests >= BATCH_SIZE or 
           timeSinceLastBatch >= MAX_BATCH_WAIT and #self.pendingRequests > 0
end

function NetworkBatchProcessor:AddRequest(request: any): ()
    table.insert(self.pendingRequests, request)
    
    -- Immediate batch if we hit the size limit
    if #self.pendingRequests >= BATCH_SIZE then
        self:ProcessBatch()
    end
end

function NetworkBatchProcessor:AddValidation(validation: any): ()
    table.insert(self.pendingValidations, validation)
end

function NetworkBatchProcessor:ProcessBatch(): ()
    if #self.pendingRequests == 0 and #self.pendingValidations == 0 then
        return
    end
    
    local batch: NetworkBatch = {
        timestamp = workspace:GetServerTimeNow(),
        requests = table.clone(self.pendingRequests),
        validations = table.clone(self.pendingValidations),
    }
    
    -- Send batch
    if self.batchRemote then
        if RunService:IsClient() then
            self.batchRemote:FireServer(batch)
        else
            -- Server-side: broadcast to all clients
            self.batchRemote:FireAllClients(batch)
        end
    end
    
    -- Clear pending items
    table.clear(self.pendingRequests)
    table.clear(self.pendingValidations)
    self.lastBatchTime = tick()
end

function NetworkBatchProcessor:HeartbeatUpdate(): ()
    if self:ShouldBatch() then
        self:ProcessBatch()
    end
end

-- Compression utilities for network optimization
local NetworkCompression = {}

function NetworkCompression.CompressRequest(request: any): any
    -- Simple compression by removing redundant data
    return {
        id = request.predictionId,
        a = request.abilityId,
        t = request.timestamp,
        d = request.inputData and {
            p = request.inputData.position,
            d = request.inputData.direction,
            m = request.inputData.mouseHit,
        } or nil,
    }
end

function NetworkCompression.DecompressRequest(compressed: any): any
    -- Decompress the request
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
    return {
        id = validation.predictionId,
        s = validation.success,
        r = validation.reason,
        st = validation.correctedState and {
            p = validation.correctedState.position,
            v = validation.correctedState.velocity,
            h = validation.correctedState.health,
            st = validation.correctedState.stamina,
        } or nil,
    }
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

-- Main optimized network manager
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
    }
    
    return self
end

function OptimizedNetworkManager:SendPredictionRequest(request: any): ()
    self.networkStats.requestsSent = (self.networkStats.requestsSent :: number) + 1
    
    -- Compress if enabled
    local processedRequest = self.compressionEnabled and 
        NetworkCompression.CompressRequest(request) or request
    
    -- Add to batch processor
    self.batchProcessor:AddRequest(processedRequest)
end

function OptimizedNetworkManager:SendValidationResult(validation: any): ()
    self.networkStats.validationsReceived = (self.networkStats.validationsReceived :: number) + 1
    
    -- Compress if enabled
    local processedValidation = self.compressionEnabled and 
        NetworkCompression.CompressValidation(validation) or validation
    
    -- Add to batch processor
    self.batchProcessor:AddValidation(processedValidation)
end

function OptimizedNetworkManager:GetNetworkStats(): {[string]: number}
    return table.clone(self.networkStats)
end

function OptimizedNetworkManager:EnableCompression(enabled: boolean): ()
    self.compressionEnabled = enabled
end

-- Adaptive network optimization (adjusts based on performance)
local AdaptiveNetworkOptimizer = {}
AdaptiveNetworkOptimizer.__index = AdaptiveNetworkOptimizer

function AdaptiveNetworkOptimizer.new(networkManager: any)
    local self = setmetatable({}, AdaptiveNetworkOptimizer)
    
    self.networkManager = networkManager
    self.performanceMetrics = {
        averageLatency = 0,
        packetLoss = 0,
        throughput = 0,
    }
    
    -- Start performance monitoring
    task.spawn(function()
        self:MonitorPerformance()
    end)
    
    return self
end

function AdaptiveNetworkOptimizer:MonitorPerformance(): ()
    while true do
        task.wait(5) -- Check every 5 seconds
        
        local stats = self.networkManager:GetNetworkStats()
        
        -- Adaptive optimization based on performance
        if stats.averageBatchSize < 3 then
            -- Low batch efficiency - reduce batch interval
            BATCH_INTERVAL = math.max(0.016, BATCH_INTERVAL * 0.9) -- Minimum 60 FPS
        elseif stats.averageBatchSize > 8 then
            -- High batch efficiency - can increase interval slightly
            BATCH_INTERVAL = math.min(0.1, BATCH_INTERVAL * 1.1) -- Maximum 10 FPS
        end
        
        print(`Network Performance: Batch interval: {string.format("%.3f", BATCH_INTERVAL)}s, Avg batch size: {stats.averageBatchSize}`)
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
