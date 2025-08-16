--!strict
-- Network Manager tests: validate remote registration and event flow

local TestService = game:GetService("TestService")

local NetworkManager = require(game.ServerStorage.Modules.Core.NetworkManager)

local function assertTrue(cond: boolean, msg: string)
    if not cond then TestService:Error(msg) end
end

local function assertType(value: any, t: string, msg: string?)
    local m = msg or `Expected type {t}, got {typeof(value)}`
    assertTrue(typeof(value) == t, m)
end

local function _assertEquals(a: any, b: any, m: string?)
    assertTrue(a == b, m or `Expected {tostring(a)} == {tostring(b)}`)
end

local function testRemoteRegistration()
    TestService:Message("Testing NetworkManager remote registration...")
    local nm = NetworkManager.New()

    local re = nm:RegisterRemoteEvent("UnitTestEvent")
    local rf = nm:RegisterRemoteFunction("UnitTestFunction")

    assertType(re, "Instance")
    assertType(rf, "Instance")

    -- Idempotent
    local re2 = nm:RegisterRemoteEvent("UnitTestEvent")
    assertTrue(re2 == re, "RegisterRemoteEvent should be idempotent")

    -- Server handler hookup
    local handled = 0
    nm:RegisterServerHandler("UnitTestEvent", function(player: Player, data: any)
        handled += 1
        return nil
    end)

    -- Simulate server event fire by invoking RemoteEvent.OnServerEvent manually
    -- We can't simulate a player here, but ensure connection was added
    -- This is indirectly verified via internal connection list size
    local connCount = 0
    local field = (nm :: any)._connections
    for _ in field do connCount += 1 end
    assertTrue(connCount >= 1, "RegisterServerHandler should add a connection when event exists")

    nm:Destroy()
    TestService:Message("✓ NetworkManager registration tests passed")
end

local function testOutboundSubscribe()
    TestService:Message("Testing NetworkManager outbound subscribe...")
    local nm = NetworkManager.New()

    local re = nm:RegisterRemoteEvent("OutEvent")
    assertType(re, "Instance")

    local seen = 0
    nm:SubscribeToOutbound("OutEvent", function(payload)
        seen += 1
        assertType(payload, "table")
        assertTrue(payload.eventName == "OutEvent", "eventName should match")
    end)

    nm:TriggerOutbound({ eventName = "OutEvent" })
    task.wait()
    assertTrue(seen == 1, "Subscriber should have seen one outbound event")

    nm:Destroy()
    TestService:Message("✓ NetworkManager outbound tests passed")
end

local function runAll()
    TestService:Message("=== Starting Network Tests ===")
    local ok = pcall(testRemoteRegistration)
    if not ok then
        TestService:Error("Network registration failed")
        return
    end

    ok = pcall(testOutboundSubscribe)
    if not ok then
        TestService:Error("Outbound subscribe failed")
        return
    end

    TestService:Message("=== All Network Tests Passed ===")
end

runAll()
