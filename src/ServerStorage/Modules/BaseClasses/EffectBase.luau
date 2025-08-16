--!strict
-- Metatable-based base classes for Effects: Buff, Debuff, DoT, HoT

local EffectTypes = require(game.ServerStorage.Modules.Types.EffectTypes)

export type EffectDef = EffectTypes.EffectDef
export type EffectContext = EffectTypes.EffectContext
export type Modifiers = EffectTypes.Modifiers

-- Base "class" --------------------------------------------------------------
local Base = {}
Base.__index = Base

function Base:_ensure(def: EffectDef): EffectDef
    if not def.onApply then def.onApply = function(_ctx: EffectContext) end end
    if not def.onRemove then def.onRemove = function(_ctx: EffectContext) end end
    return def
end

function Base:define(spec: any): EffectDef
    spec.category = spec.category or "Other"
    return self:_ensure(spec :: EffectDef)
end

-- Buff ----------------------------------------------------------------------
local Buff = setmetatable({}, Base)
Buff.__index = Buff

function Buff:define(spec: any): EffectDef
    spec.isBuff = (spec.isBuff ~= false)
    spec.category = spec.category or "Buff"
    return Base.define(self, spec)
end

-- Debuff --------------------------------------------------------------------
local Debuff = setmetatable({}, Base)
Debuff.__index = Debuff

function Debuff:define(spec: any): EffectDef
    spec.isBuff = false
    spec.category = spec.category or "Debuff"
    return Base.define(self, spec)
end

-- DoT (Damage over Time) ----------------------------------------------------
-- Supported extra fields for callers:
--   ctx.extra.dps: number                -- damage per second
--   ctx.extra.total: number              -- total damage over full duration
-- Optional defaults (per stack) on spec:
--   defaultDpsPerStack: number?
--   defaultTotalPerStack: number?
local DoT = setmetatable({}, Debuff)
DoT.__index = DoT

function DoT:define(spec: any): EffectDef
    spec.tickInterval = spec.tickInterval or 0
    local userTick = spec.onTick
    spec.category = spec.category or "DoT"

    -- Capture and strip builder-only defaults so they don't leak into def
    local defaultDpsPerStack: number? = spec.defaultDpsPerStack
    local defaultTotalPerStack: number? = spec.defaultTotalPerStack
    spec.defaultDpsPerStack = nil
    spec.defaultTotalPerStack = nil

    if not userTick then
        spec.onTick = function(ctx: EffectContext, dt: number, stacks: number)
            local extra: any = ctx.extra
            local dps: number? = nil
            if extra then
                if typeof(extra.dps) == "number" then
                    dps = extra.dps
                elseif typeof(extra.total) == "number" then
                    local duration: number = ((extra.duration :: any) or spec.duration or 0)
                    if duration > 0 then
                        dps = (extra.total :: number) / duration
                    end
                elseif typeof(extra.damage) == "number" then
                    -- Treat 'damage' as total damage over duration
                    local duration: number = ((extra.duration :: any) or spec.duration or 0)
                    if duration > 0 then
                        dps = (extra.damage :: number) / duration
                    end
                elseif typeof(extra.amount) == "number" then
                    -- Alias: amount as total over duration
                    local duration: number = ((extra.duration :: any) or spec.duration or 0)
                    if duration > 0 then
                        dps = (extra.amount :: number) / duration
                    end
                end
            end
            if not dps then
                if typeof(defaultDpsPerStack) == "number" then
                    dps = defaultDpsPerStack
                elseif typeof(defaultTotalPerStack) == "number" then
                    local duration: number = ((extra and extra.duration) or spec.duration or 0)
                    if duration > 0 then
                        dps = (defaultTotalPerStack :: number) / duration
                    end
                end
            end
            if not dps or dps == 0 then return end
            local s = math.max(1, stacks or 1)
            -- Apply per-second damage scaled by dt and stacks
            local damage = (dps * dt) * s
            local CombatComponent = require(game.ServerStorage.Modules.Components.CombatComponent)
            CombatComponent.TakeDamage(ctx.character, damage, false)
        end
    end

    return Debuff.define(self, spec)
end

-- HoT (Heal over Time) ------------------------------------------------------
-- Supported extra fields for callers:
--   ctx.extra.amountPerSecond: number    -- heal per second
--   ctx.extra.total: number              -- total healing over full duration
-- Optional defaults (per stack) on spec:
--   defaultAmountPerSecondPerStack: number?
--   defaultTotalPerStack: number?
local HoT = setmetatable({}, Buff)
HoT.__index = HoT

function HoT:define(spec: any): EffectDef
    spec.tickInterval = spec.tickInterval or 0
    local userTick = spec.onTick
    spec.category = spec.category or "HoT"

    local defaultAPSPerStack: number? = spec.defaultAmountPerSecondPerStack
    local defaultTotalPerStack: number? = spec.defaultTotalPerStack
    spec.defaultAmountPerSecondPerStack = nil
    spec.defaultTotalPerStack = nil

    if not userTick then
        spec.onTick = function(ctx: EffectContext, dt: number, stacks: number)
            local character = ctx.character
            local extra: any = ctx.extra
            local aps: number? = nil
            if extra then
                if typeof(extra.amountPerSecond) == "number" then
                    aps = extra.amountPerSecond
                elseif typeof(extra.total) == "number" then
                    local duration: number = ((extra.duration :: any) or spec.duration or 0)
                    if duration > 0 then
                        aps = (extra.total :: number) / duration
                    end
                elseif typeof(extra.heal) == "number" then
                    -- Treat 'heal' as total over duration
                    local duration: number = ((extra.duration :: any) or spec.duration or 0)
                    if duration > 0 then
                        aps = (extra.heal :: number) / duration
                    end
                elseif typeof(extra.amount) == "number" then
                    local duration: number = ((extra.duration :: any) or spec.duration or 0)
                    if duration > 0 then
                        aps = (extra.amount :: number) / duration
                    end
                end
            end
            if not aps then
                if typeof(defaultAPSPerStack) == "number" then
                    aps = defaultAPSPerStack
                elseif typeof(defaultTotalPerStack) == "number" then
                    local duration: number = ((extra and extra.duration) or spec.duration or 0)
                    if duration > 0 then
                        aps = (defaultTotalPerStack :: number) / duration
                    end
                end
            end
            if not aps or aps == 0 then return end
            local s = math.max(1, stacks or 1)
            -- Apply per-second heal scaled by dt and stacks
            local heal = (aps * dt) * s
            local sm = character.StateManager
            local current: number = sm:Get("Health")
            local maxHealth: number = sm:Get("MaxHealth") or 100
            sm:Set("Health", math.clamp(current + heal, 0, maxHealth))
        end
    end

    return Buff.define(self, spec)
end

return {
    Base = Base,
    Buff = Buff,
    Debuff = Debuff,
    DoT = DoT,
    HoT = HoT,
}
