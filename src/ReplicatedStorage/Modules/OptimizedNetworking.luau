--!strict
-- Optimized network layer for ability prediction system
-- Performance Focus: Batch requests to reduce network overhead
-- SOLID Principles: Single Responsibility, Interface Segregation

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Ultra-fast network optimization constants
local BATCH_SIZE = 15 -- Increased batch size for better efficiency
local BATCH_INTERVAL = 0.025 -- ~40 FPS batching (25ms) - faster
local MAX_BATCH_WAIT = 0.075 -- Reduced max wait (75ms)
local PRIORITY_BATCH_SIZE = 5 -- Smaller batches for critical abilities
local COMPRESSION_THRESHOLD = 3 -- Compress batches with 3+ items

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
    
    -- Pre-allocated tables for maximum performance
    self.pendingRequests = table.create(32)
    self.pendingValidations = table.create(16)
    self.priorityRequests = table.create(8) -- High-priority requests
    self.lastBatchTime = 0
    self.batchTimer = nil
    
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
    
    -- Immediate batch for priority requests
    if #self.priorityRequests > 0 then
        return true
    end
    
    -- Ultra-fast batching logic - more aggressive
    return #self.pendingRequests >= BATCH_SIZE or 
           timeSinceLastBatch >= BATCH_INTERVAL or
           (timeSinceLastBatch >= MAX_BATCH_WAIT and #self.pendingRequests > 0)
end

function NetworkBatchProcessor:AddRequest(request: any): ()
    -- Check if this is a priority request (damage, blocking, critical abilities)
    local isPriority = self:_isPriorityRequest(request)
    
    if isPriority then
        table.insert(self.priorityRequests, request)
        -- Immediate batch for critical actions
        if #self.priorityRequests >= 3 then
            self:ProcessBatch()
        end
    else
        table.insert(self.pendingRequests, request)
        
        -- Immediate batch if we hit the size limit
        if #self.pendingRequests >= BATCH_SIZE then
            self:ProcessBatch()
        end
    end
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
    
    -- Merge priority and regular requests, with priority first
    local allRequests = table.create(#self.priorityRequests + #self.pendingRequests)
    
    -- Priority requests go first
    for i = 1, #self.priorityRequests do
        allRequests[i] = self.priorityRequests[i]
    end
    
    -- Add regular requests
    local offset = #self.priorityRequests
    for i = 1, #self.pendingRequests do
        allRequests[offset + i] = self.pendingRequests[i]
    end
    
    local batch: NetworkBatch = {
        timestamp = workspace:GetServerTimeNow(),
        requests = allRequests,
        validations = table.clone(self.pendingValidations),
        priority = #self.priorityRequests > 0, -- Flag for server priority handling
    }
    
    -- Send batch with error handling
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
