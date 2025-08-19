--!strict
--[[
    Mouse Target Controller
    A clean, modular system for handling mouse-based target selection
    
    @author: GitHub Copilot
    @version: 1.0.0
]]

--// Services \\--
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local hitboxFolder = Instance.new("Folder")
hitboxFolder.Name = "Hitboxes"
hitboxFolder.Parent = workspace

--// Modules \\--
local MouseTargetTypes = require(game.ReplicatedStorage.Modules.Types.MouseTargetTypes)
local MouseTargetConfig = require(game.ReplicatedStorage.Modules.Utility.MouseTargetConfig)
local TargetValidator = require(game.ReplicatedStorage.Modules.Utility.TargetValidator)
local HighlightManager = require(game.ReplicatedStorage.Modules.Utility.HighlightManager)
local DebugManager = require(game.ReplicatedStorage.Modules.Utility.DebugManager)
local _Constants = require(game.ReplicatedStorage.Modules.Utility.Constants)

--// Types \\--
type MouseTargetConfig = MouseTargetTypes.MouseTargetConfig
type TargetChangedCallback = MouseTargetTypes.TargetChangedCallback

export type MouseTargetController = {
    getCurrentTarget: (self: MouseTargetController) -> Model?,
    onTargetChanged: (self: MouseTargetController, callback: TargetChangedCallback) -> () -> (),
    setConfig: (self: MouseTargetController, config: MouseTargetConfig) -> (),
    start: (self: MouseTargetController) -> (),
    stop: (self: MouseTargetController) -> (),
    destroy: (self: MouseTargetController) -> (),
    
    _config: MouseTargetConfig,
    _player: Player,
    _camera: Camera,
    _mouse: Mouse,
    _currentTarget: Model?,
    _currentTargetValue: ObjectValue,
    _highlightManager: any, -- HighlightManager type
    _debugManager: any, -- DebugManager type
    _callbacks: {TargetChangedCallback},
    _connection: RBXScriptConnection?,
    _running: boolean,
    _characterHitboxes: {[Model]: Part}, -- Mapping of character to hitbox
    _hitboxesCharacter: {[Part]: Model}, -- Mapping of hitbox to character
    _hitboxesIter: {Part}, -- Array of hitboxes for iteration
}

--// Module \\--
local MouseTargetController = {}
MouseTargetController.__index = MouseTargetController

--[[
    Creates a new mouse target controller instance
    
    @param config - Optional configuration override
    @return MouseTargetController - New controller instance
]]
function MouseTargetController.new(config: MouseTargetConfig?): MouseTargetController
    local self = setmetatable({}, MouseTargetController) :: any
    
    self._config = config or MouseTargetConfig
    self._player = Players.LocalPlayer
    self._camera = workspace.CurrentCamera
    self._mouse = self._player:GetMouse()
    self._currentTarget = nil
    self._callbacks = {}
    self._connection = nil
    self._running = false
    self._characterHitboxes = {} -- Initialize hitbox mapping
	self._hitboxesCharacter = {}
	self._hitboxesIter = {}

    -- Create current target value for other scripts
    local currentTargetValue = Instance.new("ObjectValue")
    currentTargetValue.Name = "CurrentTarget"
    currentTargetValue.Value = nil
    currentTargetValue.Parent = self._player
    self._currentTargetValue = currentTargetValue
    
    -- Initialize managers
    self._highlightManager = HighlightManager.new(self._config.highlight)
    self._debugManager = DebugManager.new(self._config.debug)
    
    return self
end

--[[
    Gets the currently targeted model
    
    @return Model? - The current target, or nil if none
]]
function MouseTargetController:getCurrentTarget(): Model?
    return self._currentTarget
end

--[[
    Registers a callback for when the target changes
    
    @param callback - Function to call when target changes
    @return function - Disconnect function to remove the callback
]]
function MouseTargetController:onTargetChanged(callback: TargetChangedCallback): () -> ()
    table.insert(self._callbacks, callback)
    
    return function()
        local index = table.find(self._callbacks, callback)
        if index then
            table.remove(self._callbacks, index)
        end
    end
end

--[[
    Updates the configuration
    
    @param config - New configuration to apply
]]
function MouseTargetController:setConfig(config: MouseTargetConfig): ()
    self._config = config
    -- Recreate managers with new config
    self._highlightManager:destroy()
    self._debugManager:destroy()
    self._highlightManager = HighlightManager.new(config.highlight)
    self._debugManager = DebugManager.new(config.debug)
end

--[[
    Creates an invisible hitbox around a character for easier hovering
    
    @param character - The character model to create a hitbox for
]]
function MouseTargetController:_createHitbox(character: Model): ()
    -- Check if hitbox already exists
    if self._characterHitboxes[character] then
        return
    end
    
    -- Get the character's primary part (usually HumanoidRootPart)
    local primaryPart = character.PrimaryPart
    if not primaryPart then
    -- Try to find HumanoidRootPart directly if PrimaryPart isn't set
        primaryPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not primaryPart then
            return
        end
    end
    
    -- Create the hitbox part
    local hitbox = Instance.new("Part")
    hitbox.Name = "HoverHitbox_" .. character.Name
    hitbox.Anchored = true
    hitbox.CanCollide = false
    hitbox.Transparency = 1 -- Completely invisible
    hitbox.Material = Enum.Material.ForceField
    hitbox.TopSurface = Enum.SurfaceType.Smooth
    hitbox.BottomSurface = Enum.SurfaceType.Smooth
    
    -- Make the hitbox slightly larger than the character
    local characterSize = character:GetExtentsSize()
    hitbox.Size = Vector3.new(
        math.max(characterSize.X + 2, 4), -- Minimum 4 studs wide
        math.max(characterSize.Y + 2, 6), -- Minimum 6 studs tall
        math.max(characterSize.Z + 2, 4)  -- Minimum 4 studs deep
    )
    
    -- Position the hitbox at the character's center
    if primaryPart then
        hitbox.CFrame = primaryPart.CFrame
    end
    
    -- Parent the hitbox to the character so it gets detected by TargetValidator
    hitbox.Parent = hitboxFolder
    
    -- Store reference
    self._characterHitboxes[character] = hitbox
	self._hitboxesCharacter[hitbox] = character
	table.insert(self._hitboxesIter, hitbox)
    
    -- Debug: temporarily make visible to test
    if self._config.debug and self._config.debug.enabled then
        hitbox.Transparency = 0.8
        hitbox.BrickColor = BrickColor.new("Bright red")
    end
    
    -- Set up cleanup when character is removed
    local connection
    connection = character.AncestryChanged:Connect(function()
        if not character.Parent then
            self:_removeHitbox(character)
            if connection then
                connection:Disconnect()
            end
        end
    end)
end

--[[
    Updates hitbox position to match character
    
    @param character - The character to update the hitbox for
]]
function MouseTargetController:_updateHitbox(character: Model): ()
    local hitbox = self._characterHitboxes[character]
    if hitbox and character.PrimaryPart then
        hitbox.CFrame = character.PrimaryPart.CFrame
    end
end

--[[
    Removes and cleans up a character's hitbox
    
    @param character - The character whose hitbox to remove
]]
function MouseTargetController:_removeHitbox(character: Model): ()
    local hitbox = self._characterHitboxes[character]
    if hitbox then
        hitbox:Destroy()
        self._characterHitboxes[character] = nil
        self._hitboxesCharacter[hitbox] = nil
        
        -- Remove from iterator table
        local index = table.find(self._hitboxesIter, hitbox)
        if index then
            table.remove(self._hitboxesIter, index)
        end
    end
end

--[[
    Manages hitboxes for all humanoids in the workspace
]]
function MouseTargetController:_manageHitboxes(): ()
    -- Get all descendants in workspace
    local descendants = workspace:GetDescendants()
    
    for _, descendant in ipairs(descendants) do
        -- Check if it's a humanoid
        if descendant:IsA("Humanoid") and descendant.Health > 0 then
            local character = descendant.Parent
            
            -- Verify it's a valid character with a primary part or HumanoidRootPart
            -- Exclude the local player's character
            if character and character:IsA("Model") and character ~= (self._player.Character :: Instance?) then
                local primaryPart = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
                if primaryPart then
                    -- Create hitbox if it doesn't exist
                    self:_createHitbox(character)
                    -- Update hitbox position
                    self:_updateHitbox(character)
                end
            end
        end
    end
    
    -- Clean up hitboxes for characters that no longer exist or don't have humanoids
    for character: Model, hitbox in pairs(self._characterHitboxes) do
        local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
        if not humanoid or humanoid.Health <= 0 or not character.Parent or not character:IsDescendantOf(workspace) or character == (self._player.Character :: Instance?) then
            self:_removeHitbox(character)
        end
    end
end

--[[
    Starts the mouse targeting system
]]
function MouseTargetController:start(): ()
    if self._running then
        return
    end
    
    self._running = true
    self._debugManager:log("Starting mouse targeting system")
    
    -- Bind to render step for smooth updates
    self._connection = RunService.Heartbeat:Connect(function()
        self:_updateTarget()
        self:_manageHitboxes() -- Manage hitboxes every heartbeat
    end)
end

--[[
    Stops the mouse targeting system
]]
function MouseTargetController:stop(): ()
    if not self._running then
        return
    end
    
    self._running = false
    self._debugManager:log("Stopping mouse targeting system")
    
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil :: any
    end
    
    -- Clear current target
    self:_setCurrentTarget(nil)
    
    -- Clean up all hitboxes
    for character, _ in pairs(self._characterHitboxes) do
        self:_removeHitbox(character)
    end
end

--[[
    Destroys the controller and cleans up all resources
]]
function MouseTargetController:destroy(): ()
    self:stop()
    
    -- Clean up managers
    self._highlightManager:destroy()
    self._debugManager:destroy()
    
    -- Clean up target value
    if self._currentTargetValue then
        self._currentTargetValue:Destroy()
    end
    
    -- Clear callbacks
    self._callbacks = {}
    
    -- Ensure all hitboxes are cleaned up
    for character, _ in pairs(self._characterHitboxes) do
        self:_removeHitbox(character)
    end
end

--[[
    Creates a raycast from the mouse position
    
    @return RaycastResult? - The raycast result, if any
]]
function MouseTargetController:_createMouseRaycast(): RaycastResult?
    if not self._player.Character then
        return nil
    end

    -- Set up raycast parameters - only hit hitboxes
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = self._config.raycast.filterType  -- Use config filter type
    raycastParams.IgnoreWater = self._config.raycast.ignoreWater
    raycastParams.FilterDescendantsInstances = self._hitboxesIter

    -- Get mouse position and create world ray
    local mousePos = UserInputService:GetMouseLocation()
    local unitRay : Ray = (self._camera :: Camera):ViewportPointToRay(mousePos.X, mousePos.Y)

    -- Step 1: Find the target point in the world from the camera
    local cameraRaycast = workspace:Raycast(unitRay.Origin, unitRay.Direction * self._config.raycast.maxDistance, raycastParams)
    local targetPoint = cameraRaycast and cameraRaycast.Position or (unitRay.Origin + unitRay.Direction * self._config.raycast.maxDistance)

    -- Step 2: Cast from the character's head toward the target point
    local head : Part = self._player.Character:FindFirstChild("Head") :: any
    if not head then
        return nil
    end
    
    -- Use the same origin point for both direction calculation and raycast
    local rayOrigin = head.Position
    local direction = (targetPoint - rayOrigin).Unit * self._config.raycast.maxDistance

    return workspace:Raycast(rayOrigin, direction, raycastParams)
end


--[[
    Updates the current target based on mouse raycast
]]
function MouseTargetController:_updateTarget(): ()
    local raycastResult = self:_createMouseRaycast()
    
    -- Update debug visualization
    if raycastResult then
        local mousePos = UserInputService:GetMouseLocation()
        local unitRay = self._camera:ScreenPointToRay(mousePos.X, mousePos.Y)
        self._debugManager:updateRaycastVisual(raycastResult, unitRay)
    end
    
    local hitPart = raycastResult and raycastResult.Instance
    local newTarget: Model? = nil
    
    -- If we hit a hitbox, get the character it belongs to
    if hitPart and self._hitboxesCharacter[hitPart] then
        local character = self._hitboxesCharacter[hitPart]
        -- Validate this character as a targetable model
        if TargetValidator.isTargetable(character, self._player) then
            newTarget = character
        end
    end
    
    -- Check if current target was destroyed
    if self._currentTarget and not self._currentTarget:IsDescendantOf(game) then
        newTarget = nil
    end
    
    -- Update target if it changed
    local currentTarget: Model? = self._currentTarget
    if newTarget ~= currentTarget then
        self:_setCurrentTarget(newTarget)
    end
end

--[[
    Sets the current target and triggers callbacks
    
    @param newTarget - The new target model, or nil to clear
]]
function MouseTargetController:_setCurrentTarget(newTarget: Model?): ()
    local oldTarget = self._currentTarget
    self._currentTarget = newTarget
    self._currentTargetValue.Value = newTarget
    
    -- Update highlight
    self._highlightManager:setTarget(newTarget)
    
    -- Log target change
    if newTarget then
        self._debugManager:log(`Targeting: {newTarget.Name}`)
    else
        self._debugManager:log("No target")
    end
    
    -- Fire callbacks
    for _, callback in ipairs(self._callbacks) do
        task.spawn(callback, newTarget, oldTarget)
    end
end

return MouseTargetController
