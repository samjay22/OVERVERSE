--!strict
-- Spear weapon - longer range attacks with thrust mechanics (new interface)

local _ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatComponent = require(game.ServerStorage.Modules.Components.CombatComponent)
local WeaponTypes = require(game.ServerStorage.Modules.Types.WeaponTypes)

local handler: WeaponTypes.WeaponHandler = {
    id = "Spear",
    config = {
        AttackType = "Spear",
        Damage = 22,
        Range = 4.5,
        CanBlock = true,
    },
    OnAttack = function(ctx)
        return CombatComponent.PerformAttack(ctx.character, (ctx.config and ctx.config.AttackType) or "Spear")
    end,
    OnHit = function(ctx)
        if not ctx.target then return true end
        local damage = ctx.damageOverride or ((ctx.config and ctx.config.Damage) or 22)
        local canBlock = (ctx.canBlock == nil) and ((ctx.config and ctx.config.CanBlock) or true) or ctx.canBlock
        CombatComponent.ApplyDamage(ctx.attacker, ctx.target, damage, canBlock)
        return true
    end,
}

return handler
