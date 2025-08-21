--!strict
-- UpdateScheduler: high-performance frame scheduler with parallel support

local RunService = game:GetService("RunService")

type Callback = (dt: number) -> ()
type RegisterOpts = { parallelSafe: boolean? }

local UpdateScheduler = {}
UpdateScheduler.__index = UpdateScheduler

function UpdateScheduler.New(interval: number?)
    local self = setmetatable({}, UpdateScheduler)

    self._interval = interval or 1/30 -- 0 = variable step
    self._accum = 0

    -- Pre-allocated tables for maximum performance
    local initialCapacity = 32
    
    -- Parallel-safe callbacks (no Instance access) 
    self._parCallbacks = table.create(initialCapacity) :: { Callback }
    self._parIds = {} :: { [string]: number } -- id -> index (can't pre-allocate dict)
    self._parIdsByIndex = table.create(initialCapacity) :: { [number]: string } -- index -> id

    -- Synchronized (main thread) callbacks (can touch Instances)
    self._syncCallbacks = table.create(initialCapacity) :: { Callback }
    self._syncIds = {} :: { [string]: number } -- (can't pre-allocate dict)
    self._syncIdsByIndex = table.create(initialCapacity) :: { [number]: string }

    self._running = false
    self._connection = nil :: RBXScriptConnection?
    self._useParallel = ((RunService.Heartbeat :: any).Connect ~= nil)

    return self
end

-- Register a callback. Set opts.parallelSafe = true only if the callback never touches Instances.
function UpdateScheduler:Register(id: string, callback: Callback, opts: RegisterOpts?)
    -- Replace existing
    local idx = self._parIds[id]
    if idx then
        self._parCallbacks[idx] = callback
        if not self._running then self:Start() end
        return
    end
    idx = self._syncIds[id]
    if idx then
        self._syncCallbacks[idx] = callback
        if not self._running then self:Start() end
        return
    end

    local asParallel = (opts and opts.parallelSafe) == true
    if asParallel then
        local n = #self._parCallbacks + 1
        self._parCallbacks[n] = callback
        self._parIds[id] = n
        self._parIdsByIndex[n] = id
    else
        local n = #self._syncCallbacks + 1
        self._syncCallbacks[n] = callback
        self._syncIds[id] = n
        self._syncIdsByIndex[n] = id
    end

    if not self._running then
        self:Start()
    end
end

function UpdateScheduler:Unregister(id: string)
    local idx = self._parIds[id]
    if idx then
        local arr = self._parCallbacks
        local idsByIndex = self._parIdsByIndex
        local last = #arr
        if last > 0 then
            if idx ~= last then
                arr[idx] = arr[last]
                local lastId = idsByIndex[last]
                idsByIndex[idx] = lastId
                self._parIds[lastId] = idx
            end
            arr[last] = nil
            idsByIndex[last] = nil
        end
        self._parIds[id] = nil
    else
        idx = self._syncIds[id]
        if idx then
            local arr = self._syncCallbacks
            local idsByIndex = self._syncIdsByIndex
            local last = #arr
            if last > 0 then
                if idx ~= last then
                    arr[idx] = arr[last]
                    local lastId = idsByIndex[last]
                    idsByIndex[idx] = lastId
                    self._syncIds[lastId] = idx
                end
                arr[last] = nil
                idsByIndex[last] = nil
            end
            self._syncIds[id] = nil
        end
    end

    if #self._parCallbacks + #self._syncCallbacks == 0 then
        self:Stop()
    end
end

function UpdateScheduler:SetInterval(interval: number)
    self._interval = if interval > 0 then interval else 0
end

function UpdateScheduler:Start()
    if self._running then return end
    self._running = true

    if self._useParallel then
        self._connection = RunService.Heartbeat:Connect(function(dt: number)
            local interval = self._interval
            if interval == 0 then
                -- variable step
                local pcbs = self._parCallbacks
                local pn = #pcbs
                for i = 1, pn do
                    pcbs[i](dt)
                end

                local scbs = self._syncCallbacks
                local sn = #scbs
                if sn > 0 then
                    for i = 1, sn do
                        scbs[i](dt)
                    end
                end
                return
            end

            -- fixed step
            local accum = self._accum + dt
            local steps = if interval > 0 then math.floor(accum / interval) else 0
            if steps > 0 then
                accum -= steps * interval
                local pcbs = self._parCallbacks
                local scbs = self._syncCallbacks
                local pn = #pcbs
                local sn = #scbs
                for _ = 1, steps do
                    for i = 1, pn do
                        pcbs[i](interval)
                    end
                    if sn > 0 then
                            for i = 1, sn do
                            scbs[i](interval)
                        end
                        end
                end
            end
            self._accum = accum
        end)
    else
        -- Fallback if Connect isn't available (runs everything synchronized)
        self._connection = RunService.Heartbeat:Connect(function(dt: number)
            local interval = self._interval
            if interval == 0 then
                -- Run sync first (safe), then parallel-safe (still fine here)
                local scbs = self._syncCallbacks
                local sn = #scbs
                for i = 1, sn do
                    scbs[i](dt)
                end
                local pcbs = self._parCallbacks
                local pn = #pcbs
                for i = 1, pn do
                    pcbs[i](dt)
                end
                return
            end

            local accum = self._accum + dt
            local steps = if interval > 0 then math.floor(accum / interval) else 0
            if steps > 0 then
                accum -= steps * interval
                local scbs = self._syncCallbacks
                local pcbs = self._parCallbacks
                local sn = #scbs
                local pn = #pcbs
                for _ = 1, steps do
                    for i = 1, sn do scbs[i](interval) end
                    for i = 1, pn do pcbs[i](interval) end
                end
            end
            self._accum = accum
        end)
    end
end

-- Subscribe a single callback; set parallelSafe=true if it never touches Instances.
function UpdateScheduler:OnStep(callback: Callback, parallelSafe: boolean?)
    local id = tostring(callback)
    self:Register(id, callback, { parallelSafe = parallelSafe == true })
    return function()
        self:Unregister(id)
    end
end

function UpdateScheduler:Stop()
    if not self._running then return end
    self._running = false
    local conn = self._connection
    if conn then
        conn:Disconnect()
        self._connection = nil
    end
end

function UpdateScheduler:Destroy()
    self:Stop()
    table.clear(self._parCallbacks)
    table.clear(self._parIds)
    table.clear(self._parIdsByIndex)
    table.clear(self._syncCallbacks)
    table.clear(self._syncIds)
    table.clear(self._syncIdsByIndex)
end

-- Global instance
local globalScheduler = UpdateScheduler.New()

return {
    New = UpdateScheduler.New,
    Global = globalScheduler,
}
