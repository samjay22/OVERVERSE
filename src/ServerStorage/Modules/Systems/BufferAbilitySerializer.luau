--!strict
-- BufferAbilitySerializer - Ultra-fast ability data serialization using buffers
-- Optimized for network transmission and state synchronization

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
local bufferReadu16 = buffer.readu16
local bufferWriteu16 = buffer.writeu16

-- Ability data field IDs for compact serialization
local FieldIds = {
    ABILITY_ID = 1,
    COOLDOWN_REMAINING = 2,
    CHARGES_REMAINING = 3,
    CAST_TIME = 4,
    DAMAGE = 5,
    RANGE = 6,
    IS_CHANNELING = 7,
    COMBO_COUNT = 8,
    MODIFIER_COUNT = 9,
    TARGET_POSITION = 10,
    CASTER_POSITION = 11,
    EFFECT_COUNT = 12,
}

-- Data type sizes (in bytes)
local HEADER_SIZE = 4 -- Total size
local FIELD_HEADER_SIZE = 2 -- Field ID (1 byte) + Type/Size (1 byte)
local FLOAT_SIZE = 4
local INT_SIZE = 4
local BOOL_SIZE = 1
local VECTOR3_SIZE = 12
local STRING_MAX_SIZE = 64 -- Max string length for ability IDs

type AbilityData = {
    abilityId: string?,
    cooldownRemaining: number?,
    chargesRemaining: number?,
    castTime: number?,
    damage: number?,
    range: number?,
    isChanneling: boolean?,
    comboCount: number?,
    modifierCount: number?,
    targetPosition: Vector3?,
    casterPosition: Vector3?,
    effectCount: number?,
}

local BufferAbilitySerializer = {}

-- OPTIMIZED: Serialize ability data to buffer
function BufferAbilitySerializer.Serialize(data: AbilityData): buffer
    local buf = ObjectPool.AbilityDataBufferPool:Get()
    local offset = HEADER_SIZE
    
    -- Write fields in order of frequency (most common first for better cache performance)
    if data.abilityId then
        offset = writeStringField(buf, offset, FieldIds.ABILITY_ID, data.abilityId)
    end
    
    if data.cooldownRemaining then
        offset = writeFloatField(buf, offset, FieldIds.COOLDOWN_REMAINING, data.cooldownRemaining)
    end
    
    if data.isChanneling ~= nil then
        offset = writeBoolField(buf, offset, FieldIds.IS_CHANNELING, data.isChanneling)
    end
    
    if data.chargesRemaining then
        offset = writeIntField(buf, offset, FieldIds.CHARGES_REMAINING, data.chargesRemaining)
    end
    
    if data.comboCount then
        offset = writeIntField(buf, offset, FieldIds.COMBO_COUNT, data.comboCount)
    end
    
    if data.castTime then
        offset = writeFloatField(buf, offset, FieldIds.CAST_TIME, data.castTime)
    end
    
    if data.damage then
        offset = writeFloatField(buf, offset, FieldIds.DAMAGE, data.damage)
    end
    
    if data.range then
        offset = writeFloatField(buf, offset, FieldIds.RANGE, data.range)
    end
    
    if data.targetPosition then
        offset = writeVector3Field(buf, offset, FieldIds.TARGET_POSITION, data.targetPosition)
    end
    
    if data.casterPosition then
        offset = writeVector3Field(buf, offset, FieldIds.CASTER_POSITION, data.casterPosition)
    end
    
    if data.modifierCount then
        offset = writeIntField(buf, offset, FieldIds.MODIFIER_COUNT, data.modifierCount)
    end
    
    if data.effectCount then
        offset = writeIntField(buf, offset, FieldIds.EFFECT_COUNT, data.effectCount)
    end
    
    -- Write total size at the beginning
    bufferWritei32(buf, 0, offset)
    
    return buf
end

-- OPTIMIZED: Deserialize buffer to ability data
function BufferAbilitySerializer.Deserialize(buf: buffer): AbilityData
    local data: AbilityData = {}
    local totalSize = bufferReadi32(buf, 0)
    local offset = HEADER_SIZE
    
    while offset < totalSize do
        local fieldId = bufferReadu8(buf, offset)
        local typeSize = bufferReadu8(buf, offset + 1)
        offset += FIELD_HEADER_SIZE
        
        if fieldId == FieldIds.ABILITY_ID then
            data.abilityId = buffer.readstring(buf, offset, typeSize)
            offset += typeSize
        elseif fieldId == FieldIds.COOLDOWN_REMAINING then
            data.cooldownRemaining = bufferReadf32(buf, offset)
            offset += FLOAT_SIZE
        elseif fieldId == FieldIds.IS_CHANNELING then
            data.isChanneling = bufferReadu8(buf, offset) == 1
            offset += BOOL_SIZE
        elseif fieldId == FieldIds.CHARGES_REMAINING then
            data.chargesRemaining = bufferReadi32(buf, offset)
            offset += INT_SIZE
        elseif fieldId == FieldIds.COMBO_COUNT then
            data.comboCount = bufferReadi32(buf, offset)
            offset += INT_SIZE
        elseif fieldId == FieldIds.CAST_TIME then
            data.castTime = bufferReadf32(buf, offset)
            offset += FLOAT_SIZE
        elseif fieldId == FieldIds.DAMAGE then
            data.damage = bufferReadf32(buf, offset)
            offset += FLOAT_SIZE
        elseif fieldId == FieldIds.RANGE then
            data.range = bufferReadf32(buf, offset)
            offset += FLOAT_SIZE
        elseif fieldId == FieldIds.TARGET_POSITION then
            local x = bufferReadf32(buf, offset)
            local y = bufferReadf32(buf, offset + 4)
            local z = bufferReadf32(buf, offset + 8)
            data.targetPosition = Vector3.new(x, y, z)
            offset += VECTOR3_SIZE
        elseif fieldId == FieldIds.CASTER_POSITION then
            local x = bufferReadf32(buf, offset)
            local y = bufferReadf32(buf, offset + 4)
            local z = bufferReadf32(buf, offset + 8)
            data.casterPosition = Vector3.new(x, y, z)
            offset += VECTOR3_SIZE
        elseif fieldId == FieldIds.MODIFIER_COUNT then
            data.modifierCount = bufferReadi32(buf, offset)
            offset += INT_SIZE
        elseif fieldId == FieldIds.EFFECT_COUNT then
            data.effectCount = bufferReadi32(buf, offset)
            offset += INT_SIZE
        else
            -- Unknown field, skip
            offset += typeSize
        end
    end
    
    return data
end

-- OPTIMIZED: Batch serialize multiple abilities
function BufferAbilitySerializer.SerializeBatch(abilities: {AbilityData}): buffer
    local totalSize = 4 -- Count header
    
    -- Pre-calculate total size needed
    for _, data in ipairs(abilities) do
        totalSize += estimateSize(data)
    end
    
    local buf = ObjectPool.LargeBufferPool:Get()
    if buffer.len(buf) < totalSize then
        -- Need larger buffer
        buf = bufferCreate(totalSize)
    end
    
    -- Write count
    bufferWritei32(buf, 0, #abilities)
    local offset = 4
    
    -- Serialize each ability
    for _, data in ipairs(abilities) do
        local abilityBuf = BufferAbilitySerializer.Serialize(data)
        local abilitySize = bufferReadi32(abilityBuf, 0)
        
        bufferCopy(buf, offset, abilityBuf, 0, abilitySize)
        offset += abilitySize
        
        -- Return ability buffer to pool
        ObjectPool.AbilityDataBufferPool:Return(abilityBuf)
    end
    
    return buf
end

-- Helper functions for writing different data types
local function writeStringField(buf: buffer, offset: number, fieldId: number, value: string): number
    local len = math.min(#value, STRING_MAX_SIZE)
    bufferWriteu8(buf, offset, fieldId)
    bufferWriteu8(buf, offset + 1, len)
    buffer.writestring(buf, offset + FIELD_HEADER_SIZE, value, len)
    return offset + FIELD_HEADER_SIZE + len
end

local function writeFloatField(buf: buffer, offset: number, fieldId: number, value: number): number
    bufferWriteu8(buf, offset, fieldId)
    bufferWriteu8(buf, offset + 1, FLOAT_SIZE)
    bufferWritef32(buf, offset + FIELD_HEADER_SIZE, value)
    return offset + FIELD_HEADER_SIZE + FLOAT_SIZE
end

local function writeIntField(buf: buffer, offset: number, fieldId: number, value: number): number
    bufferWriteu8(buf, offset, fieldId)
    bufferWriteu8(buf, offset + 1, INT_SIZE)
    bufferWritei32(buf, offset + FIELD_HEADER_SIZE, value)
    return offset + FIELD_HEADER_SIZE + INT_SIZE
end

local function writeBoolField(buf: buffer, offset: number, fieldId: number, value: boolean): number
    bufferWriteu8(buf, offset, fieldId)
    bufferWriteu8(buf, offset + 1, BOOL_SIZE)
    bufferWriteu8(buf, offset + FIELD_HEADER_SIZE, value and 1 or 0)
    return offset + FIELD_HEADER_SIZE + BOOL_SIZE
end

local function writeVector3Field(buf: buffer, offset: number, fieldId: number, value: Vector3): number
    bufferWriteu8(buf, offset, fieldId)
    bufferWriteu8(buf, offset + 1, VECTOR3_SIZE)
    bufferWritef32(buf, offset + FIELD_HEADER_SIZE, value.X)
    bufferWritef32(buf, offset + FIELD_HEADER_SIZE + 4, value.Y)
    bufferWritef32(buf, offset + FIELD_HEADER_SIZE + 8, value.Z)
    return offset + FIELD_HEADER_SIZE + VECTOR3_SIZE
end

-- Estimate serialized size for pre-allocation
local function estimateSize(data: AbilityData): number
    local size = HEADER_SIZE
    
    if data.abilityId then size += FIELD_HEADER_SIZE + math.min(#data.abilityId, STRING_MAX_SIZE) end
    if data.cooldownRemaining then size += FIELD_HEADER_SIZE + FLOAT_SIZE end
    if data.chargesRemaining then size += FIELD_HEADER_SIZE + INT_SIZE end
    if data.castTime then size += FIELD_HEADER_SIZE + FLOAT_SIZE end
    if data.damage then size += FIELD_HEADER_SIZE + FLOAT_SIZE end
    if data.range then size += FIELD_HEADER_SIZE + FLOAT_SIZE end
    if data.isChanneling ~= nil then size += FIELD_HEADER_SIZE + BOOL_SIZE end
    if data.comboCount then size += FIELD_HEADER_SIZE + INT_SIZE end
    if data.modifierCount then size += FIELD_HEADER_SIZE + INT_SIZE end
    if data.targetPosition then size += FIELD_HEADER_SIZE + VECTOR3_SIZE end
    if data.casterPosition then size += FIELD_HEADER_SIZE + VECTOR3_SIZE end
    if data.effectCount then size += FIELD_HEADER_SIZE + INT_SIZE end
    
    return size
end

return BufferAbilitySerializer
