# M1 Raycast System - End-to-End Flow Documentation

## Overview
The M1 ability now performs server-side raycasting from the entity position to the player's mouse click position.

## Complete Data Flow

### 1. Client-Side Mouse Tracking
**File:** `src/StarterPlayerScripts/MouseTracker.client.luau`
- Continuously tracks mouse position
- Sends updates via `NetworkClient.UpdateMouse.Fire()` every 100ms
- Sends immediate updates on mouse clicks
- Data sent: `{ MouseHit, MouseUnit, Origin, MouseScreenPosition }`

### 2. Network Communication
**Files:** `src/ReplicatedStorage/Modules/Network/Client.luau` & `Server.luau`
- `UpdateMouse` event carries mouse data from client to server
- Uses unreliable remote for continuous updates (performance optimization)

### 3. Server-Side Mouse Component
**File:** `src/ServerStorage/Modules/Components/MouseComponent.luau`
- Listens for `UpdateMouse` network events
- Stores mouse position data per character
- Validates data freshness (max 500ms age)
- Updates both component storage and StateManager

### 4. Input Processing
**File:** `src/ServerStorage/Modules/Components/InputComponent.luau`
- When M1 is detected:
  1. Retrieves mouse position from MouseComponent
  2. Falls back to StateManager if needed
  3. Calls `AbilityComponent.M1WithTarget()` with position

### 5. Ability Component
**File:** `src/ServerStorage/Modules/Components/AbilityComponent.luau`
- `M1WithTarget()` passes `targetPosition` in meta data
- Routes through `HandleInput()` → `_HandleM1()` → `Activate()`
- Passes `targetPosition` to ability's `Validate()` function

### 6. M1 Ability Raycast
**File:** `src/ReplicatedStorage/Modules/Abilities/Rem/M1.luau`
- Server `Validate()` function receives `targetPosition`
- Performs raycast from entity position to target position
- Filters out the casting player's character
- On hit:
  - Checks if hit object has Humanoid (is a character)
  - Calls `onHit()` callback with hit character
  - Logs hit information

## Debug Logging

Enable console output to see the full flow:
- `[MouseTracker]` - Client mouse tracking
- `[MouseComponent]` - Server receiving mouse data
- `[InputComponent]` - Input processing with mouse position
- `[AbilityComponent]` - Ability activation flow
- `[M1 Server]` - Raycast execution and results

## Testing

1. Start the game with a character that has the M1 ability
2. Open console to see debug messages
3. Move mouse around the world
4. Click M1 (left mouse button)
5. Observe:
   - Mouse position being sent from client
   - Server receiving and processing the position
   - Raycast being performed from entity to mouse position
   - Hit detection on characters or terrain

## Test Commands (via chat)
- `/testraycast` - Show test instructions
- `/togglerayvis` - Toggle visual ray display
- `/debugmouse` - Show current mouse data on server

## Key Components

### Required Network Events
- `UpdateMouse` - Client → Server mouse position updates

### Required Components
- `MouseComponent` - Tracks mouse position per character
- `InputComponent` - Processes input with mouse data
- `AbilityComponent` - Routes mouse data to abilities

### Configuration
- Mouse update rate: 100ms (configurable in MouseTracker)
- Mouse data max age: 500ms (configurable in MouseComponent)
- Raycast range: 100 studs (configurable in M1 ability)

## Troubleshooting

### Mouse position not reaching server
1. Check if `UpdateMouse` event exists in network definitions
2. Verify MouseTracker client script is running
3. Check console for `[MouseTracker]` messages

### Raycast not using mouse position
1. Check if MouseComponent is registered in CharacterManager
2. Verify InputComponent is retrieving mouse position
3. Check console for `[InputComponent]` messages showing position

### Raycast not hitting targets
1. Verify target has a Humanoid component
2. Check raycast distance (default 100 studs)
3. Enable ray visualization with `/togglerayvis`

## Performance Considerations

1. **Mouse Updates**: Throttled to 100ms to reduce network traffic
2. **Debug Logging**: Only 10% of updates logged to reduce spam
3. **Data Validation**: Mouse data expires after 500ms to prevent stale data
4. **Raycast Optimization**: Single ray per M1 activation, not continuous