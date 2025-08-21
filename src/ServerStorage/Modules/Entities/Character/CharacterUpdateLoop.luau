--!strict
-- CharacterUpdateLoop - Ultra-fast character updates with frame budgeting
local Players = game:GetService("Players")

local UpdateScheduler = require(game.ServerStorage.Modules.Systems.UpdateScheduler)
local FrameBudgetManager = require(game.ServerStorage.Modules.Systems.FrameBudgetManager)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

type internalCharacter = CharacterTypes.internalCharacter

export type PerformanceMetrics = {
	UpdateTime: number,
	CharacterCount: number,
	LastCleanup: number,
	FrameCount: number,
	AverageFrameTime: number,
	SkippedFrames: number,
}

export type ICharacterUpdateLoop = {
	Start: (self: ICharacterUpdateLoop) -> (),
	Stop: (self: ICharacterUpdateLoop) -> (),
	SetUpdateInterval: (self: ICharacterUpdateLoop, interval: number) -> (),
	GetPerformanceMetrics: (self: ICharacterUpdateLoop) -> PerformanceMetrics,
	SetUpdateCallback: (self: ICharacterUpdateLoop, callback: (number) -> ()) -> (),
}

local CharacterUpdateLoop = {}
CharacterUpdateLoop.__index = CharacterUpdateLoop

function CharacterUpdateLoop.new(interval: number?): ICharacterUpdateLoop
	local self = setmetatable({}, CharacterUpdateLoop)
	
	self._interval = interval or 1/120 -- Store the interval
	self._scheduler = UpdateScheduler.New(self._interval)
	self._updateCallback = nil :: ((number) -> ())?
	self._isRunning = false
	self._connections = table.create(8) -- Pre-allocated connections array
	
	-- Performance tracking with pre-allocated structure
	self._performanceMetrics = {
		UpdateTime = 0,
		CharacterCount = 0,
		LastCleanup = 0,
		FrameCount = 0,
		AverageFrameTime = 0,
		SkippedFrames = 0,
	} :: PerformanceMetrics
	
	-- Ultra-fast batch processing state
	self._batchedUpdates = table.create(64) -- Pre-allocated batch array
	self._updateBatchSize = 16 -- Process characters in batches
	self._lastUpdateTime = 0
	self._frameSkipThreshold = 16.67 -- Skip frames if falling behind (60fps = 16.67ms)
	self._frameTimes = table.create(30) -- Rolling average of frame times
	self._frameTimeIndex = 1
	
	return (self :: any) :: ICharacterUpdateLoop
end

function CharacterUpdateLoop:SetUpdateCallback(callback: (number) -> ())
	self._updateCallback = callback
end

function CharacterUpdateLoop:SetUpdateInterval(interval: number)
	self._interval = interval -- Update stored interval
	if self._scheduler and self._scheduler.SetInterval then
		self._scheduler:SetInterval(interval)
	end
end

function CharacterUpdateLoop:Start()
	if self._isRunning then
		warn("CharacterUpdateLoop is already running")
		return
	end
	
	if not self._updateCallback then
		warn("No update callback set for CharacterUpdateLoop")
		return
	end
	
	-- Set up the update loop with enhanced performance tracking
	local disconnect = self._scheduler:OnStep(function(dt: number)
		local startTime = time()
		
		-- Update frame counter
		local metrics: PerformanceMetrics = self._performanceMetrics
		metrics.FrameCount = metrics.FrameCount + 1
		
		-- Execute the update callback
		self._updateCallback(dt)
		
		-- Update performance metrics with rolling average
		local frameTime = time() - startTime
		metrics.UpdateTime = frameTime
		
		-- Update rolling average frame time
		local frameTimes = self._frameTimes :: {number}
		local frameIndex = self._frameTimeIndex :: number
		frameTimes[frameIndex] = frameTime
		self._frameTimeIndex = (frameIndex % 30) + 1
		
		-- Calculate average frame time
		local total = 0
		local count = 0
		for i = 1, #frameTimes do
			if frameTimes[i] then
				total += frameTimes[i]
				count += 1
			end
		end
		metrics.AverageFrameTime = if count > 0 then total / count else 0
		
		-- Track frame skips if performance is poor
		if frameTime > self._frameSkipThreshold then
			metrics.SkippedFrames = metrics.SkippedFrames + 1
		end
	end)
	
	self._scheduler:Start()
	self._isRunning = true
	
	-- Store connection for cleanup
	table.insert(self._connections, { 
		Disconnect = function()
			disconnect()
			if self._scheduler then
				self._scheduler:Destroy()
				-- Don't set to nil, just mark as destroyed
			end
		end 
	} :: any)
end

function CharacterUpdateLoop:Stop()
	if not self._isRunning then
		return
	end
	
	-- Disconnect all connections
	for _, connection in pairs(self._connections) do
		if connection and connection.Disconnect then
			connection:Disconnect()
		end
	end
	
	table.clear(self._connections)
	self._isRunning = false
	
	if self._scheduler then
		self._scheduler:Destroy()
		self._scheduler = UpdateScheduler.New(self._interval) -- Recreate with original interval
	end
end

function CharacterUpdateLoop:GetPerformanceMetrics(): PerformanceMetrics
	return table.clone(self._performanceMetrics)
end

return CharacterUpdateLoop
