# Mouse Target Controller - Refactored Architecture

This document describes the refactored mouse targeting system that replaced the original monolithic `MouseController.client.luau`.

## 🎯 Overview

The original mouse controller was a single file with ~220 lines of tightly coupled code. It has been refactored into a modular, type-safe, and maintainable system with clear separation of concerns.

## 📁 Architecture

### Core Modules

1. **`MouseTargetTypes.luau`** - Type definitions for the entire system
2. **`MouseTargetConfig.luau`** - Configuration constants and settings  
3. **`TargetValidator.luau`** - Target validation logic
4. **`HighlightManager.luau`** - Target highlighting and visual effects
5. **`DebugManager.luau`** - Debug visualization and logging
6. **`MouseTargetController.luau`** - Main controller that coordinates everything

### Client Script

- **`MouseController.client.luau`** - Simplified client script (~30 lines)

## 🚀 Key Improvements

### ✅ Modular Design
- **Single Responsibility**: Each module has one clear purpose
- **Loose Coupling**: Modules communicate through well-defined interfaces
- **High Cohesion**: Related functionality is grouped together

### ✅ Type Safety
- **Strict Mode**: All files use `--!strict` for maximum type safety
- **Export Types**: Clear type definitions for all public APIs
- **Type Annotations**: Comprehensive type coverage

### ✅ Configuration Management
- **Centralized Config**: All settings in one location
- **Environment-Specific**: Easy to toggle debug features
- **Type-Safe**: Configuration is type-checked

### ✅ Debug Features
- **Conditional Debug**: Debug features can be toggled on/off
- **Visual Debugging**: Optional raycast visualization
- **Structured Logging**: Consistent logging format

### ✅ Resource Management
- **Proper Cleanup**: All managers implement destroy() methods
- **Memory Efficient**: Single highlight instance, proper tween cleanup
- **Connection Management**: Proper connection handling

## 📖 Usage Examples

### Basic Usage
```lua
local MouseTargetController = require(game.ReplicatedStorage.Modules.Utility.MouseTargetController)

local controller = MouseTargetController.new()
controller:start()

-- Get current target
local target = controller:getCurrentTarget()

-- Listen for target changes
local disconnect = controller:onTargetChanged(function(newTarget, oldTarget)
    print("Target changed:", newTarget and newTarget.Name or "none")
end)

-- Clean up
disconnect()
controller:destroy()
```

### Custom Configuration
```lua
local config = {
    highlight = {
        fillColor = Color3.fromRGB(0, 255, 0),
        outlineColor = Color3.fromRGB(0, 200, 0),
        fillTransparency = 0.5,
        outlineTransparency = 0.1,
        glowDuration = 1.0,
        glowIntensity = 0.2,
    },
    raycast = {
        maxDistance = 500,
        ignoreWater = false,
        filterType = Enum.RaycastFilterType.Blacklist,
    },
    debug = {
        enabled = true,
        raycastVisualization = true,
        logging = true,
    },
}

local controller = MouseTargetController.new(config)
```

### Target Validation Customization
Target validation supports multiple methods:
- **Attributes**: `model:SetAttribute("Targetable", false)`
- **Tags**: `CollectionService:AddTag(model, "NonTargetable")`
- **Humanoid Check**: Models with Humanoids are targetable by default

## 🔧 Configuration Options

### Highlight Configuration
- `fillColor`: Color of the highlight fill
- `outlineColor`: Color of the highlight outline  
- `fillTransparency`: Transparency of the fill (0-1)
- `outlineTransparency`: Transparency of the outline (0-1)
- `glowDuration`: Duration of glow animation in seconds
- `glowIntensity`: Intensity of the glow effect (0-1)

### Raycast Configuration
- `maxDistance`: Maximum raycast distance
- `ignoreWater`: Whether to ignore water in raycasts
- `filterType`: Raycast filter type (Exclude/Include)

### Debug Configuration
- `enabled`: Master debug toggle
- `raycastVisualization`: Show visual raycast representation
- `logging`: Enable debug logging

## 🧪 Testing

The modular design makes testing much easier:

```lua
-- Test target validation
local TargetValidator = require(game.ReplicatedStorage.Modules.Utility.TargetValidator)
local isValid = TargetValidator.isTargetable(someModel, Players.LocalPlayer)

-- Test highlight manager
local HighlightManager = require(game.ReplicatedStorage.Modules.Utility.HighlightManager)
local highlighter = HighlightManager.new(config.highlight)
highlighter:setTarget(someModel)
```

## 🎭 Migration Guide

### For Scripts Using the Old System

**Old way:**
```lua
-- Access via ObjectValue
local currentTargetValue = Player:FindFirstChild("CurrentTarget")
local target = currentTargetValue.Value
```

**New way:**
```lua
-- Access via controller
local controller = _G.MouseTargetController
local target = controller:getCurrentTarget()

-- Or listen for changes
controller:onTargetChanged(function(newTarget, oldTarget)
    -- Handle target change
end)
```

### For Scripts That Modified Targeting Logic

**Old way:** Direct modification of the monolithic file  
**New way:** Extend or replace individual modules:

```lua
-- Custom target validator
local CustomValidator = require(script.CustomTargetValidator)
local MouseTargetController = require(game.ReplicatedStorage.Modules.Utility.MouseTargetController)

-- Patch the validation logic
local originalValidator = require(game.ReplicatedStorage.Modules.Utility.TargetValidator)
originalValidator.isTargetable = CustomValidator.isTargetable
```

## 🎯 Benefits Summary

1. **Maintainability**: Easy to modify individual components
2. **Testability**: Each module can be tested in isolation
3. **Reusability**: Modules can be used in other systems
4. **Debuggability**: Comprehensive debug features and logging
5. **Performance**: Efficient resource management and cleanup
6. **Type Safety**: Full type coverage prevents runtime errors
7. **Documentation**: Self-documenting code with clear interfaces

The refactored system maintains 100% backward compatibility while providing a much cleaner foundation for future development.
