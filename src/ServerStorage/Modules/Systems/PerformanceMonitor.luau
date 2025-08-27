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

function PerformanceMonitor:_updateMetrics(deltaTime: number)
	self._sampleCount = (self._sampleCount + 1) % self._totalSamples
	
	-- Update frame time (rolling average)
	local frameTimeMs = deltaTime * 1000
	if self._metrics.frameTime then
		self._metrics.frameTime = (self._metrics.frameTime * 0.9) + (frameTimeMs * 0.1)
	else
		self._metrics.frameTime = frameTimeMs
	end
	
	-- Update memory usage (periodically)
	if self._sampleCount % 30 == 0 then
		self._metrics.memoryUsage = gcinfo()
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

return PerformanceMonitor
