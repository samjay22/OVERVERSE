--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- MouseComponent - Tracks client mouse position and hit data for server-side use

local Targeting = require(ReplicatedStorage.Modules.CoreClient.Targeting).new()
local BaseComponent = require(script.Parent.BaseComponent)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

type MouseComponentData = {
    MouseHitPosition: Vector3,
    MouseTarget: Instance?,
    MouseHitNormal: Vector3,
    LastUpdateTime: number,
    IsValid: boolean,
    _networkCleanup: (() -> ())?,
}

export type MouseComponent = BaseComponent.BaseComponent & {
    UpdateMousePosition: (self: MouseComponent, characterData: CharacterTypes.internalCharacter, hitPosition: Vector3, target: Instance?, normal: Vector3?) -> (),
    GetMouseHitPosition: (self: MouseComponent, characterData: CharacterTypes.internalCharacter) -> Vector3?,
    GetMouseTarget: (self: MouseComponent, characterData: CharacterTypes.internalCharacter) -> Instance?,
    GetMouseHitNormal: (self: MouseComponent, characterData: CharacterTypes.internalCharacter) -> Vector3?,
    IsMouseDataValid: (self: MouseComponent, characterData: CharacterTypes.internalCharacter, maxAge: number?) -> boolean,
}

local MouseComponent = BaseComponent:extend("Mouse") :: any
local DEFAULT_MOUSE_POSITION = Vector3.new(0, 0, 0)
local DEFAULT_MOUSE_NORMAL = Vector3.new(0, 1, 0)
local MOUSE_DATA_MAX_AGE = 0.5 -- Mouse data older than this is considered stale

function MouseComponent:Initialize(characterData: CharacterTypes.internalCharacter, config: any?)
    BaseComponent.Initialize(self, characterData, config)
        
    local componentData: MouseComponentData = {
        MouseHitPosition = DEFAULT_MOUSE_POSITION,
        MouseTarget = nil,
        MouseHitNormal = DEFAULT_MOUSE_NORMAL,
        LastUpdateTime = 0,
        IsValid = false,
        Enabled = true,
    }
    
    characterData.Components.Mouse = componentData :: any
  
    -- Also update StateManager for other components to access
    characterData.StateManager:Set("MouseHitPosition", DEFAULT_MOUSE_POSITION :: any)
    characterData.StateManager:Set("MouseTarget", nil :: any)
    characterData.StateManager:Set("MouseHitNormal", DEFAULT_MOUSE_NORMAL :: any)
    
    -- Set up network listener for mouse updates if player exists
    local player = characterData.Player or (characterData.PlayerId and game.Players:GetPlayerByUserId(characterData.PlayerId))
    if player then
        self:_SetupNetworkListener(characterData, player)
    end
end

function MouseComponent:_SetupNetworkListener(characterData: CharacterTypes.internalCharacter, player: Player)
    local NetworkServer = require(game.ReplicatedStorage.Modules.Network.Server)
    
    if NetworkServer and NetworkServer.UpdateMouse then
        -- Store connection for cleanup
        local connection = NetworkServer.UpdateMouse.On(function(sendingPlayer: Player, data: {
            MouseHit: Vector3,
            MouseUnit: Vector3,
            Origin: Vector3,
            MouseScreenPosition: Vector3
        })
            -- Validate this is the correct player
            if sendingPlayer ~= player then
                return
            end
            
            -- Update mouse data using MouseHit position
            if data and data.MouseHit then
                -- MouseUnit can be used as the normal or we can calculate our own
                self:UpdateMousePosition(
                    characterData, 
                    data.MouseHit,  -- The hit position
                    nil,  -- Target will come from client later if needed
                    data.MouseUnit  -- Use unit vector as normal direction
                )
            end
        end)
        
        -- Store cleanup function for later
        characterData.Components.Mouse._networkCleanup = connection
    else
        warn("MouseComponent: UpdateMouse network event not found")
    end
end

function MouseComponent:Update(characterData: CharacterTypes.internalCharacter, dt: number)
    if not self:IsEnabled(characterData) then
        return
    end
    
    local component = characterData.Components.Mouse :: MouseComponentData
    if not component then
        return
    end

    component.MouseTarget = (Targeting :: any):GetTarget(characterData.Entity.player :: Player)
    
    -- Check if mouse data is stale
    local currentTime = tick()
    if component.IsValid and (currentTime - component.LastUpdateTime) > MOUSE_DATA_MAX_AGE then
        component.IsValid = false
        -- Don't reset position, just mark as invalid
    end
end

function MouseComponent:UpdateMousePosition(
    characterData: CharacterTypes.internalCharacter, 
    hitPosition: Vector3, 
    target: Instance?, 
    normal: Vector3?
)
    local component = characterData.Components.Mouse :: MouseComponentData
    if not component then
        return
    end
    
    -- Debug logging (disabled for performance)
    -- if math.random() < 0.01 then -- Log 1% to reduce spam
    --     warn(`[MouseComponent] Updated mouse position for {characterData.Name or "Unknown"} - Position: {hitPosition}`)
    -- end
    
    -- Update component data
    component.MouseHitPosition = hitPosition
    component.MouseHitNormal = normal or DEFAULT_MOUSE_NORMAL
    component.LastUpdateTime = tick()
    component.IsValid = true
    component.MouseTarget = (Targeting :: any):GetTarget(characterData.Entity.player :: Player)
    
    -- Update state manager for other components
    characterData.StateManager:Set("MouseHitPosition", hitPosition :: any)
    characterData.StateManager:Set("MouseTarget", component.MouseTarget :: any)
    characterData.StateManager:Set("MouseHitNormal", component.MouseHitNormal :: any)
end

function MouseComponent:GetMouseHitPosition(characterData: CharacterTypes.internalCharacter): Vector3?
    local component = characterData.Components.Mouse :: MouseComponentData
    if not component or not component.IsValid then
        return nil
    end
    
    return component.MouseHitPosition
end

function MouseComponent:GetMouseTarget(characterData: CharacterTypes.internalCharacter): Instance?
    local component = characterData.Components.Mouse :: MouseComponentData
    if not component or not component.IsValid then
        return nil
    end
    
    return component.MouseTarget
end

function MouseComponent:GetMouseHitNormal(characterData: CharacterTypes.internalCharacter): Vector3?
    local component = characterData.Components.Mouse :: MouseComponentData
    if not component or not component.IsValid then
        return nil
    end
    
    return component.MouseHitNormal
end

function MouseComponent:IsMouseDataValid(characterData: CharacterTypes.internalCharacter, maxAge: number?): boolean
    local component = characterData.Components.Mouse :: MouseComponentData
    if not component or not component.IsValid then
        return false
    end
    
    local age = tick() - component.LastUpdateTime
    local threshold = maxAge or MOUSE_DATA_MAX_AGE
    
    return age <= threshold
end

function MouseComponent:Cleanup(characterData: CharacterTypes.internalCharacter)
    local component = characterData.Components.Mouse :: MouseComponentData
    if component then
        -- Call cleanup function if it exists
        if component._networkCleanup then
            component._networkCleanup()
            component._networkCleanup = nil
        end
        
        -- Clear data
        component.MouseHitPosition = DEFAULT_MOUSE_POSITION
        component.MouseTarget = nil
        component.MouseHitNormal = DEFAULT_MOUSE_NORMAL
        component.IsValid = false
    end
    
    BaseComponent.Cleanup(self, characterData)
end

-- Create singleton instance for backward compatibility
local instance = MouseComponent.new()

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
    
    -- Additional methods specific to MouseComponent
    UpdateMousePosition = function(characterData, hitPosition, target, normal)
        return instance:UpdateMousePosition(characterData, hitPosition, target, normal)
    end,
    
    GetMouseHitPosition = function(characterData)
        return instance:GetMouseHitPosition(characterData)
    end,
    
    GetMouseTarget = function(characterData)
        return instance:GetMouseTarget(characterData)
    end,
    
    GetMouseHitNormal = function(characterData)
        return instance:GetMouseHitNormal(characterData)
    end,
    
    IsMouseDataValid = function(characterData, maxAge)
        return instance:IsMouseDataValid(characterData, maxAge)
    end,
}

return exports