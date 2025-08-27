# Network Ping Compensation System

## Overview

This system implements client-first ability casting with server-side damage application based on travel time and network latency compensation using `GetNetworkPing()`.

## How It Works

### 1. Client-Side Casting
- Client immediately executes ability visuals/effects for responsive gameplay
- Client sends ability cast request to server via `RequestAbilityCast` event
- Includes target position and other relevant data

### 2. Server-Side Processing
- Server receives ability cast request with network timestamp
- Uses `player:GetNetworkPing()` to get current network latency
- Calculates travel time based on projectile speed and distance
- Applies network compensation: `compensatedTime = travelTime - (networkPing * 0.5)`

### 3. Damage Application
- Server applies damage after the compensated travel time
- This accounts for the time it took the client's input to reach the server
- Results in more accurate hit timing despite network latency

## Key Components

### Server Scripts
- `src/ServerScriptService/Scripts/AbilityManager.server.luau` - Handles `RequestAbilityCast` events
- `src/ServerStorage/Modules/Components/AbilityComponent.luau` - Enhanced with legacy ability support

### Client Scripts
- `src/StarterPlayerScripts/NetworkAbilityCaster.client.luau` - Sends ability cast requests
- `src/StarterPlayerScripts/NetworkPingDisplay.client.luau` - Shows ping information for debugging

### Modified Abilities
- `src/ReplicatedStorage/Modules/Abilities/Rem/M1.luau` - Updated with network ping compensation

## Network Compensation Formula

```lua
local networkPing = player:GetNetworkPing()
local distance = (targetPosition - entityPosition).Magnitude
local travelTime = distance / PROJECTILE_SPEED
local compensatedTravelTime = math.max(0, travelTime - (networkPing * 0.5))

task.delay(compensatedTravelTime, function()
    -- Apply damage here
    onHit(target)
end)
```

## Benefits

1. **Responsive Gameplay**: Client sees immediate visual feedback
2. **Fair Damage Timing**: Server compensates for network latency
3. **Consistent Experience**: Players with different ping levels get similar gameplay
4. **Accurate Hit Detection**: Damage is applied at the correct time relative to projectile travel

## Usage Example

```lua
-- Client sends ability cast request
NetworkClient.RequestAbilityCast.Fire({
    AbilityId = 1, -- M1 ability
    Target = targetModel,
    Position = mouseHitPosition
})

-- Server processes with ping compensation
local networkPing = player:GetNetworkPing()
local compensatedDelay = travelTime - (networkPing * 0.5)
task.delay(compensatedDelay, function()
    applyDamage(target, damage)
end)
```

## Configuration

- `PROJECTILE_SPEED`: Speed of projectiles in studs per second (currently 100)
- `CAST_COOLDOWN`: Minimum time between ability casts (currently 0.1 seconds)
- Network compensation factor: Currently uses 50% of ping time (`networkPing * 0.5`)

## Testing

1. Enable the NetworkPingDisplay to see current ping
2. Cast abilities and observe damage timing
3. Test with different network conditions (you can simulate lag in Studio)
4. Verify that higher ping players don't experience delayed damage application

## Future Enhancements

- Adaptive compensation based on ping stability
- Client-side prediction rollback for mispredicted hits
- Lag compensation for moving targets
- Advanced interpolation for very high latency scenarios
