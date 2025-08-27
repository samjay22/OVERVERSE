--!strict
-- BufferCharacterSync - Ultra-fast character state synchronization using buffers
-- Optimized for minimal network bandwidth and maximum performance

local ObjectPool = require(game.ServerStorage.Modules.Systems.ObjectPool)
local BufferStateManager = require(game.ServerStorage.Modules.Systems.BufferStateManager)

-- Performance optimizations
local bufferCreate = buffer.create
local bufferCopy = buffer.copy
local bufferReadf32 = buffer.readf32
local bufferWritef32 = buffer.writef32
local bufferReadi32 = buffer.readi32
local bufferWritei32 = buffer.writei32
local bufferReadu8 = buffer.readu8
local bufferWriteu8 = buffer.writeu8
local tick = tick

-- Character state field IDs for compact serialization
local StateFields = {
    POSITION = 1,
    ROTATION = 2,
    VELOCITY = 3,
    HEALTH = 4,
    STAMINA = 5,
    MANA = 6,
    ANIMATION_STATE = 7,
    ABILITY_STATE = 8,
    COMBO_COUNT = 9,
    MOVEMENT_STATE = 10,
    LOOK_DIRECTION = 11,
    IS_GROUNDED = 12,
    IS_SPRINTING = 13,
    IS_CROUCHING = 14,
    WEAPON_EQUIPPED = 15,
}

-- Compression flags for delta updates
local CompressionFlags = {
    POSITION_CHANGED = 1,
    ROTATION_CHANGED = 2,
    HEALTH_CHANGED = 4,
    ANIMATION_CHANGED = 8,
    ABILITY_CHANGED = 16,
    MOVEMENT_CHANGED = 32,
}

type CharacterState = {
    playerId: number,
    position: Vector3?,
    rotation: Vector3?,
    velocity: Vector3?,
    health: number?,
    stamina: number?,
    mana: number?,
    animationState: string?,
    abilityState: string?,
    comboCount: number?,
    movementState: string?,
    lookDirection: Vector3?,
    isGrounded: boolean?,
    isSprinting: boolean?,
    isCrouching: boolean?,
    weaponEquipped: string?,
    timestamp: number?,
}

local BufferCharacterSync = {}
BufferCharacterSync.__index = BufferCharacterSync

-- Helper function to check if a flag is set (since we can't use bitwise AND)
local function hasFlag(flags: number, flag: number): boolean
    return flags >= flag and (flags % (flag * 2)) >= flag
end

function BufferCharacterSync.new(): any
    local self = setmetatable({}, BufferCharacterSync)
    
    self._lastStates = {} :: {[number]: CharacterState} -- playerId -> last state
    self._stateBuffers = {} :: {[number]: BufferStateManager} -- playerId -> buffer manager
    self._compressionThreshold = 0.1 -- Minimum change to trigger update
    self._maxUpdateRate = 1/20 -- 20 updates per second max
    self._lastUpdateTime = {} :: {[number]: number}
    
    return self
end

-- OPTIMIZED: Serialize character state with delta compression
function BufferCharacterSync:SerializeState(playerId: number, state: CharacterState): buffer?
    local currentTime = tick()
    local lastUpdateTime = self._lastUpdateTime[playerId] or 0
    
    -- Rate limiting
    if currentTime - lastUpdateTime < self._maxUpdateRate then
        return nil
    end
    
    local lastState = self._lastStates[playerId]
    local compressionFlags = 0
    
    -- Calculate what changed (using addition instead of bitwise OR)
    if not lastState or self:_hasPositionChanged(state, lastState) then
        compressionFlags = compressionFlags + CompressionFlags.POSITION_CHANGED
    end

    if not lastState or self:_hasRotationChanged(state, lastState) then
        compressionFlags = compressionFlags + CompressionFlags.ROTATION_CHANGED
    end

    if not lastState or math.abs((state.health or 0) - (lastState.health or 0)) > self._compressionThreshold then
        compressionFlags = compressionFlags + CompressionFlags.HEALTH_CHANGED
    end

    if not lastState or state.animationState ~= lastState.animationState then
        compressionFlags = compressionFlags + CompressionFlags.ANIMATION_CHANGED
    end

    if not lastState or state.abilityState ~= lastState.abilityState then
        compressionFlags = compressionFlags + CompressionFlags.ABILITY_CHANGED
    end

    if not lastState or state.movementState ~= lastState.movementState then
        compressionFlags = compressionFlags + CompressionFlags.MOVEMENT_CHANGED
    end
    
    -- No changes worth sending
    if compressionFlags == 0 then
        return nil
    end
    
    -- Create delta buffer
    local buf = ObjectPool.NetworkBufferPool:Get()
    local offset = 0
    
    -- Write header
    bufferWritei32(buf, offset, playerId)
    offset += 4
    bufferWriteu8(buf, offset, compressionFlags)
    offset += 1
    bufferWritef32(buf, offset, currentTime)
    offset += 4
    
    -- Write changed fields only
    if hasFlag(compressionFlags, CompressionFlags.POSITION_CHANGED) and state.position then
        offset = self:_writeVector3(buf, offset, state.position)
    end

    if hasFlag(compressionFlags, CompressionFlags.ROTATION_CHANGED) and state.rotation then
        offset = self:_writeVector3(buf, offset, state.rotation)
    end

    if hasFlag(compressionFlags, CompressionFlags.HEALTH_CHANGED) and state.health then
        bufferWritef32(buf, offset, state.health)
        offset += 4
    end

    if hasFlag(compressionFlags, CompressionFlags.ANIMATION_CHANGED) and state.animationState then
        offset = self:_writeString(buf, offset, state.animationState)
    end

    if hasFlag(compressionFlags, CompressionFlags.ABILITY_CHANGED) and state.abilityState then
        offset = self:_writeString(buf, offset, state.abilityState)
    end

    if hasFlag(compressionFlags, CompressionFlags.MOVEMENT_CHANGED) and state.movementState then
        offset = self:_writeString(buf, offset, state.movementState)
    end
    
    -- Write total size at beginning
    bufferWritei32(buf, 0, offset)
    
    -- Update tracking
    self._lastStates[playerId] = state
    self._lastUpdateTime[playerId] = currentTime
    
    return buf
end

-- OPTIMIZED: Deserialize character state from buffer
function BufferCharacterSync:DeserializeState(buf: buffer): CharacterState?
    local totalSize = bufferReadi32(buf, 0)
    if totalSize < 9 then -- Minimum size check
        return nil
    end
    
    local offset = 4
    local playerId = bufferReadi32(buf, offset)
    offset += 4
    local compressionFlags = bufferReadu8(buf, offset)
    offset += 1
    local timestamp = bufferReadf32(buf, offset)
    offset += 4
    
    local state: CharacterState = {
        playerId = playerId,
        timestamp = timestamp,
    }
    
    -- Read changed fields
    if hasFlag(compressionFlags, CompressionFlags.POSITION_CHANGED) then
        state.position, offset = self:_readVector3(buf, offset)
    end

    if hasFlag(compressionFlags, CompressionFlags.ROTATION_CHANGED) then
        state.rotation, offset = self:_readVector3(buf, offset)
    end

    if hasFlag(compressionFlags, CompressionFlags.HEALTH_CHANGED) then
        state.health = bufferReadf32(buf, offset)
        offset += 4
    end

    if hasFlag(compressionFlags, CompressionFlags.ANIMATION_CHANGED) then
        state.animationState, offset = self:_readString(buf, offset)
    end

    if hasFlag(compressionFlags, CompressionFlags.ABILITY_CHANGED) then
        state.abilityState, offset = self:_readString(buf, offset)
    end

    if hasFlag(compressionFlags, CompressionFlags.MOVEMENT_CHANGED) then
        state.movementState, offset = self:_readString(buf, offset)
    end
    
    return state
end

-- OPTIMIZED: Batch serialize multiple character states
function BufferCharacterSync:SerializeBatch(states: {CharacterState}): buffer?
    local validStates = {}
    
    -- Filter states that need updates
    for _, state in ipairs(states) do
        local serialized = self:SerializeState(state.playerId, state)
        if serialized then
            table.insert(validStates, serialized)
        end
    end
    
    if #validStates == 0 then
        return nil
    end
    
    -- Calculate total size needed
    local totalSize = 4 -- Count header
    for _, stateBuf in ipairs(validStates) do
        totalSize += bufferReadi32(stateBuf, 0)
    end
    
    local batchBuf = ObjectPool.LargeBufferPool:Get()
    if buffer.len(batchBuf) < totalSize then
        batchBuf = bufferCreate(totalSize)
    end
    
    -- Write batch header
    bufferWritei32(batchBuf, 0, #validStates)
    local offset = 4
    
    -- Copy all state buffers
    for _, stateBuf in ipairs(validStates) do
        local stateSize = bufferReadi32(stateBuf, 0)
        bufferCopy(batchBuf, offset, stateBuf, 0, stateSize)
        offset += stateSize
        
        -- Return buffer to pool
        ObjectPool.NetworkBufferPool:Return(stateBuf)
    end
    
    return batchBuf
end

-- Helper methods for serialization
function BufferCharacterSync:_writeVector3(buf: buffer, offset: number, vec: Vector3): number
    bufferWritef32(buf, offset, vec.X)
    bufferWritef32(buf, offset + 4, vec.Y)
    bufferWritef32(buf, offset + 8, vec.Z)
    return offset + 12
end

function BufferCharacterSync:_readVector3(buf: buffer, offset: number): (Vector3, number)
    local x = bufferReadf32(buf, offset)
    local y = bufferReadf32(buf, offset + 4)
    local z = bufferReadf32(buf, offset + 8)
    return Vector3.new(x, y, z), offset + 12
end

function BufferCharacterSync:_writeString(buf: buffer, offset: number, str: string): number
    local len = math.min(#str, 255) -- Max string length
    bufferWriteu8(buf, offset, len)
    buffer.writestring(buf, offset + 1, str, len)
    return offset + 1 + len
end

function BufferCharacterSync:_readString(buf: buffer, offset: number): (string, number)
    local len = bufferReadu8(buf, offset)
    local str = buffer.readstring(buf, offset + 1, len)
    return str, offset + 1 + len
end

function BufferCharacterSync:_hasPositionChanged(current: CharacterState, last: CharacterState): boolean
    if not current.position or not last.position then
        return current.position ~= last.position
    end
    
    local delta = current.position - last.position
    return delta.Magnitude > self._compressionThreshold
end

function BufferCharacterSync:_hasRotationChanged(current: CharacterState, last: CharacterState): boolean
    if not current.rotation or not last.rotation then
        return current.rotation ~= last.rotation
    end
    
    local delta = current.rotation - last.rotation
    return delta.Magnitude > math.rad(5) -- 5 degree threshold
end

return BufferCharacterSync
