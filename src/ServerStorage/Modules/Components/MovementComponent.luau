--!strict
-- Movement Component - Manages character movement and speeds

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(game.ReplicatedStorage.Modules.Utility.Constants)

local MovementComponent = {}

function MovementComponent.Initialize(characterData, config)
    local stateManager = characterData.StateManager
    local humanoid = characterData.Humanoid
    
    -- Get movement speeds from config or constants
    local walkSpeed = (config and config.WalkSpeed) or Constants.DEFAULT_WALK_SPEED or 16
    local runSpeed = (config and config.RunSpeed) or Constants.DEFAULT_RUN_SPEED or 26
    local blockedSpeed = Constants.DEFAULT_BLOCKED_SPEED or 8
    local stunnedSpeed = 0
    
    -- Store speeds in component data
    characterData.Components.Movement = {
        WalkSpeed = walkSpeed,
        RunSpeed = runSpeed,
        BlockedSpeed = blockedSpeed,
        StunnedSpeed = stunnedSpeed
    }
    
    -- Set up movement state change handlers
    stateManager:OnStateChange("IsRunning", function(isRunning: boolean)
        MovementComponent._UpdateMovementSpeed(characterData)
    end)
    
    stateManager:OnStateChange("IsBlocking", function(isBlocking: boolean)
        MovementComponent._UpdateMovementSpeed(characterData)
    end)
    
    stateManager:OnStateChange("IsStunned", function(isStunned: boolean)
        MovementComponent._UpdateMovementSpeed(characterData)
        
        if isStunned then
            -- Disable jumping when stunned
            humanoid.JumpPower = 0
        else
            -- Restore jumping
            humanoid.JumpPower = Constants.DEFAULT_JUMP_POWER or 50
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
    MovementComponent._UpdateMovementSpeed(characterData)
end

function MovementComponent._UpdateMovementSpeed(characterData)
    local stateManager = characterData.StateManager
    local humanoid = characterData.Humanoid
    local movementData = characterData.Components.Movement
    
    if not movementData then return end
    
    -- Check states in priority order
    if stateManager:Get("IsDead") then
        humanoid.WalkSpeed = 0
    elseif stateManager:Get("IsStunned") then
        humanoid.WalkSpeed = movementData.StunnedSpeed
    elseif stateManager:Get("IsBlocking") then
        humanoid.WalkSpeed = movementData.BlockedSpeed
    elseif stateManager:Get("IsRunning") then
        -- Only run if we have stamina
        local stamina = stateManager:Get("Stamina")
        if stamina > 0 then
            humanoid.WalkSpeed = movementData.RunSpeed
        else
            humanoid.WalkSpeed = movementData.WalkSpeed
            stateManager:Set("IsRunning", false)
        end
    else
        humanoid.WalkSpeed = movementData.WalkSpeed
    end
end

function MovementComponent.Update(characterData, dt: number)
    local stateManager = characterData.StateManager
    local humanoid = characterData.Humanoid
    
    if stateManager:Get("IsDead") then return end
    
    -- Auto-disable running if no stamina
    if stateManager:Get("IsRunning") and stateManager:Get("Stamina") <= 0 then
        stateManager:Set("IsRunning", false)
    end
    
    -- Handle movement state based on humanoid state
    local moveVector = humanoid.MoveDirection
    local isMoving = moveVector.Magnitude > 0.1
    
    -- Could add movement-based effects here
    if isMoving and stateManager:Get("IsRunning") then
        -- Running movement effects could be added here
    end
end

function MovementComponent.Cleanup(characterData)
    if characterData.Components.Movement then
        characterData.Components.Movement = nil
    end
end

return MovementComponent