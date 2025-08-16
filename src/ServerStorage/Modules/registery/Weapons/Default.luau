--!strict
-- Default weapon handler (new interface)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage.Modules.Types.Enums)
local CombatComponent = require(game.ServerStorage.Modules.Components.CombatComponent)
local WeaponTypes = require(game.ServerStorage.Modules.Types.WeaponTypes)


local handler: WeaponTypes.WeaponHandler = {
    id = Enums.WeaponId.Default,
    config = {
        AttackType = "Default",
        Damage = 20,
        Range = 3.5,
        CanBlock = true,
    },
    OnAttack = function(ctx)
        local ok: boolean = CombatComponent.PerformAttack(ctx.character, (ctx.config and ctx.config.AttackType) or "Default")
        return ok, nil
    end,
    OnHit = function(ctx)
        if not ctx.target then return true end
        local damage = ctx.damageOverride or ((ctx.config and ctx.config.Damage) or 20)
        local canBlock = (ctx.canBlock == nil) and ((ctx.config and ctx.config.CanBlock) or true) or ctx.canBlock
        CombatComponent.ApplyDamage(ctx.attacker, ctx.target, damage, canBlock)
        return true
    end,
}

return handler
