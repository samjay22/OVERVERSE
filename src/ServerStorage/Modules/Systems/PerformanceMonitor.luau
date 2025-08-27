--!strict
-- PerformanceMonitor: Real-time performance tracking and optimization recommendations

local RunService = game:GetService("RunService")
local _HttpService = game:GetService("HttpService")

type PerformanceMetrics = {
	frameTime: number,
	memoryUsage: number,
	networkLatency: number,
	activeConnections: number,
	cacheHitRate: number,
	batchEfficiency: number,
	characterUpdateTime: number,
	gcCollections: number,
}

type PerformanceThresholds = {
	maxFrameTime: number,
	maxMemoryMB: number,
	maxNetworkLatency: number,
	minCacheHitRate: number,
	minBatchEfficiency: number,
}

local PerformanceMonitor = {}
PerformanceMonitor.__index = PerformanceMonitor

function PerformanceMonitor.new()
	local self = setmetatable({}, PerformanceMonitor)
	
	self._metrics = {} :: PerformanceMetrics
	self._thresholds = {
		maxFrameTime = 16.67, -- 60 FPS
		maxMemoryMB = 512,
		maxNetworkLatency = 100,
		minCacheHitRate = 0.8,
		minBatchEfficiency = 0.6,
	} :: PerformanceThresholds
	
	self._sampleCount = 0
	self._totalSamples = 120 -- 2 seconds at 60fps
	self._warningCallbacks = {} :: {(string, PerformanceMetrics) -> ()}
	
	-- Start monitoring
	self:_startMonitoring()
	
	return self
end

function PerformanceMonitor:_startMonitoring()
	-- Monitor frame time
	RunService.Heartbeat:Connect(function(deltaTime)
		self:_updateMetrics(deltaTime)
		self:_checkThresholds()
	end)
	
	-- Periodic detailed analysis
	task.spawn(function()
		while true do
			task.wait(10) -- Every 10 seconds
			self:_performDetailedAnalysis()
		end
	end)
end

-- HEAVILY OPTIMIZED: Performance metrics with buffer-based tracking
function PerformanceMonitor:_updateMetrics(deltaTime: number)
	self._sampleCount = (self._sampleCount + 1) % self._totalSamples

	-- Update frame time (rolling average with better smoothing)
	local frameTimeMs = deltaTime * 1000
	if self._metrics.frameTime then
		-- Use exponential moving average with adaptive smoothing
		local alpha = frameTimeMs > 20 and 0.3 or 0.1 -- React faster to spikes
		self._metrics.frameTime = (self._metrics.frameTime * (1 - alpha)) + (frameTimeMs * alpha)
	else
		self._metrics.frameTime = frameTimeMs
	end

	-- OPTIMIZED: Update memory usage less frequently but with trend analysis
	if self._sampleCount % 60 == 0 then -- Every 2 seconds instead of 1
		local currentMemory = gcinfo()
		local lastMemory = self._metrics.memoryUsage or currentMemory

		self._metrics.memoryUsage = currentMemory
		self._metrics.memoryTrend = currentMemory - lastMemory

		-- Trigger GC if memory is growing too fast
		if self._metrics.memoryTrend > 50 then -- 50MB growth
			collectgarbage("collect")
		end
	end

	-- OPTIMIZED: Track buffer pool efficiency
	if self._sampleCount % 30 == 0 then
		local ObjectPool = require(game.ServerStorage.Modules.Systems.ObjectPool)
		self._metrics.bufferPoolHitRate = self:_calculateBufferPoolHitRate(ObjectPool)
	end

	-- OPTIMIZED: Track network efficiency
	if self._sampleCount % 45 == 0 then
		self._metrics.networkEfficiency = self:_calculateNetworkEfficiency()
	end
end

function PerformanceMonitor:_checkThresholds()
	local metrics = self._metrics
	local thresholds = self._thresholds
	
	-- Check frame time
	if metrics.frameTime > thresholds.maxFrameTime then
		self:_triggerWarning("High frame time detected", metrics)
	end
	
	-- Check memory usage
	if metrics.memoryUsage > thresholds.maxMemoryMB then
		self:_triggerWarning("High memory usage detected", metrics)
	end
	
	-- Check cache hit rate
	if metrics.cacheHitRate and metrics.cacheHitRate < thresholds.minCacheHitRate then
		self:_triggerWarning("Low cache hit rate detected", metrics)
	end
end

function PerformanceMonitor:_performDetailedAnalysis()
	local report = self:GenerateReport()
	print("=== PERFORMANCE REPORT ===")
	print(`Frame Time: {string.format("%.2f", report.frameTime)}ms (Target: <16.67ms)`)
	print(`Memory Usage: {string.format("%.1f", report.memoryUsage)}MB`)
	print(`Cache Hit Rate: {string.format("%.1f", (report.cacheHitRate or 0) * 100)}%`)
	
	-- Generate recommendations
	local recommendations = self:_generateRecommendations(report)
	if #recommendations > 0 then
		print("=== OPTIMIZATION RECOMMENDATIONS ===")
		for _, rec in ipairs(recommendations) do
			print(`• {rec}`)
		end
	end
	print("=== END REPORT ===")
end

function PerformanceMonitor:_generateRecommendations(metrics: PerformanceMetrics): {string}
	local recommendations = {}
	
	if metrics.frameTime > 20 then
		table.insert(recommendations, "Consider reducing character update frequency")
		table.insert(recommendations, "Enable aggressive batching for network operations")
	end
	
	if metrics.memoryUsage > 400 then
		table.insert(recommendations, "Implement more aggressive cache cleanup")
		table.insert(recommendations, "Use object pooling for frequently allocated objects")
	end
	
	if metrics.cacheHitRate and metrics.cacheHitRate < 0.7 then
		table.insert(recommendations, "Increase cache sizes for frequently accessed data")
		table.insert(recommendations, "Review cache eviction policies")
	end
	
	if metrics.batchEfficiency and metrics.batchEfficiency < 0.5 then
		table.insert(recommendations, "Optimize network batch sizes")
		table.insert(recommendations, "Implement priority batching for critical operations")
	end
	
	return recommendations
end

function PerformanceMonitor:_triggerWarning(message: string, metrics: PerformanceMetrics)
	warn(`[PerformanceMonitor] {message}`)
	
	for _, callback in ipairs(self._warningCallbacks) do
		pcall(callback, message, metrics)
	end
end

function PerformanceMonitor:AddWarningCallback(callback: (string, PerformanceMetrics) -> ())
	table.insert(self._warningCallbacks, callback)
end

function PerformanceMonitor:UpdateMetric(key: string, value: number)
	(self._metrics :: any)[key] = value
end

function PerformanceMonitor:GenerateReport(): PerformanceMetrics
	return table.clone(self._metrics)
end

function PerformanceMonitor:GetRecommendations(): {string}
	return self:_generateRecommendations(self._metrics)
end

-- OPTIMIZED: Calculate buffer pool hit rate for memory efficiency tracking
function PerformanceMonitor:_calculateBufferPoolHitRate(ObjectPool: any): number
	local totalRequests = 0
	local totalHits = 0

	-- Check all common pools
	local pools = {
		ObjectPool.Vector3Pool,
		ObjectPool.CFramePool,
		ObjectPool.TablePool,
		ObjectPool.ArrayPool,
		ObjectPool.RayPool,
	}

	for _, pool in ipairs(pools) do
		if pool and pool.GetStats then
			local stats = pool:GetStats()
			totalRequests += stats.requests or 0
			totalHits += stats.hits or 0
		end
	end

	return totalRequests > 0 and (totalHits / totalRequests) or 1.0
end

-- OPTIMIZED: Calculate network efficiency based on buffer usage
function PerformanceMonitor:_calculateNetworkEfficiency(): number
	-- This would integrate with the network layer to track:
	-- - Buffer reuse rate
	-- - Compression ratio
	-- - Delta update efficiency
	-- For now, return a placeholder
	return 0.85
end

-- OPTIMIZED: Auto-optimization based on performance metrics
function PerformanceMonitor:_autoOptimize()
	local metrics = self._metrics

	-- Adjust update frequencies based on performance
	if metrics.frameTime > 25 then -- Over 25ms frame time
		-- Reduce update frequencies
		self:_triggerOptimization("REDUCE_UPDATE_FREQUENCY")
	elseif metrics.frameTime < 10 then -- Under 10ms frame time
		-- Can increase update frequencies
		self:_triggerOptimization("INCREASE_UPDATE_FREQUENCY")
	end

	-- Memory optimization
	if metrics.memoryUsage > 800 then -- Over 800MB
		self:_triggerOptimization("AGGRESSIVE_CLEANUP")
	end

	-- Buffer pool optimization
	if metrics.bufferPoolHitRate and metrics.bufferPoolHitRate < 0.7 then
		self:_triggerOptimization("INCREASE_POOL_SIZES")
	end
end

function PerformanceMonitor:_triggerOptimization(optimizationType: string)
	warn(`[PerformanceMonitor] Auto-optimization triggered: {optimizationType}`)

	-- Implement specific optimizations based on type
	if optimizationType == "REDUCE_UPDATE_FREQUENCY" then
		-- Signal to reduce character update frequency
		game:GetService("ReplicatedStorage"):SetAttribute("ReduceUpdateFreq", true)
	elseif optimizationType == "AGGRESSIVE_CLEANUP" then
		-- Force garbage collection and cleanup
		collectgarbage("collect")
		-- Signal components to clean up caches
		game:GetService("ReplicatedStorage"):SetAttribute("AggressiveCleanup", true)
	elseif optimizationType == "INCREASE_POOL_SIZES" then
		-- Signal to increase object pool sizes
		game:GetService("ReplicatedStorage"):SetAttribute("IncreasePoolSizes", true)
	end
end

return PerformanceMonitor
