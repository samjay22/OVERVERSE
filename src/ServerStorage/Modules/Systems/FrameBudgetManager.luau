--!strict
-- FrameBudgetManager: Manages expensive operations across frames to prevent lag spikes
-- Distributes heavy computations to maintain consistent frame rates

local RunService = game:GetService("RunService")

type Task = {
	id: string,
	callback: () -> (),
	priority: number, -- 1 = highest, 10 = lowest
	estimatedCost: number, -- Milliseconds
}

type FrameBudgetManager = {
	_maxFrameTime: number,
	_frameStartTime: number,
	_pendingTasks: {Task},
	_highPriorityTasks: {Task},
	_running: boolean,
	_connection: RBXScriptConnection?,
	
	AddTask: (self: FrameBudgetManager, task: Task) -> (),
	AddHighPriorityTask: (self: FrameBudgetManager, task: Task) -> (),
	Start: (self: FrameBudgetManager) -> (),
	Stop: (self: FrameBudgetManager) -> (),
	GetRemainingBudget: (self: FrameBudgetManager) -> number,
}

local FrameBudgetManager = {}
FrameBudgetManager.__index = FrameBudgetManager

function FrameBudgetManager.new(maxFrameTimeMs: number?): FrameBudgetManager
	local self = setmetatable({}, FrameBudgetManager)
	
	self._maxFrameTime = (maxFrameTimeMs or 8) / 1000 -- Default 8ms budget
	self._frameStartTime = 0
	self._pendingTasks = table.create(64)
	self._highPriorityTasks = table.create(16)
	self._running = false
	self._connection = nil
	
	return self :: any
end

function FrameBudgetManager:AddTask(task: Task): ()
	table.insert(self._pendingTasks, task)
	
	if not self._running then
		self:Start()
	end
end

function FrameBudgetManager:AddHighPriorityTask(task: Task): ()
	table.insert(self._highPriorityTasks, task)
	
	if not self._running then
		self:Start()
	end
end

function FrameBudgetManager:GetRemainingBudget(): number
	local elapsed = tick() - self._frameStartTime
	return math.max(0, self._maxFrameTime - elapsed)
end

function FrameBudgetManager:Start(): ()
	if self._running then return end
	
	self._running = true
	self._connection = RunService.Heartbeat:Connect(function()
		self:_processFrame()
	end)
end

function FrameBudgetManager:Stop(): ()
	if not self._running then return end
	
	self._running = false
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

function FrameBudgetManager:_processFrame(): ()
	self._frameStartTime = tick()
	
	-- Process high-priority tasks first (always run at least one)
	while #self._highPriorityTasks > 0 do
		local task = table.remove(self._highPriorityTasks, 1)
		if task then
			local success, err = pcall(task.callback)
			if not success then
				warn(`Frame budget task {task.id} failed:`, err)
			end
		end
		
		-- Only break if we have budget remaining and regular tasks
		if self:GetRemainingBudget() <= 0 and #self._pendingTasks > 0 then
			break
		end
	end
	
	-- Process regular tasks within remaining budget
	while #self._pendingTasks > 0 and self:GetRemainingBudget() > 0 do
		local task = table.remove(self._pendingTasks, 1)
		if task then
			-- Skip task if estimated cost exceeds remaining budget
			if task.estimatedCost and task.estimatedCost > self:GetRemainingBudget() * 1000 then
				-- Re-queue for next frame
				table.insert(self._pendingTasks, 1, task)
				break
			end
			
			local taskStart = tick()
			local success, err = pcall(task.callback)
			if not success then
				warn(`Frame budget task {task.id} failed:`, err)
			end
			
			-- Update actual cost for future estimation
			local actualCost = (tick() - taskStart) * 1000
			if task.estimatedCost then
				task.estimatedCost = (task.estimatedCost + actualCost) / 2 -- Moving average
			end
		end
	end
	
	-- Stop if no more tasks
	if #self._pendingTasks == 0 and #self._highPriorityTasks == 0 then
		self:Stop()
	end
end

return FrameBudgetManager
