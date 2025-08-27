--!strict
-- Test script to verify cooldown system works properly

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Wait for first player to join
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        -- Wait for character to be fully loaded
        wait(2)
        
        print("[TestCooldowns] Testing cooldown system for", player.Name)
        
        -- Get the cooldown manager
        local CooldownManager = require(game.ServerStorage.Modules.Core.AbilitySystem.CooldownManager)
        local cooldownManager = CooldownManager.get()
        
        -- Test 1: Start a cooldown
        print("[TestCooldowns] Test 1: Starting cooldown")
        cooldownManager:startCooldown(character, "TestAbility", 5.0)
        
        -- Test 2: Check if on cooldown
        wait(0.1)
        local isOnCooldown = cooldownManager:isOnCooldown(character, "TestAbility")
        print("[TestCooldowns] Test 2: Is on cooldown?", isOnCooldown, "(should be true)")
        
        -- Test 3: Check remaining time
        local remaining = cooldownManager:getCooldownRemaining(character, "TestAbility")
        print("[TestCooldowns] Test 3: Remaining time:", remaining, "(should be ~4.9)")
        
        -- Test 4: Wait for cooldown to expire
        wait(5)
        isOnCooldown = cooldownManager:isOnCooldown(character, "TestAbility")
        print("[TestCooldowns] Test 4: Is on cooldown after 5s?", isOnCooldown, "(should be false)")
        
        -- Test 5: Clear and retest
        print("[TestCooldowns] Test 5: Clearing cooldowns")
        cooldownManager:clearEntityCooldowns(character)
        isOnCooldown = cooldownManager:isOnCooldown(character, "TestAbility")
        print("[TestCooldowns] Test 5: Is on cooldown after clear?", isOnCooldown, "(should be false)")
        
        print("[TestCooldowns] All tests completed!")
    end)
end)