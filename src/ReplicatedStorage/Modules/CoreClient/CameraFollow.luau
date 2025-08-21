--[[ 
    Third-person camera follow system that manages camera offset and positioning.
    Handles smooth camera transitions and maintains proper camera height.
    
    @author: Zach
    @version: 1.0.0
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local IS_CLIENT = RunService:IsClient()
local VECTOR3_UP = Vector3.new(0, 1, 0)

local CAMERA_SETTINGS = table.freeze({
    HeightOffset = 1.5,
    TweenDuration = 0.5,
    TweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.In)
})

local player = Players.LocalPlayer

-------------------------
--// Module \\--
-------------------------
local CameraFollow = {}
CameraFollow.__index = CameraFollow

-------------------------
--// Private Methods \\--
-------------------------

--- Updates the camera offset for the character
-- @param character Model
-- @return nil
function CameraFollow:_updateCameraOffset(character: Model)
    if not character or not character.Parent then return end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end
    
    local head = character:FindFirstChild("Head")
    if not head then return end
    
    local success, cameraOffset = pcall(function()
        return (rootPart.CFrame + VECTOR3_UP * CAMERA_SETTINGS.HeightOffset):PointToObjectSpace(head.Position)
    end)
    
    if not success then return end
    
    TweenService:Create(humanoid, CAMERA_SETTINGS.TweenInfo, {CameraOffset = cameraOffset}):Play()
end

--- Sets up camera offset rendering for a character
-- @param character Model
-- @return nil
function CameraFollow:_setupCameraOffset(character: Model)
    if not character then return end
    
    local bindName = "CameraOffset_" .. player.Name
    RunService:UnbindFromRenderStep(bindName)
    RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value - 1, function()
        self:_updateCameraOffset(character)
    end)
end

--- Handles character added event
-- @param character Model
-- @return nil
function CameraFollow:_handleCharacterAdded(character: Model)
    if not character then return end
    
    self:_setupCameraOffset(character)
    
    character.AncestryChanged:Connect(function(_, parent)
        if not parent then
            local bindName = "CameraOffset_" .. player.Name
            RunService:UnbindFromRenderStep(bindName)
        end
    end)
end

-------------------------
--// Public Methods \\--
-------------------------

--- Initializes the camera follow system
-- @return nil
function CameraFollow:Init()
    if not IS_CLIENT then return end
    if self._initialized then return end
    
    self._initialized = true
    
    return function (char)
        self:_handleCharacterAdded(char)
    end
end

return CameraFollow