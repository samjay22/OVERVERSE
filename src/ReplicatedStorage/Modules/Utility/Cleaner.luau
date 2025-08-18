--!strict
--!optimize 2

--[[

    Managing cleanup tasks with advanced features.
    Provides automatic resource management, task prioritization, and comprehensive cleanup.
    
    @author: Zach
    @version: 2.0.0
]]

--// Services \\--
    local RunService = game:GetService("RunService")

--// Types \\--
export type CleanupFunction = () -> ()
export type CleanupPriority = "High" | "Normal" | "Low"

export type CleanerHandle = {
    Disconnect: () -> (),
    SetPriority: (self: CleanerHandle, priority: CleanupPriority) -> CleanerHandle,
    GetPriority: (self: CleanerHandle) -> CleanupPriority
}

export type CleanerEntry = {
    cleanup: CleanupFunction,
    priority: CleanupPriority,
    key: any
}

export type CleanerState = {
    _entries: {[any]: CleanerEntry},
    _destroyed: boolean,
    _cleanupInProgress: boolean,
    _parent: CleanerState?,
    _children: {[CleanerState]: true},
    _stats: {
        totalAdded: number,
        totalCleaned: number,
        lastCleanupTime: number?
    }
}

export type Cleaner = {
    new: () -> Cleaner,
    Add: (self: Cleaner, object: any, priority: CleanupPriority?) -> (any, CleanerHandle),
    AddPromise: (self: Cleaner, promise: {cancel: () -> ()}, priority: CleanupPriority?) -> ({cancel: () -> ()}, CleanerHandle),
    AddCleaner: (self: Cleaner, cleaner: {Destroy: () -> ()}, priority: CleanupPriority?) -> ({Destroy: () -> ()}, CleanerHandle),
    Connect: (self: Cleaner, signal: RBXScriptSignal, fn: (...any) -> (), priority: CleanupPriority?) -> RBXScriptConnection,
    CreateChild: (self: Cleaner) -> Cleaner,
    Destroy: (self: Cleaner) -> (),
    Clear: (self: Cleaner) -> (),
    IsDestroyed: (self: Cleaner) -> boolean,
    GetStats: (self: Cleaner) -> {[string]: any},
    RemoveObject: (self: Cleaner, object: any) -> boolean
}

--// Constants \\--
local PRIORITY_LEVELS = {
    High = 1,
    Normal = 2,
    Low = 3
}

--// Cached Functions \\--
local tableInsert = table.insert
local tableSort = table.sort
local tableClear = table.clear
local typeof = typeof
local type = type
local pairs = pairs
local pcall = pcall
local tick = tick
local next = next

--// Helper Functions \\--
local function sortByPriority(a: CleanerEntry, b: CleanerEntry): boolean
    return PRIORITY_LEVELS[a.priority] < PRIORITY_LEVELS[b.priority]
end

local function getCleanupFunction(object: any): CleanupFunction?
    local objectType = typeof(object)
    
    if type(object) == "function" then
        return object
    end
    
    if objectType == "RBXScriptConnection" then
        return function()
            if not object.Connected then return end
            object:Disconnect()
        end
    end
    
    if objectType == "Instance" then
        return function()
            if not object:IsDescendantOf(game) then return end
            object:Destroy()
        end
    end
    
    if type(object) ~= "table" then return nil end
    
    if type(object.Destroy) == "function" then
        return function() object:Destroy() end
    end
    
    if type(object.destroy) == "function" then
        return function() object:destroy() end
    end
    
    if type(object.Disconnect) == "function" then
        return function() object:Disconnect() end
    end
    
    if type(object.disconnect) == "function" then
        return function() object:disconnect() end
    end
    
    if type(object.cancel) == "function" then
        return function() object:cancel() end
    end
    
    return nil
end

--// Cleaner Class \\--
local Cleaner = {}
Cleaner.__index = Cleaner

function Cleaner.new(): Cleaner
    local self = setmetatable({}, Cleaner)
    
    self._entries = {}
    self._destroyed = false
    self._cleanupInProgress = false
    self._parent = nil
    self._children = {}
    self._stats = {
        totalAdded = 0,
        totalCleaned = 0,
        lastCleanupTime = nil
    }
    
    return self :: any
end

local function createHandle(self: CleanerState, key: any, entry: CleanerEntry): CleanerHandle
    return {
        Disconnect = function()
            if not self._entries[key] then return end
            self._entries[key] = nil
        end,
        
        SetPriority = function(_, priority: CleanupPriority)
            if not PRIORITY_LEVELS[priority] then
                error("Invalid priority level: " .. tostring(priority))
                return _
            end
            
            if not self._entries[key] then return _ end
            
            self._entries[key].priority = priority
            return _
        end,
        
        GetPriority = function()
            if not self._entries[key] then return "Normal" end
            return self._entries[key].priority
        end
    }
end

function Cleaner:Add(object: any, priority: CleanupPriority?): (any, CleanerHandle)
    if self._destroyed then
        error("Cannot add to a destroyed Cleaner")
        return object, { 
            Disconnect = function() end,
            SetPriority = function(self) return self end,
            GetPriority = function() return "Normal" end
        }
    end
    
    local cleanupFunc = getCleanupFunction(object)
    if not cleanupFunc then
        error("Cleaner:Add: Unsupported type " .. typeof(object))
        return object, { 
            Disconnect = function() end,
            SetPriority = function(self) return self end,
            GetPriority = function() return "Normal" end
        }
    end
    
    priority = priority or "Normal"
    if not PRIORITY_LEVELS[priority] then
        error("Invalid priority level: " .. tostring(priority))
        return object, { 
            Disconnect = function() end,
            SetPriority = function(self) return self end,
            GetPriority = function() return "Normal" end
        }
    end
    
    local key = {}
    local entry = {
        cleanup = cleanupFunc,
        priority = priority,
        key = key
    }
    
    self._entries[key] = entry
    self._stats.totalAdded += 1
    
    if self._destroyed then
        pcall(cleanupFunc)
    end
    
    return object, createHandle(self, key, entry)
end

function Cleaner:AddPromise(promise: {cancel: () -> ()}, priority: CleanupPriority?): ({cancel: () -> ()}, CleanerHandle)
    if type(promise) ~= "table" or type(promise.cancel) ~= "function" then
        error("Cleaner:AddPromise: Expected promise with cancel method")
        return promise, { 
            Disconnect = function() end,
            SetPriority = function(self) return self end,
            GetPriority = function() return "Normal" end
        }
    end
    
    return self:Add(promise, priority)
end

function Cleaner:AddCleaner(cleaner: {Destroy: () -> ()}, priority: CleanupPriority?): ({Destroy: () -> ()}, CleanerHandle)
    if type(cleaner) ~= "table" or type(cleaner.Destroy) ~= "function" then
        error("Cleaner:AddCleaner: Expected a cleaner-like table with a Destroy method")
        return cleaner, { 
            Disconnect = function() end,
            SetPriority = function(self) return self end,
            GetPriority = function() return "Normal" end
        }
    end
    
    return self:Add(cleaner, priority)
end

function Cleaner:Connect(signal: RBXScriptSignal, fn: (...any) -> (), priority: CleanupPriority?): RBXScriptConnection
    if typeof(signal) ~= "RBXScriptSignal" then
        error("Cleaner:Connect: Expected RBXScriptSignal, got " .. typeof(signal))
        return nil :: any
    end
    
    if type(fn) ~= "function" then
        error("Cleaner:Connect: Expected function callback")
        return nil :: any
    end
    
    local connection = signal:Connect(fn)
    return self:Add(connection, priority)
end

function Cleaner:CreateChild(): Cleaner
    if self._destroyed then
        error("Cannot create child from a destroyed Cleaner")
        return nil :: any
    end
    
    local child = Cleaner.new()
    child._parent = self
    self._children[child] = true
    
    return child
end

function Cleaner:RemoveObject(object: any): boolean
    if self._destroyed then return false end
    if not object then return false end
    
    for key, entry in pairs(self._entries) do
        if entry.cleanup == object or getCleanupFunction(object) == entry.cleanup then
            self._entries[key] = nil
            return true
        end
    end
    
    return false
end

function Cleaner:Clear()
    if self._cleanupInProgress then return end
    if self._destroyed and next(self._entries) == nil and next(self._children) == nil then return end
    
    self._cleanupInProgress = true

    for child in pairs(self._children) do
        child:Destroy()
        self._children[child] = nil
    end

    local sortedEntries = {}
    for _, entry in pairs(self._entries) do
        tableInsert(sortedEntries, entry)
    end
    
    if #sortedEntries > 0 then
        tableSort(sortedEntries, sortByPriority)

        for _, entry in ipairs(sortedEntries) do
            pcall(entry.cleanup)
            self._entries[entry.key] = nil
            self._stats.totalCleaned += 1
        end
    end
    
    self._stats.lastCleanupTime = tick()
    self._cleanupInProgress = false
end

function Cleaner:Destroy()
    if self._destroyed then return end
    
    self._destroyed = true

    if self._parent and not self._parent._destroyed then
        self._parent._children[self] = nil
    end
    
    self:Clear()
end

function Cleaner:IsDestroyed(): boolean
    return self._destroyed
end

function Cleaner:GetStats(): {[string]: any}
    local stats = {
        totalAdded = self._stats.totalAdded,
        totalCleaned = self._stats.totalCleaned,
        lastCleanupTime = self._stats.lastCleanupTime,
        activeEntries = 0,
        childCleaners = 0,
        isDestroyed = self._destroyed
    }
    
    for _ in pairs(self._entries) do
        stats.activeEntries += 1
    end
    
    for _ in pairs(self._children) do
        stats.childCleaners += 1
    end
    
    return stats
end

return table.freeze(Cleaner)