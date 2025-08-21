--!strict
-- Sword weapon handler - updated with new strongly-typed system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local CombatComponent = require(game.ServerStorage.Modules.Components.CombatComponent)
local WeaponTypes = require(game.ServerStorage.Modules.Types.WeaponTypes)

local SWORD_DAMAGE = 35
local SWORD_RANGE = 4
local SWORD_COOLDOWN = 1.2
local SWORD_STAMINA_COST = 15

local handler: WeaponTypes.WeaponHandler = {
	id = Enums.WeaponId.Sword,
	config = {
		AttackType = "Sword",
		Damage = SWORD_DAMAGE,
		Range = SWORD_RANGE,
		CanBlock = true,
		AttackCooldown = SWORD_COOLDOWN,
		StaminaCost = SWORD_STAMINA_COST,
	},
	OnAttack = function(ctx)
		-- Use new context format while maintaining backwards compatibility
		local success = CombatComponent.PerformAttack(ctx.character, (ctx.config and ctx.config.AttackType) or "Sword")
		
		-- Set character state for attack animation
		if success and ctx.character.StateManager then
			ctx.character.StateManager:Set("IsAttacking", true)
			task.spawn(function()
				task.wait(0.5) -- Attack animation duration
				ctx.character.StateManager:Set("IsAttacking", false)
			end)
		end
		
		return success, if success then nil else "Attack failed"
	end,
	OnHit = function(ctx)
		if not ctx.target then return true end
		local damage = ctx.damageOverride or ((ctx.config and ctx.config.Damage) or SWORD_DAMAGE)
		local canBlock = (ctx.canBlock == nil) and ((ctx.config and ctx.config.CanBlock) or true) or ctx.canBlock
		
		-- Apply damage through combat component
		local result = CombatComponent.ApplyDamage(ctx.attacker, ctx.target, damage, canBlock)
		
		-- Add hit effects
		if result and ctx.attacker.StateManager then
			ctx.attacker.StateManager:Set("LastHitTime", tick())
		end
		
		return result > 0
	end,
}

return handler
