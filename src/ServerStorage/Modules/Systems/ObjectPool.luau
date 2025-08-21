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

-- Pre-built pools for common objects
local CommonPools = {}

-- Vector3 pool
CommonPools.Vector3Pool = ObjectPool.new(
	function() return Vector3.new(0, 0, 0) end,
	nil, -- Vector3 is immutable, no reset needed
	64
)

-- CFrame pool  
CommonPools.CFramePool = ObjectPool.new(
	function() return CFrame.new() end,
	nil, -- CFrame is immutable, no reset needed
	32
)

-- Table pool for temporary data structures
CommonPools.TablePool = ObjectPool.new(
	function() return {} end,
	function(t) table.clear(t) end, -- Reset by clearing
	128
)

-- Array pool for lists
CommonPools.ArrayPool = ObjectPool.new(
	function() return table.create(16) end,
	function(arr) table.clear(arr) end,
	64
)

-- Ray pool for raycasting
CommonPools.RayPool = ObjectPool.new(
	function() return Ray.new(Vector3.new(), Vector3.new()) end,
	nil, -- Ray is immutable
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
