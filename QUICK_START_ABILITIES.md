# Quick Start Guide: Creating Abilities

## 🚀 TL;DR - Create Abilities in 3 Steps

1. **Choose your approach**: Template, Builder, or Custom Effect
2. **Configure your ability**: Set name, cooldown, costs, etc.
3. **Add effects**: Use pre-built effects or create custom ones

## ⚡ Super Quick Examples

### Movement Ability (Dash)
```lua
-- Copy-paste ready!
return AbilityTemplates.Movement({
    id = "my_dash",
    name = "Super Dash",
    distance = 20,
    cooldown = 3,
    staminaCost = 15,
    handler = AbilityEffects.CreateDashEffect({ distance = 20, duration = 0.3 })
})
```

### Healing Ability
```lua
-- Copy-paste ready!
return AbilityTemplates.Healing({
    id = "my_heal",
    name = "Quick Heal",
    healAmount = 50,
    cooldown = 5,
    manaCost = 25,
    handler = AbilityEffects.CreateHealEffect({ amount = 50 })
})
```

### Damage Ability (AOE)
```lua
-- Copy-paste ready!
return AbilityTemplates.Damage({
    id = "my_explosion",
    name = "Explosion",
    damage = 60,
    cooldown = 6,
    manaCost = 40,
    handler = AbilityEffects.CreateAOEDamageEffect({
        damage = 60,
        radius = 10,
        maxTargets = 5
    })
})
```

---

## 📚 Available Templates

### `AbilityTemplates.Movement(config)`
Perfect for: Dash, teleport, charge abilities
```lua
AbilityTemplates.Movement({
    id = "ability_id",
    name = "Ability Name",
    description = "What it does", -- optional
    distance = 16, -- how far to move
    duration = 0.3, -- how long it takes
    cooldown = 3,
    staminaCost = 20,
    handler = AbilityEffects.CreateDashEffect({ distance = 16 })
})
```

### `AbilityTemplates.Healing(config)`
Perfect for: All healing abilities
```lua
AbilityTemplates.Healing({
    id = "ability_id",
    name = "Ability Name",
    healAmount = 50,
    cooldown = 5,
    manaCost = 30,
    handler = AbilityEffects.CreateHealEffect({ 
        amount = 50,
        overheal = false  -- optional
    })
})
```

### `AbilityTemplates.Damage(config)`
Perfect for: Direct damage, projectiles
```lua
AbilityTemplates.Damage({
    id = "ability_id",
    name = "Ability Name",
    damage = 40,
    cooldown = 4,
    manaCost = 25,
    handler = AbilityEffects.CreateDamageEffect({ amount = 40 })
})
```

### `AbilityTemplates.Buff(config)`
Perfect for: Speed boosts, stat increases
```lua
AbilityTemplates.Buff({
    id = "ability_id",
    name = "Ability Name",
    duration = 10,
    cooldown = 15,
    staminaCost = 30,
    handler = AbilityEffects.CreateBuffEffect({
        modifiers = { MovementSpeed = 1.5 },
        duration = 10
    })
})
```

---

## 🔧 Pre-Built Effects

### Movement Effects
```lua
-- Dash forward
AbilityEffects.CreateDashEffect({
    distance = 16,        -- studs to dash
    duration = 0.3,       -- seconds
    easingStyle = Enum.EasingStyle.Quart  -- optional
})

-- Teleport
AbilityEffects.CreateTeleportEffect({
    maxDistance = 20,           -- max teleport distance
    requireLineOfSight = true   -- must see target location
})
```

### Healing Effects
```lua
AbilityEffects.CreateHealEffect({
    amount = 50,           -- health to restore
    overheal = false,      -- allow healing above max HP
    animationTime = 1      -- healing animation duration
})
```

### Damage Effects
```lua
-- Single target
AbilityEffects.CreateDamageEffect({
    amount = 30,
    damageType = "Physical",  -- optional
    canCrit = true,          -- enable critical hits
    critChance = 0.1,        -- 10% crit chance
    critMultiplier = 2.0     -- 2x damage on crit
})

-- Area of Effect
AbilityEffects.CreateAOEDamageEffect({
    damage = 40,
    radius = 8,
    maxTargets = 3
})
```

### Buff Effects
```lua
AbilityEffects.CreateBuffEffect({
    modifiers = {
        MovementSpeed = 1.5,    -- 50% speed boost
        JumpPower = 1.2,        -- 20% jump boost
        DamageResistance = 0.9  -- 90% damage resistance
    },
    duration = 10,    -- seconds (optional - permanent if not set)
    stackable = false -- can multiple buffs stack?
})
```

---

## 🛠️ Builder Pattern (For Custom Abilities)

When templates aren't enough, use the builder:

```lua
return AbilityBuilder.New()
    :WithId("custom_ability")
    :WithName("Custom Ability")
    :WithDescription("Does something unique")
    -- Type
    :AsActive()  -- or :AsPassive()
    -- Stats
    :WithCooldown(5)
    :WithManaCost(30)
    :WithStaminaCost(20)
    :WithLevel(3)
    -- Targeting
    :TargetingSelf()     -- or :TargetingEnemy(), :TargetingAlly(), etc.
    -- Behavior
    :WithOnActivate(function(context)
        -- Your custom logic here
        return { success = true }
    end)
    :Build()
```

### Builder Methods
- **Type**: `:AsActive()`, `:AsPassive()`
- **Stats**: `:WithCooldown()`, `:WithManaCost()`, `:WithStaminaCost()`, `:WithLevel()`
- **Targeting**: `:TargetingSelf()`, `:TargetingEnemy()`, `:TargetingAlly()`, `:TargetingArea()`
- **Behavior**: `:WithOnActivate()`, `:WithOnEquip()`, `:WithOnTick()` (for passives)

---

## 🎯 Common Patterns

### Combo Abilities (Multiple Effects)
```lua
:WithOnActivate(function(context)
    -- Effect 1: Teleport
    local teleportResult = AbilityEffects.CreateTeleportEffect({
        maxDistance = 15
    })(context)
    
    if teleportResult.success then
        -- Effect 2: Damage
        local damageResult = AbilityEffects.CreateDamageEffect({
            amount = 80
        })(context)
        
        return {
            success = true,
            data = { teleport = teleportResult.data, damage = damageResult.data }
        }
    end
    
    return teleportResult
end)
```

### Conditional Effects
```lua
:WithOnActivate(function(context)
    local character = context.character
    
    -- Only heal if below 50% health
    if character.Humanoid.Health < (character.Humanoid.MaxHealth * 0.5) then
        return AbilityEffects.CreateHealEffect({ amount = 100 })(context)
    else
        return { success = false, errorMessage = "Health too high" }
    end
end)
```

### Passive Abilities
```lua
return AbilityBuilder.New()
    :WithId("regeneration")
    :WithName("Regeneration")
    :AsPassive()
    :WithOnTick(function(context, deltaTime)
        -- Heal 1 HP per second
        local character = context.character
        if character.Humanoid.Health < character.Humanoid.MaxHealth then
            character.Humanoid.Health = math.min(
                character.Humanoid.Health + deltaTime,
                character.Humanoid.MaxHealth
            )
        end
    end)
    :Build()
```

---

## 📁 Where to Put Your Abilities

Create your ability files in:
```
src/ServerStorage/Modules/registery/Abilities/YourAbilities.luau
```

Example file structure:
```lua
--!strict
local AbilityBuilder = require(game.ServerStorage.Modules.Utilities.AbilityBuilder)
local AbilityTemplates = require(game.ServerStorage.Modules.Utilities.AbilityTemplates)
local AbilityEffects = require(game.ServerStorage.Modules.Utilities.AbilityEffects)

local MyAbilities = {}

function MyAbilities.CreateDash()
    return AbilityTemplates.Movement({
        id = "my_dash",
        name = "My Dash",
        distance = 20,
        cooldown = 3,
        staminaCost = 15,
        handler = AbilityEffects.CreateDashEffect({ distance = 20 })
    })
end

function MyAbilities.CreateHeal()
    return AbilityTemplates.Healing({
        id = "my_heal",
        name = "My Heal",
        healAmount = 50,
        cooldown = 5,
        manaCost = 25,
        handler = AbilityEffects.CreateHealEffect({ amount = 50 })
    })
end

return MyAbilities
```

---

## 🐛 Troubleshooting

### Common Issues

**"TypeError: Key 'X' not found"**
- Check method names match the builder API
- Use `:WithOnActivate()` not `:WithHandler()`
- Use `:AsActive()` not `:WithSubtype()`

**"Unknown require"**
- Use full paths: `game.ServerStorage.Modules.Utilities.AbilityBuilder`
- Don't use relative paths like `script.Parent`

**Effect not working**
- Make sure your effect function is called: `effectFunction(context)`
- Check the effect returns `{ success = boolean }` format

### Getting Help

1. Check the type definitions in `AbilityTypes.luau`
2. Look at working examples in `ExampleAbilities.luau`
3. Use VS Code autocomplete (it's fully typed!)

---

## 🎉 You're Ready!

You now have everything you need to create amazing abilities quickly and easily. The system handles all the complex stuff - you just focus on making fun abilities!

**Happy ability creating! 🚀**
