--!strict
-- CharacterUpdateLoop - Handles the update scheduling and performance tracking
local Players = game:GetService("Players")

local UpdateScheduler = require(game.ServerStorage.Modules.Utilities.UpdateScheduler)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

type internalCharacter = CharacterTypes.internalCharacter

export type PerformanceMetrics = {
	UpdateTime: number,
	CharacterCount: number,
	LastCleanup: number,
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
	self._connections = {}
	
	-- Performance tracking
	self._performanceMetrics = {
		UpdateTime = 0,
		CharacterCount = 0,
		LastCleanup = 0
	} :: PerformanceMetrics
	
	return self
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
	
	-- Set up the update loop
	local disconnect = self._scheduler:OnStep(function(dt: number)
		local startTime = time()
		
		-- Execute the update callback
		self._updateCallback(dt)
		
		-- Update performance metrics
		self._performanceMetrics.UpdateTime = time() - startTime
	end)
	
	self._scheduler:Start()
	self._isRunning = true
	
	-- Store connection for cleanup
	table.insert(self._connections, { 
		Disconnect = function()
			disconnect()
			if self._scheduler then
				self._scheduler:Destroy()
				self._scheduler = nil
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
