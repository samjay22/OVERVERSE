# OnCharacterCreation Hook Documentation

## Overview
The `OnCharacterCreation` method allows you to customize characters before they are placed in the workspace. This hook is called during the character spawning process and gives you full control over character modifications.

## How It Works

### 1. Method Signature
```lua
function CharacterInstance:OnCharacterCreation(player: Player, character: Model, config: CharacterConfig?)
    -- Your customization code here
end
```

### 2. Parameters
- **player**: The Player instance who owns this character
- **character**: The character Model that was just created (not yet in workspace)
- **config**: Optional character configuration passed to SpawnCharacter

### 2. When It's Called
The hook is invoked in the `SpawnCharacter` method, specifically:
1. Character model is created
2. **OnCharacterCreation is called** ← You customize here
3. Character is parented to workspace
4. OnSpawn signal is fired

### 3. Implementation Location
- **File**: `src/ServerStorage/Modules/Entities/Character.luau`
- **Method**: `SpawnCharacter` (around line 220-260)

## Usage Examples

### Basic Weapon Addition
```lua
local Character = require(game.ServerStorage.Modules.Entities.Character)
local characterManager = Character.New()

function characterManager:OnCharacterCreation(player: Player, character: Model, config: CharacterConfig?)
    -- Add a sword to the character
    local sword = game.ReplicatedStorage.Weapons.Sword:Clone()
    sword.Parent = character
    
    -- Weld it to the character's hand
    local humanoid = character:FindFirstChild("Humanoid")
    if humanoid then
        local rightHand = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
        if rightHand and sword:FindFirstChild("Handle") then
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = rightHand
            weld.Part1 = sword.Handle
            weld.Parent = sword
        end
    end
    
    print(`Added weapon to {player.Name}'s character`)
end
```

### Animation Setup
```lua
function characterManager:OnCharacterCreation(player: Player, character: Model, config: CharacterConfig?)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    -- Create animation controller
    local animationFolder = Instance.new("Folder")
    animationFolder.Name = "CustomAnimations"
    animationFolder.Parent = character
    
    -- Load combat animations
    local animations = {
        Attack1 = "rbxassetid://123456789",
        Attack2 = "rbxassetid://987654321",
        Block = "rbxassetid://555666777"
    }
    
    for animName, animId in pairs(animations) do
        local animation = Instance.new("Animation")
        animation.Name = animName
        animation.AnimationId = animId
        animation.Parent = animationFolder
    end
    
    print(`Set up animations for {player.Name}`)
end
```

### Visual Customization
```lua
function characterManager:OnCharacterCreation(player: Player, character: Model, config: CharacterConfig?)
    -- Add custom accessories based on player data
    local crown = game.ReplicatedStorage.Accessories.Crown:Clone()
    crown.Parent = character
    
    -- Modify body colors based on config
    local bodyColors = character:FindFirstChild("Body Colors")
    if bodyColors then
        if config and config.CustomColors then
            bodyColors.HeadColor3 = config.CustomColors.Head or Color3.fromRGB(255, 220, 177)
            bodyColors.TorsoColor3 = config.CustomColors.Torso or Color3.fromRGB(0, 100, 200)
        end
    end
    
    -- Add special effects for VIP players
    if player:GetRankInGroup(123456) >= 100 then -- Example group check
        local aura = Instance.new("SelectionBox")
        aura.Color3 = Color3.fromRGB(255, 215, 0)
        aura.Transparency = 0.8
        aura.Adornee = character:FindFirstChild("HumanoidRootPart")
        aura.Parent = character
    end
end
```

### Character Stats Modification
```lua
function characterManager:OnCharacterCreation(player: Player, character: Model, config: CharacterConfig?)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    -- Set custom health from config or default
    local maxHealth = (config and config.MaxHealth) or 150
    humanoid.MaxHealth = maxHealth
    humanoid.Health = maxHealth
    
    -- Modify walk speed based on character type
    humanoid.WalkSpeed = (config and config.WalkSpeed) or 20
    humanoid.JumpPower = (config and config.JumpPower) or 60
    
    -- Add custom character values
    local stats = Instance.new("Folder")
    stats.Name = "Stats"
    stats.Parent = character
    
    local level = Instance.new("IntValue")
    level.Name = "Level"
    level.Value = 1
    level.Parent = stats
    
    local experience = Instance.new("IntValue")
    experience.Name = "Experience"
    experience.Value = 0
    experience.Parent = stats
    
    print(`Applied stats to {player.Name}: HP={maxHealth}, Speed={humanoid.WalkSpeed}`)
end
```

## Integration with Game Systems

### With Weapon System
```lua
local WeaponService = require(game.ServerStorage.Modules.Services.WeaponService)

function characterManager:OnCharacterCreation(player: Player, character: Model, config: CharacterConfig?)
    -- Load player's equipped weapon from data or config
    local weaponId = (config and config.WeaponId) or "Sword" -- Default or from player data
    local weapon = WeaponService:CreateWeapon(weaponId)
    
    if weapon then
        WeaponService:EquipWeapon(character, weapon)
        print(`Equipped {weaponId} to {player.Name}`)
    end
end
```

### With Ability System
```lua
local AbilityService = require(game.ServerStorage.Modules.Services.AbilityService)

function characterManager:OnCharacterCreation(player: Player, character: Model, config: CharacterConfig?)
    -- Setup player's abilities from config or default loadout
    local abilities = (config and config.AbilityLoadout) or {"Dash", "Heal"} -- From config or default
    
    for _, abilityId in ipairs(abilities) do
        AbilityService:GrantAbility(character, abilityId)
    end
    
    print(`Granted {#abilities} abilities to {player.Name}`)
end
```

## Best Practices

### 1. Error Handling
```lua
function characterManager:OnCharacterCreation(player: Player, character: Model, config: CharacterConfig?)
    local success, err = pcall(function()
        -- Your customization code here
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            warn(`No humanoid found in character for {player.Name}`)
            return
        end
        
        -- Safe customization code
        print(`Customizing character for {player.Name}`)
    end)
    
    if not success then
        warn(`Error in OnCharacterCreation for {player.Name}: {err}`)
    end
end
```

### 2. Performance Considerations
```lua
function characterManager:OnCharacterCreation(player: Player, character: Model, config: CharacterConfig?)
    -- Cache frequently used services
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local TweenService = game:GetService("TweenService")
    
    -- Batch operations when possible
    local modifications = {}
    
    -- Collect all modifications first
    modifications.weapon = ReplicatedStorage.Weapons.Sword:Clone()
    modifications.accessory = ReplicatedStorage.Accessories.Hat:Clone()
    
    -- Apply all at once
    for _, item in pairs(modifications) do
        item.Parent = character
    end
    
    print(`Applied {#modifications} modifications to {player.Name}`)
end
```

### 3. Networking Awareness
```lua
function characterManager:OnCharacterCreation(player: Player, character: Model, config: CharacterConfig?)
    -- Remember: Character is not in workspace yet!
    -- Don't try to fire client events or use character position
    
    -- ✅ Good: Modify character structure
    local weapon = game.ReplicatedStorage.Weapons.Sword:Clone()
    weapon.Parent = character
    
    -- ✅ Good: Access player and config data
    print(`Customizing for player: {player.Name}, UserId: {player.UserId}`)
    if config then
        print("Config provided:", config.MaxHealth or "No health config")
    end
    
    -- ❌ Bad: Try to use world position (character not in workspace)
    -- local position = character.HumanoidRootPart.Position -- Will error!
end
```

## Technical Details

### Execution Flow
1. `SpawnCharacter` method called
2. `_CreateCharacterModel` creates character model
3. **`OnCharacterCreation` hook called** ← Your customizations happen here
4. Character parented to workspace via `_CreateCharacterModel(parentToWorkspace: true)`
5. `OnSpawn` signal fired
6. Client notifications sent

### Method Override
The `OnCharacterCreation` method is designed to be overridden:

```lua
-- Default implementation (does nothing)
-- This property is initialized as nil in Character.New()
self.OnCharacterCreation = nil :: ((player: Player, characterModel: Model, config: CharacterConfig?) -> ())?

-- Your override
local characterManager = Character.New()
function characterManager:OnCharacterCreation(player: Player, character: Model, config: CharacterConfig?)
    -- Your customization code
    print(`Customizing character for {player.Name}`)
end
```

## Testing

Use the provided test script at `src/ServerStorage/TestCharacterCreation.server.luau` to verify your implementation:

```lua
-- The test script sets up an example OnCharacterCreation hook
-- and connects to Players.PlayerAdded to test with real players
```

## Troubleshooting

### Common Issues

1. **Character not in workspace**: Remember the character hasn't been parented to workspace yet
2. **Missing humanoid**: Always check for humanoid existence before modifying
3. **Timing issues**: All modifications should be synchronous in the hook
4. **Memory leaks**: Clean up any connections or temporary objects

### Debugging
```lua
function characterManager:OnCharacterCreation(player: Player, character: Model, config: CharacterConfig?)
    print("=== OnCharacterCreation Debug Info ===")
    print("Player:", player.Name, "UserId:", player.UserId)
    print("Character:", character.Name)
    print("Character parent:", character.Parent) -- Should be nil
    print("Character children count:", #character:GetChildren())
    print("Config provided:", config ~= nil)
    if config then
        print("Config details:", config.MaxHealth, config.MaxStamina)
    end
    print("=======================================")
    
    -- Your customization code with debug prints
end
```
