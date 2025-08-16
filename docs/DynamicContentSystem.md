# Dynamic Content System Documentation

This system provides a scalable, type-safe way to add new abilities, weapons, effects, and characters to the game.

## Overview

The new architecture includes:

1. **NetworkManager**: Event-driven networking with bindable events
2. **Registry System**: Dynamic content loading with validation
3. **Strong Typing**: Full Luau strict typing throughout
4. **Component Architecture**: Modular, reusable components
5. **State Management**: Event-driven state system

## Adding New Abilities

### Step 1: Add to Enums

```lua
-- In src/ReplicatedStorage/Modules/Types/Enums.luau
export type AbilityId = "Dash" | "Keen" | "Heal" | "YourNewAbility"

local AbilityId = {
    -- ... existing abilities
    YourNewAbility = "YourNewAbility" :: AbilityId,
}
```

### Step 2: Create Ability Definition

Create a new file: `src/ServerStorage/Modules/registery/Abilities/Definitions/YourNewAbility.luau`

```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage.Modules.Types.Enums)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

local function activateAbility(context: AbilityTypes.AbilityContext): AbilityTypes.AbilityResult
    local character = context.character
    
    -- Your ability logic here
    
    return {
        success = true,
        data = {
            -- Any result data
        },
    }
end

return {
    id = Enums.AbilityId.YourNewAbility,
    type = "Active" :: "Active",
    name = "Your Ability Name",
    description = "What your ability does",
    targetType = "Self" :: "Self", -- or "Target", "Area", "None"
    cooldown = 5, -- seconds
    staminaCost = 20,
    range = 10, -- studs (for targeted abilities)
    castTime = 0.5, -- seconds
    interruptible = true,
    serverActivate = activateAbility,
}
```

### Step 3: That's It!

The ability is automatically loaded by the registry system. No manual registration required.

## Adding New Weapons

### Step 1: Add to Enums

```lua
-- In src/ReplicatedStorage/Modules/Types/Enums.luau
export type WeaponId = "Default" | "Sword" | "YourNewWeapon"

local WeaponId = {
    -- ... existing weapons
    YourNewWeapon = "YourNewWeapon" :: WeaponId,
}
```

### Step 2: Create Weapon Definition

Create: `src/ServerStorage/Modules/registery/Weapons/YourNewWeapon.luau`

```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage.Modules.Types.Enums)
local WeaponTypes = require(game.ServerStorage.Modules.Types.WeaponTypes)

local function onAttack(context: WeaponTypes.WeaponContext): WeaponTypes.WeaponResult
    -- Weapon attack logic
    return {
        success = true,
        damage = 50,
        targets = {context.player},
    }
end

return {
    id = Enums.WeaponId.YourNewWeapon,
    type = "Melee" :: "Melee", -- or "Ranged", "Magic"
    name = "Your Weapon Name",
    description = "What your weapon does",
    damage = 50,
    range = 5,
    speed = 1.0,
    cooldown = 1.5,
    staminaCost = 10,
    onAttack = onAttack,
}
```

## Adding New Effects

### Step 1: Add to Enums

```lua
-- In src/ReplicatedStorage/Modules/Types/Enums.luau
export type EffectId = "Bleed" | "Rally" | "YourNewEffect"

local EffectId = {
    -- ... existing effects
    YourNewEffect = "YourNewEffect" :: EffectId,
}
```

### Step 2: Create Effect Definition

Create: `src/ServerStorage/Modules/registery/Effects/Definitions/YourNewEffect.luau`

```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage.Modules.Types.Enums)

return {
    id = Enums.EffectId.YourNewEffect,
    type = "Buff" :: "Buff", -- or "Debuff", "Neutral"
    name = "Your Effect Name",
    description = "What your effect does",
    duration = "Timed" :: "Timed", -- or "Instant", "Permanent", "Conditional"
    
    onApply = function(character, power, duration)
        -- Apply effect logic
    end,
    
    onTick = function(character, deltaTime, power)
        -- Per-frame effect logic
    end,
    
    onRemove = function(character)
        -- Cleanup logic
    end,
}
```

## Network Events

The new system uses typed network events:

### Sending from Client

```lua
-- AbilityEvent
local NetworkTypes = require(game.ReplicatedStorage.Modules.Types.NetworkTypes)
local abilityEvent = game.ReplicatedStorage.Remotes.AbilityEvent

local message = NetworkTypes.CreateAbilityActivateMessage(
    game.Players.LocalPlayer.UserId,
    "Dash",
    {
        targetPosition = Vector3.new(0, 0, 10),
        direction = Vector3.new(0, 0, 1),
    }
)

abilityEvent:FireServer(message)
```

### Listening on Server

The NetworkServer automatically handles typed events and calls the appropriate services.

### Custom Events

You can subscribe to network events for custom handling:

```lua
local networkManager = require(game.ServerScriptService.Scripts.NetworkServer)

-- Subscribe to outbound ability events
networkManager:SubscribeToOutbound("AbilityEvent", function(eventData)
    print("Ability event:", eventData.eventName)
    -- Custom logic here
end)
```

## State Management

The new StateManager provides type-safe state handling:

```lua
local StateManager = require(game.ServerStorage.Modules.Core.StateManager)
local stateManager = StateManager.New()

-- Set state
stateManager:Set("Health", 100)
stateManager:Set("IsInCombat", true)

-- Get state
local health = stateManager:Get("Health") -- number | nil
local inCombat = stateManager:Get("IsInCombat") -- boolean | nil

-- Listen for changes
local connection = stateManager:OnChange("Health", function(newValue, oldValue)
    print(`Health changed from {oldValue} to {newValue}`)
end)

-- Set multiple states at once
stateManager:SetMultiple({
    Health = 90,
    Stamina = 75,
    IsBlocking = false,
})
```

## Component System

Components are modular pieces that handle specific functionality:

```lua
-- In a component
local MyComponent = {}

function MyComponent.Initialize(characterData, config)
    -- Setup logic
end

function MyComponent.Update(characterData, deltaTime)
    -- Per-frame logic
end

function MyComponent.Cleanup(characterData)
    -- Cleanup logic
end

return MyComponent
```

## Character Classes

To add new character classes:

1. Add to `CharacterClass` enum
2. Create loadout definitions in `src/ServerStorage/Modules/registery/Loadouts/`
3. Define class-specific abilities and weapons

## Best Practices

1. **Always use strict typing** (`--!strict`)
2. **Export types at the top** of type definition files
3. **Validate inputs** in ability/weapon functions
4. **Use the Registry system** instead of manual imports
5. **Follow naming conventions**: PascalCase for types, camelCase for functions
6. **Document complex logic** with comments
7. **Use events** instead of direct coupling between systems

## Migration from Legacy System

The new system maintains backwards compatibility:

- Old `CoreEvent` still works
- Legacy ability definitions are supported
- Existing components continue to function

To migrate:
1. Update type annotations to use new strongly-typed interfaces
2. Replace manual registrations with Registry-based loading
3. Convert direct RemoteEvent usage to NetworkManager
4. Update state management to use new StateManager

## Performance Considerations

- Registry loading is cached
- State changes only fire events when values actually change
- Network events use efficient serialization
- Components are updated on a managed schedule

This system is designed to scale from small games to large, complex multiplayer experiences while maintaining type safety and performance.
