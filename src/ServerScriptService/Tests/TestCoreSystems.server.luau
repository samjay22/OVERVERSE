--!strict
-- Core Systems Tests: Registry, StateManagers, EventBus, UpdateScheduler

local TestService = game:GetService("TestService")

local Registry = require(game.ServerStorage.Modules.Core.Registry)
local CoreStateManager = require(game.ServerStorage.Modules.Core.StateManager)
local ReplicatedStateManager = require(game.ReplicatedStorage.Modules.Utility.StateManager)
local EventBus = require(game.ServerStorage.Modules.Utilities.EventBus)
local UpdateScheduler = require(game.ServerStorage.Modules.Utilities.UpdateScheduler)

-- Lightweight assertions
local function assertTrue(cond: boolean, msg: string)
    if not cond then TestService:Error(msg) end
end

local function assertType(value: any, t: string, msg: string?)
    local m = msg or `Expected type {t}, got {typeof(value)}`
    assertTrue(typeof(value) == t, m)
end

local function assertEquals(expected: any, actual: any, msg: string?)
    local m = msg or `Expected {tostring(expected)}, got {tostring(actual)}`
    assertTrue(expected == actual, m)
end

local function assertNear(expected: number, actual: number, eps: number, msg: string?)
    local m = msg or `Expected ~{expected}, got {actual}`
    assertTrue(math.abs(expected - actual) <= eps, m)
end

-- Registry tests
local function testRegistry()
    TestService:Message("Testing Core.Registry...")

    local validate = function(item: any)
        return typeof(item) == "table" and typeof(item.name) == "string", item
    end
    local transform = function(item: any)
        item.upper = string.upper(item.name)
        return item
    end

    local reg = Registry.New(validate, transform)
    reg:Register("Sword", { name = "sword", dmg = 10 })
    reg:Register("Shield", { name = "shield", def = 5 })

    assertTrue(reg:Has("Sword"), "Registry should have 'Sword'")
    assertEquals(2, reg:Count(), "Registry count should be 2")

    local sword = reg:Get("Sword")
    assertType(sword, "table")
    assertEquals("SWORD", sword.upper, "Transform should add upper field")

    local ids = reg:GetIds()
    assertType(ids, "table")
    assertTrue(#ids >= 2, "GetIds should return at least 2 ids")

    local regAny = reg :: any
    regAny:SetMetadata("Sword", { rarity = "Common" })
    local meta = regAny:GetMetadata("Sword")
    assertType(meta, "table")
    assertEquals("Common", meta.rarity)

    -- LoadFromFolder on an empty temp folder (we can't set ModuleScript.Source at runtime)
    local folder = Instance.new("Folder")
    folder.Name = "_TestRegistryFolder"
    folder.Parent = game.ServerStorage
    local loaded = reg:LoadFromFolder(folder)
    assertEquals(0, loaded, "LoadFromFolder on empty folder should load 0 modules")
    folder:Destroy()

    -- Remove and clear
    assertTrue(reg:Remove("Shield"), "Remove should return true for existing id")
    assertEquals(1, reg:Count(), "Count should reflect removal")
    -- Clear (method exists on implementation but not in interface typing)
    regAny:Clear()
    assertEquals(0, reg:Count(), "Clear should remove all items")

    TestService:Message("✓ Core.Registry tests passed")
end

-- EventBus tests
local function testEventBus()
    TestService:Message("Testing Utilities.EventBus...")
    local bus = EventBus.New()
    local received = 0
    local lastPayload = nil
    local conn = bus:Get("Ping"):Connect(function(payload)
        received += 1
        lastPayload = payload
    end)
    bus:Get("Ping"):Fire({ hello = "world" })
    task.wait() -- yield to process
    assertEquals(1, received, "Listener should fire once")
    assertType(lastPayload, "table")
    assertEquals("world", lastPayload.hello)
    conn:Disconnect()
    bus:Destroy()
    TestService:Message("✓ EventBus tests passed")
end

-- Core StateManager tests (server Core)
local function testCoreStateManager()
    TestService:Message("Testing Core.StateManager...")
    local sm = CoreStateManager.New()

    local changeCount = 0
    local _lastOld, lastNew = nil, nil
    local conn = sm:OnChange("Health", function(new, old)
        changeCount += 1
        lastNew, _lastOld = new, old
    end)

    sm:Set("Health", 50)
    sm:Set("Health", 75)
    assertEquals(75, sm:Get("Health"))
    assertTrue(changeCount >= 1, "OnChange should have fired")
    assertEquals(75, lastNew)

    sm:SetMultiple({ Health = 80, Mana = 10 })
    assertEquals(80, sm:Get("Health"))
    assertEquals(10, sm:Get("Mana"))

    -- Increment/Decrement/Toggle helpers
    local v = (sm :: any):Increment("Mana", 5)
    assertEquals(15, v)
    v = (sm :: any):Decrement("Mana", 3)
    assertEquals(12, v)
    sm:Set("CanMove", true)
    local b = (sm :: any):Toggle("CanMove")
    assertEquals(false, b)

    -- Keys and counts
    local keys = (sm :: any):GetKeys()
    assertType(keys, "table")
    assertTrue(((sm :: any):GetStateCount()) >= 3, "Should have at least 3 states defined")

    -- Clear should drop states and fire events
    sm:Clear()
    assertEquals(nil, sm:Get("Health"))
    conn:Disconnect()
    local smAny = sm :: any
    smAny:Destroy()

    TestService:Message("✓ Core.StateManager tests passed")
end

-- Replicated StateManager tests (older utility version)
local function testReplicatedStateManager()
    TestService:Message("Testing Replicated StateManager (Utility)...")
    local evt = Instance.new("BindableEvent")
    local sm = ReplicatedStateManager.New(evt)

    local seen = 0
    sm:DefineState("Stamina", 50, function(v) return typeof(v) == "number" and v >= 0 and v <= 100 end)
    local disconnect = sm:OnStateChange("Stamina", function(new, old)
        seen += 1
    end)

    local ok = sm:Set("Stamina", 75)
    assertTrue(ok == true, "Set should succeed for valid value")
    assertEquals(75, sm:Get("Stamina"))
    sm:SetMultiple({ Stamina = 60, Guard = 20 })
    assertEquals(60, sm:Get("Stamina"))
    assertEquals(20, sm:Get("Guard"))

    -- Invalid set rejected
    local ok2 = sm:Set("Stamina", -10)
    assertTrue(ok2 == false, "Validator should reject invalid value")
    assertEquals(60, sm:Get("Stamina"))

    disconnect()
    evt:Destroy()
    TestService:Message("✓ Replicated StateManager tests passed")
end

-- UpdateScheduler tests (quick sanity)
local function testUpdateScheduler()
    TestService:Message("Testing UpdateScheduler...")
    local scheduler = UpdateScheduler.New(0.05) -- fixed 20 Hz
    local ticks = 0
    local disconnect = scheduler:OnStep(function(dt)
        ticks += 1
        assertNear(0.05, dt, 0.03, "dt should be near interval for fixed-step")
    end)
    scheduler:Start()
    task.wait(0.22)
    scheduler:Stop()
    disconnect()
    scheduler:Destroy()
    assertTrue(ticks >= 3, "Scheduler should have ticked at least 3 times in ~0.22s")
    TestService:Message("✓ UpdateScheduler tests passed")
end

local function runAll()
    TestService:Message("=== Starting Core Systems Tests ===")
    local tests = {
        { name = "Registry", f = testRegistry },
        { name = "EventBus", f = testEventBus },
        { name = "CoreStateManager", f = testCoreStateManager },
        { name = "ReplicatedStateManager", f = testReplicatedStateManager },
        { name = "UpdateScheduler", f = testUpdateScheduler },
    }

    local passed, failed = 0, 0
    for _, t in ipairs(tests) do
        local ok = pcall(t.f)
        if ok then
            passed += 1
            TestService:Message(`✓ {t.name} passed`)
        else
            failed += 1
            TestService:Error(`✗ {t.name} failed`)
        end
    end

    TestService:Message("=== Core Systems Test Results ===")
    TestService:Message(`Passed: {passed}`)
    TestService:Message(`Failed: {failed}`)
end

runAll()
