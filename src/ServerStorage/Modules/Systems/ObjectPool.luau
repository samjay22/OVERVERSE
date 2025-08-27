--!strict
-- ObjectPool: High-performance object pooling to reduce garbage collection
-- Reuses objects instead of creating new ones constantly

type PooledObject = {
	[string]: any
}

type ObjectPool<T> = {
	_pool: {T},
	_createFn: () -> T,
	_resetFn: ((T) -> ())?,
	_poolSize: number,
	_maxPoolSize: number,
	
	Get: (self: ObjectPool<T>) -> T,
	Return: (self: ObjectPool<T>, obj: T) -> (),
	Clear: (self: ObjectPool<T>) -> (),
	GetPoolSize: (self: ObjectPool<T>) -> number,
}

local ObjectPool = {}
ObjectPool.__index = ObjectPool

function ObjectPool.new<T>(createFn: () -> T, resetFn: ((T) -> ())?, maxPoolSize: number?): ObjectPool<T>
	local self = setmetatable({}, ObjectPool)
	
	self._pool = table.create(maxPoolSize or 32)
	self._createFn = createFn
	self._resetFn = resetFn
	self._poolSize = 0
	self._maxPoolSize = maxPoolSize or 32
	
	return (self :: any) :: ObjectPool<T>
end

function ObjectPool:Get(): any
	if self._poolSize > 0 then
		local obj = self._pool[self._poolSize]
		self._pool[self._poolSize] = nil
		self._poolSize = self._poolSize - 1
		return obj
	else
		-- Pool empty, create new object
		return self._createFn()
	end
end

function ObjectPool:Return(obj: any): ()
	if self._poolSize < self._maxPoolSize then
		-- Reset object if reset function provided
		if self._resetFn then
			self._resetFn(obj)
		end
		
		self._poolSize = self._poolSize + 1
		self._pool[self._poolSize] = obj
	end
	-- If pool is full, object will be garbage collected
end

function ObjectPool:Clear(): ()
	table.clear(self._pool)
	self._poolSize = 0
end

function ObjectPool:GetPoolSize(): number
	return self._poolSize
end

-- HEAVILY OPTIMIZED Pre-built pools for common objects
local CommonPools = {}

-- Performance optimizations - cache frequently used functions
local mathMin = math.min
local mathMax = math.max
local tableInsert = table.insert
local tableRemove = table.remove
local tableClear = table.clear

-- Vector3 pool - INCREASED SIZE for better performance
CommonPools.Vector3Pool = ObjectPool.new(
	function() return Vector3.new(0, 0, 0) end,
	nil, -- Vector3 is immutable, no reset needed
	128 -- Increased from 64
)

-- CFrame pool - INCREASED SIZE
CommonPools.CFramePool = ObjectPool.new(
	function() return CFrame.new() end,
	nil, -- CFrame is immutable, no reset needed
	64 -- Increased from 32
)

-- Table pool for temporary data structures - INCREASED SIZE
CommonPools.TablePool = ObjectPool.new(
	function() return {} end,
	function(t) tableClear(t) end, -- Use cached function
	256 -- Increased from 128
)

-- Array pool for lists - INCREASED SIZE
CommonPools.ArrayPool = ObjectPool.new(
	function() return table.create(32) end, -- Larger initial size
	function(arr) tableClear(arr) end, -- Use cached function
	128 -- Increased from 64
)

-- Ray pool for raycasting - INCREASED SIZE
CommonPools.RayPool = ObjectPool.new(
	function() return Ray.new(Vector3.new(), Vector3.new()) end,
	nil, -- Ray is immutable
	32 -- Increased from 16
)

-- NEW: RaycastParams pool for frequent raycasting
CommonPools.RaycastParamsPool = ObjectPool.new(
	function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {}
		return params
	end,
	function(params)
		tableClear(params.FilterDescendantsInstances)
		params.FilterType = Enum.RaycastFilterType.Exclude
	end,
	16
)

-- NEW: OverlapParams pool for region queries
CommonPools.OverlapParamsPool = ObjectPool.new(
	function()
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {}
		return params
	end,
	function(params)
		tableClear(params.FilterDescendantsInstances)
		params.FilterType = Enum.RaycastFilterType.Exclude
	end,
	8
)

-- NEW: Buffer pools for high-performance data serialization
CommonPools.SmallBufferPool = ObjectPool.new(
	function() return buffer.create(256) end, -- 256 bytes for small data
	nil, -- Buffers don't need reset
	32
)

CommonPools.MediumBufferPool = ObjectPool.new(
	function() return buffer.create(1024) end, -- 1KB for medium data
	nil,
	16
)

CommonPools.LargeBufferPool = ObjectPool.new(
	function() return buffer.create(4096) end, -- 4KB for large data
	nil,
	8
)

-- NEW: Specialized buffer pool for ability data serialization
CommonPools.AbilityDataBufferPool = ObjectPool.new(
	function() return buffer.create(512) end, -- Optimized for ability data
	nil,
	24
)

-- NEW: Network packet buffer pool
CommonPools.NetworkBufferPool = ObjectPool.new(
	function() return buffer.create(2048) end, -- Network packet size
	nil,
	16
)

return {
	ObjectPool = ObjectPool,
	Vector3Pool = CommonPools.Vector3Pool,
	CFramePool = CommonPools.CFramePool,
	TablePool = CommonPools.TablePool,
	ArrayPool = CommonPools.ArrayPool,
	RayPool = CommonPools.RayPool,
}
