--!strict
-- Movement Component - Manages character movement and speeds

local BaseComponent = require(script.Parent.BaseComponent)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)
local Constants = require(game.ReplicatedStorage.Modules.Utility.Constants)

type MovementComponentData = {
    WalkSpeed: number,
    RunSpeed: number,
    BlockedSpeed: number,
    StunnedSpeed: number,
    CurrentSpeed: number,
    JumpPower: number,
    IsMoving: boolean,
    MoveDirection: Vector3,
    SpeedMultiplier: number,
}

export type MovementComponent = BaseComponent.BaseComponent & {
    SetWalkSpeed: (self: MovementComponent, characterData: CharacterTypes.internalCharacter, speed: number) -> (),
    SetRunSpeed: (self: MovementComponent, characterData: CharacterTypes.internalCharacter, speed: number) -> (),
    GetCurrentSpeed: (self: MovementComponent, characterData: CharacterTypes.internalCharacter) -> number,
    StartRunning: (self: MovementComponent, characterData: CharacterTypes.internalCharacter) -> boolean,
    StopRunning: (self: MovementComponent, characterData: CharacterTypes.internalCharacter) -> (),
    SetSpeedMultiplier: (self: MovementComponent, characterData: CharacterTypes.internalCharacter, multiplier: number) -> (),
    Jump: (self: MovementComponent, characterData: CharacterTypes.internalCharacter) -> boolean,
    CanMove: (self: MovementComponent, characterData: CharacterTypes.internalCharacter) -> boolean,
}

local DEFAULT_WALK_SPEED = 16
local DEFAULT_RUN_SPEED = 26
local DEFAULT_BLOCKED_SPEED = 8
local DEFAULT_JUMP_POWER = 50

local MovementComponent = BaseComponent:extend("Movement") :: any

function MovementComponent:Initialize(characterData: CharacterTypes.internalCharacter, config: any?)
    BaseComponent.Initialize(self, characterData, config)
    
    local stateManager = characterData.StateManager
    local humanoid = characterData.Humanoid
    
    -- Get movement speeds from config or constants
    local walkSpeed = (config and config.WalkSpeed) or Constants.DEFAULT_WALK_SPEED or DEFAULT_WALK_SPEED
    local runSpeed = (config and config.RunSpeed) or Constants.DEFAULT_RUN_SPEED or DEFAULT_RUN_SPEED
    local blockedSpeed = Constants.DEFAULT_BLOCKED_SPEED or DEFAULT_BLOCKED_SPEED
    local jumpPower = (config and config.JumpPower) or Constants.DEFAULT_JUMP_POWER or DEFAULT_JUMP_POWER
    
    local componentData: MovementComponentData = {
        WalkSpeed = walkSpeed,
        RunSpeed = runSpeed,
        BlockedSpeed = blockedSpeed,
        StunnedSpeed = 0,
        CurrentSpeed = walkSpeed,
        JumpPower = jumpPower,
        IsMoving = false,
        MoveDirection = Vector3.zero,
        SpeedMultiplier = 1,
    }
    
    characterData.Components.Movement = componentData :: any
    
    -- Set initial humanoid values
    humanoid.WalkSpeed = walkSpeed
    humanoid.JumpPower = jumpPower
    
    -- Set up movement state change handlers
    stateManager:OnStateChange("IsRunning", function(isRunning: boolean)
        self:_UpdateMovementSpeed(characterData)
    end)
    
    stateManager:OnStateChange("IsBlocking", function(isBlocking: boolean)
        self:_UpdateMovementSpeed(characterData)
    end)
    
    stateManager:OnStateChange("IsStunned", function(isStunned: boolean)
        self:_UpdateMovementSpeed(characterData)
        
        local component = characterData.Components.Movement :: MovementComponentData
        if isStunned then
            humanoid.JumpPower = 0
        else
            humanoid.JumpPower = component.JumpPower
        end
    end)
    
    stateManager:OnStateChange("IsDead", function(isDead: boolean)
        if isDead then
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
            humanoid.PlatformStand = true
        end
    end)
    
    -- Initial speed setup
    self:_UpdateMovementSpeed(characterData)
end

function MovementComponent:Update(characterData: CharacterTypes.internalCharacter, dt: number)
    if not self:IsEnabled(characterData) then
        return
    end
    
    local component = characterData.Components.Movement :: MovementComponentData
    if not component then
        return
    end
    
    local stateManager = characterData.StateManager
    local humanoid = characterData.Humanoid
    
    if stateManager:Get("IsDead") then
        return
    end
    
    -- Auto-disable running if no stamina
    if stateManager:Get("IsRunning") and stateManager:Get("Stamina") <= 0 then
        self:StopRunning(characterData)
    end
    
    -- Update movement state
    local moveVector = humanoid.MoveDirection
    component.MoveDirection = moveVector
    component.IsMoving = moveVector.Magnitude > 0.1
    
    -- Update state manager
    stateManager:Set("IsMoving", component.IsMoving)
    
    -- Apply any movement effects
    if component.IsMoving and stateManager:Get("IsRunning") then
        -- Running movement effects could be added here
    end
end

function MovementComponent:Cleanup(characterData: CharacterTypes.internalCharacter)
    BaseComponent.Cleanup(self, characterData)
end

function MovementComponent:_UpdateMovementSpeed(characterData: CharacterTypes.internalCharacter)
    local stateManager = characterData.StateManager
    local humanoid = characterData.Humanoid
    local component = characterData.Components.Movement :: MovementComponentData
    
    if not component then
        return
    end
    
    local targetSpeed = component.WalkSpeed
    
    -- Check states in priority order
    if stateManager:Get("IsDead") then
        targetSpeed = 0
    elseif stateManager:Get("IsStunned") then
        targetSpeed = component.StunnedSpeed
    elseif stateManager:Get("IsBlocking") then
        targetSpeed = component.BlockedSpeed
    elseif stateManager:Get("IsRunning") then
        -- Only run if we have stamina
        local stamina = stateManager:Get("Stamina")
        if stamina > 0 then
            targetSpeed = component.RunSpeed
        else
            targetSpeed = component.WalkSpeed
            stateManager:Set("IsRunning", false)
        end
    else
        targetSpeed = component.WalkSpeed
    end
    
    -- Apply speed multiplier
    targetSpeed = targetSpeed * component.SpeedMultiplier
    
    component.CurrentSpeed = targetSpeed
    humanoid.WalkSpeed = targetSpeed
end

function MovementComponent:SetWalkSpeed(characterData: CharacterTypes.internalCharacter, speed: number)
    local component = characterData.Components.Movement :: MovementComponentData
    if component then
        component.WalkSpeed = speed
        self:_UpdateMovementSpeed(characterData)
    end
end

function MovementComponent:SetRunSpeed(characterData: CharacterTypes.internalCharacter, speed: number)
    local component = characterData.Components.Movement :: MovementComponentData
    if component then
        component.RunSpeed = speed
        self:_UpdateMovementSpeed(characterData)
    end
end

function MovementComponent:GetCurrentSpeed(characterData: CharacterTypes.internalCharacter): number
    local component = characterData.Components.Movement :: MovementComponentData
    return component and component.CurrentSpeed or 0
end

function MovementComponent:StartRunning(characterData: CharacterTypes.internalCharacter): boolean
    local stateManager = characterData.StateManager
    
    -- Check if we can run
    if not self:CanMove(characterData) then
        return false
    end
    
    local stamina = stateManager:Get("Stamina")
    if stamina <= 0 then
        return false
    end
    
    stateManager:Set("IsRunning", true)
    return true
end

function MovementComponent:StopRunning(characterData: CharacterTypes.internalCharacter)
    characterData.StateManager:Set("IsRunning", false)
end

function MovementComponent:SetSpeedMultiplier(characterData: CharacterTypes.internalCharacter, multiplier: number)
    local component = characterData.Components.Movement :: MovementComponentData
    if component then
        component.SpeedMultiplier = math.max(0, multiplier)
        self:_UpdateMovementSpeed(characterData)
    end
end

function MovementComponent:Jump(characterData: CharacterTypes.internalCharacter): boolean
    if not self:CanMove(characterData) then
        return false
    end
    
    local humanoid = characterData.Humanoid
    humanoid.Jump = true
    
    return true
end

function MovementComponent:CanMove(characterData: CharacterTypes.internalCharacter): boolean
    local stateManager = characterData.StateManager
    
    return not stateManager:Get("IsDead")
        and not stateManager:Get("IsStunned")
        and self:IsEnabled(characterData)
end

-- Create singleton instance for backward compatibility
local instance = MovementComponent.new()

-- Export both instance methods and static interface for backward compatibility
local exports = {
    -- Instance (for new usage)
    Instance = instance,
    
    -- Static methods (for backward compatibility)
    Initialize = function(characterData, config)
        return instance:Initialize(characterData, config)
    end,
    
    Update = function(characterData, dt)
        return instance:Update(characterData, dt)
    end,
    
    Cleanup = function(characterData)
        return instance:Cleanup(characterData)
    end,
}

return exports