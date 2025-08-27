--!strict
-- BufferStateManager - Ultra-high performance state management using buffers
-- Replaces table-based state with buffer-based serialization for maximum performance

local ObjectPool = require(game.ServerStorage.Modules.Systems.ObjectPool)

-- Performance optimizations - cache frequently used functions
local bufferCreate = buffer.create
local bufferCopy = buffer.copy
local bufferReadf32 = buffer.readf32
local bufferWritef32 = buffer.writef32
local bufferReadi32 = buffer.readi32
local bufferWritei32 = buffer.writei32
local bufferReadu8 = buffer.readu8
local bufferWriteu8 = buffer.writeu8
local bufferLen = buffer.len

-- State type definitions for buffer layout
local StateTypes = {
    FLOAT = 1,
    INT = 2,
    BOOL = 3,
    VECTOR3 = 4,
    STRING = 5,
}

-- Buffer layout constants (in bytes)
local HEADER_SIZE = 8 -- 4 bytes for count + 4 bytes for total size
local ENTRY_HEADER_SIZE = 8 -- 4 bytes for key hash + 4 bytes for type/size
local FLOAT_SIZE = 4
local INT_SIZE = 4
local BOOL_SIZE = 1
local VECTOR3_SIZE = 12 -- 3 floats

type BufferStateManager = {
    _buffer: buffer,
    _size: number,
    _keyMap: {[string]: number}, -- key -> offset mapping
    _changeBuffer: buffer, -- For delta updates
    _lastSnapshot: buffer, -- For change detection
    _pool: any,
}

local BufferStateManager = {}
BufferStateManager.__index = BufferStateManager

function BufferStateManager.new(initialSize: number?): BufferStateManager
    local self = setmetatable({}, BufferStateManager)
    
    local size = initialSize or 2048
    self._buffer = bufferCreate(size)
    self._size = size
    self._keyMap = {}
    self._changeBuffer = bufferCreate(size)
    self._lastSnapshot = bufferCreate(size)
    self._pool = ObjectPool.TablePool -- Use table pool instead
    
    -- Initialize header
    bufferWritei32(self._buffer, 0, 0) -- entry count
    bufferWritei32(self._buffer, 4, HEADER_SIZE) -- current data size
    
    return self :: any
end

-- OPTIMIZED: Hash function for string keys (faster than string comparison)
local function hashString(str: string): number
    local hash = 5381
    for i = 1, #str do
        hash = ((hash * 33) + string.byte(str, i)) % 2147483647
    end
    return hash
end

-- OPTIMIZED: Set value using buffer serialization
function BufferStateManager:Set(key: string, value: any)
    local keyHash = hashString(key)
    local valueType = typeof(value)
    
    local offset = self._keyMap[key]
    local _needsReallocation = false
    local requiredSize = 0
    
    -- Calculate required size based on type
    if valueType == "number" then
        if value % 1 == 0 then -- Integer
            requiredSize = ENTRY_HEADER_SIZE + INT_SIZE
        else -- Float
            requiredSize = ENTRY_HEADER_SIZE + FLOAT_SIZE
        end
    elseif valueType == "boolean" then
        requiredSize = ENTRY_HEADER_SIZE + BOOL_SIZE
    elseif valueType == "Vector3" then
        requiredSize = ENTRY_HEADER_SIZE + VECTOR3_SIZE
    elseif valueType == "string" then
        requiredSize = ENTRY_HEADER_SIZE + #value
    else
        warn(`BufferStateManager: Unsupported type {valueType}`)
        return
    end
    
    -- Check if we need to reallocate
    local currentSize = bufferReadi32(self._buffer, 4)
    if not offset then
        -- New entry
        if currentSize + requiredSize > self._size then
            self:_reallocate(self._size * 2)
        end
        offset = currentSize
        self._keyMap[key] = offset
        
        -- Update header
        local entryCount = bufferReadi32(self._buffer, 0) + 1
        bufferWritei32(self._buffer, 0, entryCount)
        bufferWritei32(self._buffer, 4, currentSize + requiredSize)
    end
    
    -- Write entry header
    bufferWritei32(self._buffer, offset, keyHash)
    
    -- Write value based on type
    if valueType == "number" then
        if value % 1 == 0 then -- Integer
            bufferWritei32(self._buffer, offset + 4, (StateTypes.INT * 16777216) + INT_SIZE) -- 16777216 = 2^24
            bufferWritei32(self._buffer, offset + 8, value)
        else -- Float
            bufferWritei32(self._buffer, offset + 4, (StateTypes.FLOAT * 16777216) + FLOAT_SIZE)
            bufferWritef32(self._buffer, offset + 8, value)
        end
    elseif valueType == "boolean" then
        bufferWritei32(self._buffer, offset + 4, (StateTypes.BOOL * 16777216) + BOOL_SIZE)
        bufferWriteu8(self._buffer, offset + 8, value and 1 or 0)
    elseif valueType == "Vector3" then
        bufferWritei32(self._buffer, offset + 4, (StateTypes.VECTOR3 * 16777216) + VECTOR3_SIZE)
        bufferWritef32(self._buffer, offset + 8, value.X)
        bufferWritef32(self._buffer, offset + 12, value.Y)
        bufferWritef32(self._buffer, offset + 16, value.Z)
    elseif valueType == "string" then
        local strLen = #value
        bufferWritei32(self._buffer, offset + 4, (StateTypes.STRING * 16777216) + strLen)
        buffer.writestring(self._buffer, offset + 8, value)
    end
end

-- OPTIMIZED: Get value using buffer deserialization
function BufferStateManager:Get(key: string): any
    local offset = self._keyMap[key]
    if not offset then
        return nil
    end

    local typeAndSize = bufferReadi32(self._buffer, (offset :: number) + 4)
    local valueType = math.floor(typeAndSize / 16777216) -- Equivalent to >> 24
    local size = typeAndSize % 16777216 -- Equivalent to & 0xFFFFFF

    if valueType == StateTypes.FLOAT then
        return bufferReadf32(self._buffer, (offset :: number) + 8)
    elseif valueType == StateTypes.INT then
        return bufferReadi32(self._buffer, (offset :: number) + 8)
    elseif valueType == StateTypes.BOOL then
        return bufferReadu8(self._buffer, (offset :: number) + 8) == 1
    elseif valueType == StateTypes.VECTOR3 then
        local x = bufferReadf32(self._buffer, (offset :: number) + 8)
        local y = bufferReadf32(self._buffer, (offset :: number) + 12)
        local z = bufferReadf32(self._buffer, (offset :: number) + 16)
        return Vector3.new(x, y, z)
    elseif valueType == StateTypes.STRING then
        return buffer.readstring(self._buffer, (offset :: number) + 8, size)
    end

    return nil
end

-- OPTIMIZED: Create delta buffer for network transmission
function BufferStateManager:CreateDelta(): buffer?
    local currentSize = bufferReadi32(self._buffer, 4)
    
    -- Compare with last snapshot
    if bufferLen(self._lastSnapshot) ~= currentSize then
        -- Size changed, full update needed
        bufferCopy(self._lastSnapshot, 0, self._buffer, 0, currentSize)
        return self._buffer
    end
    
    -- Check for changes
    local hasChanges = false
    for i = 0, currentSize - 1, 4 do
        if bufferReadi32(self._buffer, i) ~= bufferReadi32(self._lastSnapshot, i) then
            hasChanges = true
            break
        end
    end
    
    if not hasChanges then
        return nil -- No changes
    end
    
    -- Update snapshot
    bufferCopy(self._lastSnapshot, 0, self._buffer, 0, currentSize)
    return self._buffer
end

-- OPTIMIZED: Reallocate buffer when needed
function BufferStateManager:_reallocate(newSize: number)
    local oldBuffer = self._buffer
    local oldSize = bufferReadi32(oldBuffer, 4)
    
    self._buffer = bufferCreate(newSize)
    self._size = newSize
    
    -- Copy existing data
    bufferCopy(self._buffer, 0, oldBuffer, 0, oldSize)
    
    -- Reallocate other buffers
    self._changeBuffer = bufferCreate(newSize)
    self._lastSnapshot = bufferCreate(newSize)
end

-- OPTIMIZED: Batch operations for multiple state changes
function BufferStateManager:BatchSet(changes: {[string]: any})
    -- Pre-calculate total size needed
    local totalSize = 0
    for key, value in pairs(changes) do
        local valueType = typeof(value)
        if valueType == "number" then
            totalSize += ENTRY_HEADER_SIZE + (value % 1 == 0 and INT_SIZE or FLOAT_SIZE)
        elseif valueType == "boolean" then
            totalSize += ENTRY_HEADER_SIZE + BOOL_SIZE
        elseif valueType == "Vector3" then
            totalSize += ENTRY_HEADER_SIZE + VECTOR3_SIZE
        elseif valueType == "string" then
            totalSize += ENTRY_HEADER_SIZE + #value
        end
    end
    
    -- Reallocate if needed
    local currentSize = bufferReadi32(self._buffer, 4)
    if currentSize + totalSize > self._size then
        self:_reallocate(math.max(self._size * 2, currentSize + totalSize))
    end
    
    -- Apply all changes
    for key, value in pairs(changes) do
        self:Set(key, value)
    end
end

return BufferStateManager
