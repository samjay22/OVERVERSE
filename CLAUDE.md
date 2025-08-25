# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OVERVERSE is a Roblox game project built with Luau, featuring a sophisticated component-based entity system with client-side prediction and server validation. The project uses Rojo for syncing between the filesystem and Roblox Studio.

## Development Commands

### Building and Syncing
```bash
# Start Rojo server to sync with Roblox Studio
rojo serve

# Build the project into a .rbxl file
rojo build -o OVERVERSE.rbxl
```

### Running in Roblox Studio
1. Install Rojo plugin in Roblox Studio
2. Run `rojo serve` in terminal
3. Connect via Rojo plugin in Studio
4. Use Studio's Run/Play buttons for testing

## Core Architecture

### Character System
The game uses a modular component-based entity architecture:

- **CharacterManager** (`ServerStorage/Modules/Entities/Character/`): Orchestrates all character operations
- **ComponentManager**: Manages character components (Health, Stamina, Movement, Combat, Effect, Ability, Weapon, Input)
- **CharacterFactory**: Creates character instances with proper configuration
- **CharacterLifecycle**: Handles spawning, death, and respawn logic
- **CharacterRegistry**: Tracks active characters and their states
- **Manual Spawning**: `Players.CharacterAutoLoads` is disabled; characters spawn via queue system

### Network Architecture
- **NetworkManager** (`ServerStorage/Modules/Core/`): Centralized event management with EventBus integration
- **Client Prediction**: Optimistic execution with server rollback via prediction types
- **Input System**: Client captures → Server validates → Network replicates
- **RemoteEvents**: Strongly typed communication between client and server

### Registry System
Content definition and management through registries:

- **Characters** (`ServerStorage/Modules/registery/Characters/`): Character class definitions (e.g., Rem)
- **Loadouts** (`ServerStorage/Modules/registery/Loadouts/`): Ability configurations per character/form
- **Effects** (`ServerStorage/Modules/registery/Effects/`): Buff/debuff definitions (Bleed, Fortify, Rally, Regeneration)
- **Weapons** (`ServerStorage/Modules/registery/Weapons/`): Weapon type definitions (Sword, Spear)

### Service Architecture
Server-side game logic orchestration:

- **AbilityService**: Ability execution and validation
- **CharacterService**: Character management interface
- **CombatService**: Combat mechanics and damage calculation
- **EffectService**: Effect application and management
- **WeaponService**: Weapon behavior and stats

### Key Patterns

#### Entity Reference System
Unified handling of Players and NPCs:
```lua
type EntityRef = {
    entityType: "Player" | "NPC",
    player: Player?,
    npcId: string?,
    name: string,
    userId: number
}
```

#### Component System
Each character has modular components:
- **AbilityComponent**: Manages ability cooldowns and execution
- **CombatComponent**: Handles attack patterns and damage
- **EffectComponent**: Tracks active effects and durations
- **HealthComponent**: Health management and damage processing
- **InputComponent**: Processes player input
- **MovementComponent**: Character movement and physics
- **StaminaComponent**: Stamina consumption and regeneration
- **WeaponComponent**: Weapon state and attacks

#### State Management
- **StateManager**: Per-character state with validation
- **CharacterStates**: State definitions and transitions
- **StateSync**: Client-server state synchronization

### File Organization

```
src/
├── ReplicatedStorage/       # Shared between client/server
│   └── Modules/
│       ├── AbilityAssets/  # Visual/audio assets per character
│       ├── AssetHandlers/  # Asset loading utilities
│       ├── CoreClient/     # Client-side systems
│       ├── Types/          # Shared type definitions
│       └── Utility/        # Shared utilities
├── ServerScriptService/    # Server initialization scripts
├── ServerStorage/         # Server-only modules
│   └── Modules/
│       ├── Components/    # Character component system
│       ├── Core/          # Core server infrastructure
│       ├── Entities/      # Character management system
│       ├── Events/        # Event bus system
│       ├── Services/      # Game services
│       ├── Systems/       # Performance and scheduling
│       ├── Types/         # Server type definitions
│       ├── Utilities/     # Server utilities
│       └── registery/     # Content definitions
├── StarterGui/           # UI components
└── StarterPlayerScripts/ # Client initialization scripts
```

## Character System Details

### Character Definitions
Characters are defined with:
- **Class Structure**: Base stats, abilities, and properties
- **Shift States**: Characters can transform (e.g., Rem ↔ Ram)
- **Loadout System**: Different ability sets per state
- **Custom Fields**: Character-specific timers and properties

### Combat System
- **Damage Types**: Physical, Magical, True, Poison, Fire, Ice, Lightning
- **Effect System**: Timed, permanent, or conditional effects
- **Guard System**: Blocking with efficiency calculations
- **Combat Events**: Centralized event bus for combat actions

## Performance Optimization

- **UpdateLoop**: 60Hz character updates with batch processing (default: 10 characters/batch)
- **Object Pooling**: Event and cleanup pools to reduce garbage collection
- **FrameBudgetManager**: Ensures consistent frame times
- **PerformanceMonitor**: Tracks system performance metrics
- **Distance Culling**: Performance scaling based on player proximity

## Important Considerations

### Type Safety
- Extensive use of strict typing throughout the codebase
- Well-defined interfaces for all major systems
- Centralized constants and enums
- Type validation for state management

### Asset Management
- **AbilityAssets**: Organized by character and ability type (M1, M2, E, F, Shift)
- **AssetHandlers**: Specialized loaders for animations, characters, effects, weapons
- **Preloading**: AssetPreloader for optimal loading

### Development Notes
- **Workspace Streaming**: Enabled with 500-2000 stud radius
- **Manual Character Spawning**: Queue-based system with configuration support
- **Event-Driven Architecture**: EventBus for decoupled communication
- **Service Pattern**: ServiceManager orchestrates all game services

## Project Configuration

- **Rojo Project**: `default.project.json` - Maps filesystem to Roblox services
- **Toolchain**: `aftman.toml` / `rokit.toml` - Manages tool versions
- **Source Map**: `sourcemap.json` - Generated by Rojo for debugging