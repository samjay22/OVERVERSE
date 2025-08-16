--!strict
-- CombatEventBus: typed event bus for combat events

local EventBus = require(game.ServerStorage.Modules.Utilities.EventBus)
local CombatEventTypes = require(game.ServerStorage.Modules.Types.CombatEventTypes)

export type ICombatEventBus = CombatEventTypes.ICombatEventBus

local CombatEventBus = {}
CombatEventBus.__index = CombatEventBus

function CombatEventBus.New(): ICombatEventBus
    local self = setmetatable({}, CombatEventBus)
    local bus = EventBus.New()
    
    -- Request-side events (from client/external to combat system)
    self.AttackRequested = bus:Get("AttackRequested")
    self.BlockRequested = bus:Get("BlockRequested")
    self.DamageRequested = bus:Get("DamageRequested")
    
    -- Response-side events (from combat system to listeners)
    self.AttackPerformed = bus:Get("AttackPerformed")
    self.BlockStateChanged = bus:Get("BlockStateChanged")
    self.DamageApplied = bus:Get("DamageApplied")
    self.GuardChanged = bus:Get("GuardChanged")
    self.GuardBroken = bus:Get("GuardBroken")
    self.ComboChanged = bus:Get("ComboChanged")
    self.Tick = bus:Get("Tick")
    
    self._bus = bus
    
    return self :: any
end

function CombatEventBus:Destroy()
    if self._bus then
        self._bus:Destroy()
    end
end

return CombatEventBus
