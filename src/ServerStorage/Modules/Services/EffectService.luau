--!strict
-- EffectService: scalable, optimized status/buff/debuff manager

local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local EffectTypes = require(game.ServerStorage.Modules.Types.EffectTypes)
local EffectRegistry = require(game.ServerStorage.Modules.registery.Effects)

export type EffectId = Enums.EffectId
export type EffectDef = EffectTypes.EffectDef
export type ActiveEffect = EffectTypes.ActiveEffect
export type PerCharacterEffects = EffectTypes.PerCharacterEffects
export type Modifiers = EffectTypes.Modifiers

local EffectService = {}
EffectService.__index = EffectService

function EffectService.New()
    local self = setmetatable({}, EffectService)
    self._effects = {} :: {[number]: PerCharacterEffects}
    self._iterList = {} :: {[number]: {EffectId}}
    self._iterIndex = {} :: {[number]: {[EffectId]: number}}
    return self
end

function EffectService:Register(def: EffectDef)
	-- This is now handled by the static registry, but kept for backward compatibility
	warn("EffectService:Register is deprecated. Effects are now auto-discovered from registry modules.")
end

function EffectService:_getBucket(playerId: number): PerCharacterEffects
    local b: PerCharacterEffects? = self._effects[playerId]
    if not b then
        b = { byId = {} }
        self._effects[playerId] = b
    end
    -- ensure iteration arrays exist
    if not self._iterList[playerId] then
        self._iterList[playerId] = {}
        self._iterIndex[playerId] = {} :: {[EffectId]: number}
    end
    return b :: any
end

function EffectService:Apply(character: any, effectOrId: EffectDef | EffectId, ctxExtra: {[string]: any}?)
    local def: EffectDef
    local id: EffectId
	
	if type(effectOrId) == "string" then
		-- Called with effect ID
		id = effectOrId :: EffectId
		local foundDef: EffectDef? = EffectRegistry.GetEffect(id)
		if not foundDef then return end
		def = foundDef
	else
		-- Called with effect definition object
		def = effectOrId :: EffectDef
		id = def.id
	end
	
	local playerId: number = character.PlayerId or (character.Player and character.Player.UserId) or character.UserId or 0
	local player: Player = character.Player
	local bucket: PerCharacterEffects = self:_getBucket(playerId)
	local now: number = time()

	local existing: ActiveEffect? = bucket.byId[id]
	local durationOverride: number? = ctxExtra and ctxExtra.duration or nil
    if existing then
        existing.stacks = math.min((def.maxStacks or 1), existing.stacks + 1)
        if durationOverride or def.duration then
            existing.expiresAt = (durationOverride and (now + durationOverride)) or (def.duration and (now + def.duration))
        end
        -- reset tick accumulator so stacked applications feel responsive
        existing._tickAccum = 0
    else
        local active: ActiveEffect = {
            id = id,
            stacks = 1,
            expiresAt = (durationOverride and (now + durationOverride)) or (def.duration and (now + def.duration)) or nil,
            extra = ctxExtra,
            def = def,
            _tickAccum = 0,
        } :: any
		bucket.byId[id] = active

        -- maintain int-index iteration structures
        local list = self._iterList[playerId]
        local indexMap = self._iterIndex[playerId]
        table.insert(list, id)
        indexMap[id] = #list

        if def.onApply then
            def.onApply({ player = player, character = character, extra = ctxExtra })
        end
	end
end

function EffectService:_swapRemove(playerId: number, id: EffectId)
    local list = self._iterList[playerId]
    local indexMap = self._iterIndex[playerId]
    local idx = indexMap[id]
    if idx then
        local last = #list
        local lastId = list[last]
        if lastId then
            list[idx] = lastId
            indexMap[lastId] = idx
            list[last] = nil
        end
        indexMap[id] = nil
    end
end

function EffectService:Remove(character: any, id: EffectId)
    local playerId: number = character.PlayerId or character.Player.UserId
    local player: Player = character.Player
    local bucket: PerCharacterEffects = self:_getBucket(playerId)
    local active: ActiveEffect? = bucket.byId[id]
    if not active then return end
    if active.def.onRemove then
        active.def.onRemove({ player = player, character = character, extra = active.extra })
    end

    self:_swapRemove(playerId, id)
    bucket.byId[id] = nil
end

function EffectService:Update(character)
	-- Deprecated: expiry is handled during Tick to avoid double iteration per frame.
end

function EffectService:Tick(character, dt: number)
    local playerId = character.PlayerId
    local list = self._iterList[playerId]
    if not list or #list == 0 then return end

    local player = character.Player
    if character.StateManager and character.StateManager:Get("IsDead") then
        return
    end

    local bucket = self._effects[playerId]
    if not bucket then return end

    local byId = bucket.byId
    local now = time()

    local toRemove = table.create(#list) :: {EffectId}
    local rc = 0

    -- Reverse numeric for-loop; no in-loop removals (deferred).
    for i = #list, 1, -1 do
        local id = list[i]
        local active = byId[id]
        if active then
            local def = active.def
            local expiresAt = active.expiresAt
            if expiresAt and now >= expiresAt then
                local onRemove = def.onRemove
                if onRemove then
                    local ok, err = pcall(onRemove, { player = player, character = character, extra = active.extra })
                    if not ok then warn("Effect " .. tostring(id) .. " removal failed: " .. tostring(err)) end
                end
                rc += 1
                toRemove[rc] = id
            else
                local onTick = def.onTick
                if onTick then
                    -- Optional fixed tick interval per effect
                    local interval = (def.tickInterval or 0)
                    if interval > 0 then
                        active._tickAccum = (active._tickAccum or 0) + dt
                        while active._tickAccum >= interval do
                            active._tickAccum -= interval
                            local ok, err = pcall(onTick, { player = player, character = character, extra = active.extra }, interval, active.stacks)
                            if not ok then
                                warn("Effect " .. tostring(id) .. " tick failed: " .. tostring(err))
                                break
                            end
                        end
                    else
                        -- If the effect will expire within this frame, only apply the remaining fraction of dt
                        local effDt = dt
                        if active.expiresAt then
                            local tprev = now - dt
                            local remains = active.expiresAt - tprev
                            if remains < dt then
                                effDt = math.max(0, remains)
                            end
                        end
                        if effDt <= 0 then
                            -- Nothing to apply this frame; let removal happen next iteration
                        else
                            local ok, err = pcall(onTick, { player = player, character = character, extra = active.extra }, effDt, active.stacks)
                            if not ok then warn("Effect " .. tostring(id) .. " tick failed: " .. tostring(err)) end
                        end
                    end
                end
            end
        else
            rc += 1
            toRemove[rc] = id
        end
    end

    if rc > 0 then
        local indexMap = self._iterIndex[playerId]
        -- O(1) swap-remove per id
        for j = 1, rc do
            local rid = toRemove[j]
            local idx = indexMap[rid]
            if idx then
                local last = #list
                local lastId = list[last]
                if lastId then
                    list[idx] = lastId
                    indexMap[lastId] = idx
                    list[last] = nil
                end
                indexMap[rid] = nil
            end
            byId[rid] = nil
        end
    end
end

function EffectService:GetStacks(playerId: number, id: EffectId): number
	local bucket = self._effects[playerId]
	if not bucket then return 0 end
	local active = bucket.byId[id]
	return active and active.stacks or 0
end

function EffectService:ComputeModifiers(character): Modifiers
    local mods: Modifiers = {}
    local playerId = character.PlayerId
    local bucket = self._effects[playerId]
    if not bucket then return mods end

    local list = self._iterList[playerId]
    if not list or #list == 0 then return mods end

    local byId = bucket.byId
    for i = 1, #list do
        local id = list[i]
        local active = byId[id]
        if active then
            local compute = active.def.compute
            if compute then
                compute({ player = character.Player, character = character, extra = active.extra }, mods, active.stacks)
            end
        end
    end
    return mods
end

-- Clears all active effects for a character (used on death/cleanup)
function EffectService:ClearAll(character)
    local playerId = character.PlayerId or (character.Player and character.Player.UserId)
    if not playerId then return end
    local bucket = self._effects[playerId]
    if not bucket then return end

    local list = self._iterList[playerId]
    local indexMap = self._iterIndex[playerId]
    if not list or not indexMap then return end

    local byId = bucket.byId
    local player = character.Player

    -- Call onRemove for all active effects, then clear structures
    for i = #list, 1, -1 do
        local id = list[i]
        local active = byId[id]
        if active then
            local def = active.def
            local onRemove = def and def.onRemove
            if onRemove then
                local ok, err = pcall(onRemove, { player = player, character = character, extra = active.extra })
                if not ok then
                    warn("Effect " .. tostring(id) .. " removal failed: " .. tostring(err))
                end
            end
        end
        byId[id] = nil
        indexMap[id] = nil
        list[i] = nil
    end
end

return EffectService
