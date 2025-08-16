# Backend Controls and Messaging

This document shows how to call the backend CoreEvent for abilities and primary weapon actions, and outlines the overall backend architecture (services, components, and enums).

## Core Remote
- RemoteEvent path: `ReplicatedStorage.Remotes.CoreEvent`
- Messages are typed using `ReplicatedStorage.Modules.Types.Enums` and `...Types.NetworkTypes`.

## Messages
- Ability
  - t: `Enums.CoreMessageType.Ability`
  - id: `Enums.AbilityId`
  - extra?: arbitrary payload table
- Primary Weapon
  - t: `Enums.CoreMessageType.PrimaryWeapon`
  - action: `Enums.WeaponAction` (e.g., `M1`)

## Examples (Client)

### Ability activation
```lua
local CoreRemote: RemoteEvent = game.ReplicatedStorage.Remotes.CoreEvent
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)

-- Dash ability example
CoreRemote:FireServer({
    t = Enums.CoreMessageType.Ability,
    id = Enums.AbilityId.Dash,
    extra = {
        -- Optional payload; your ability may read these
        position = workspace.CurrentCamera.CFrame.Position,
        direction = workspace.CurrentCamera.CFrame.LookVector,
    },
})
```

### Primary weapon M1
```lua
local CoreRemote: RemoteEvent = game.ReplicatedStorage.Remotes.CoreEvent
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)

CoreRemote:FireServer({
    t = Enums.CoreMessageType.PrimaryWeapon,
    action = Enums.WeaponAction.M1,
})
```

### Adding new actions
Add a new `CoreMessageType` and server handler, then call:
```lua
CoreRemote:FireServer({
    t = Enums.CoreMessageType.SwapWeapon, -- after you add it to Enums and server
    to = "Greatsword", -- your WeaponId
})
```

---

# Backend Architecture Overview

- Strict-typed services and components for RPG-scale abilities, weapons, and status effects.
- Event-driven inputs; the client talks only to CoreEvent with typed messages.

## Enums & Types
- `ReplicatedStorage/Modules/Types/Enums.luau`
  - `CoreMessageType` = `PrimaryWeapon | Ability`
  - `WeaponId` = `Default | string`
  - `WeaponAction` = `M1`
  - `AbilityId` = `dash | keen | string`
  - `EffectId` = `Bleed | Rally | Fortify | string`
- `ReplicatedStorage/Modules/Types/NetworkTypes.luau`
  - `PrimaryWeaponMsg` and `AbilityMsg` shapes
- `ServerStorage/Modules/Types/*`
  - `AbilityTypes.luau`, `EffectTypes.luau`, `CharacterTypes.luau`, etc.

## Services (ServerStorage/Modules/Services)
- `WeaponService.luau`
  - Registers weapon handlers by `WeaponId`
  - Tracks equipped weapon per player
  - Dispatches `Primary(player, action)` to handler
- `CombatService.luau`
  - Attack, block, damage logic (shared by weapons)
- `AbilityService.luau`
  - Abilities (active) + passives, cooldowns, stamina costs; integrates with characters
- `AbilityRegistry.luau`
  - Registers active/passive definitions
- `EffectService.luau`
  - Status effect system: register, apply, remove, update, tick
- `EffectRegistryBootstrap.luau`
  - Example effects (Rally, Bleed) registration

## Components (ServerStorage/Modules/Components)
- `WeaponComponent.luau`
  - Wraps `WeaponService`
  - Registers default weapon handler: `M1` → `CombatComponent.PerformAttack("Default")`
  - Equips `WeaponId.Default` on spawn
- `CombatComponent.luau`
  - Wraps `CombatService`
- `AbilityComponent.luau`
  - Wraps `AbilityService` and exposes registry
- `EffectComponent.luau`
  - Wraps `EffectService`; updates and ticks effects per character

## Character Integration
- `ServerStorage/Modules/Entities/Character.luau`
  - Registers Components: `Movement`, `Combat`, `Ability`, `Weapon`, `Effect`
  - Hooks ability registry examples and effect registry bootstrap
  - Injects default ability loadout via `Utilities/Abilities/Loadouts.luau`

## Extending
- Add weapons: call `WeaponComponent.GetService():RegisterWeapon(Enums.WeaponId.X, handler)` and `...:Equip(playerId, Enums.WeaponId.X)`
- Add effects: call `EffectComponent.GetService():Register(def)` or add to bootstrap file
- Add abilities: register in `AbilityRegistry` and drive logic via `serverActivate`, `onTick`

## Notes
- All systems are backend-only; no client code added beyond examples above.
- Messages and IDs are enum-backed to avoid typos and keep types strict.
- Effects and passives can implement any logic (buffs, debuffs, DOTs, HOTs, etc.).
