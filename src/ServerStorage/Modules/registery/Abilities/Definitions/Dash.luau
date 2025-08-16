--!strict
-- Dash ability - quick movement ability

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Enums = require(ReplicatedStorage.Modules.Types.Enums)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

local DASH_DISTANCE: number = 16 -- studs
local DASH_DURATION: number = 0.3 -- seconds
local DASH_COOLDOWN: number = 3 -- seconds
local DASH_STAMINA_COST: number = 15

local function performDash(context: AbilityTypes.AbilityContext): AbilityTypes.AbilityResult
	local character: AbilityTypes.CharacterRef = context.character
	if not character.Character or not character.Character.PrimaryPart or not character.Humanoid then
		return {
			success = false,
			errorMessage = "No character model, PrimaryPart, or Humanoid",
		}
	end

	local humanoid: Humanoid = character.Humanoid :: Humanoid
	local rootPart: BasePart = character.Character.PrimaryPart

	-- Get movement direction (either provided or forward)
	local direction: Vector3 = context.direction or rootPart.CFrame.LookVector
	direction = Vector3.new(direction.X, 0, direction.Z).Unit -- Keep on ground plane
	
	-- Calculate dash target position
	local startPosition: Vector3 = rootPart.Position
	local targetPosition: Vector3 = startPosition + (direction * DASH_DISTANCE)
	
	-- Check for obstacles (basic raycast)
	local raycast: RaycastResult? = workspace:Raycast(startPosition, direction * DASH_DISTANCE)
	if raycast then
		-- Stop short of the obstacle
		targetPosition = raycast.Position - (direction * 2)
	end

	-- Disable character control temporarily
	local originalWalkSpeed: number = humanoid.WalkSpeed
	humanoid.WalkSpeed = 0
	
	-- Set character state
	character.StateManager:Set("IsDashing", true)
	
	-- Create dash tween
	local targetCFrame: CFrame = CFrame.new(targetPosition, targetPosition + direction)
	local tween: Tween = TweenService:Create(
		rootPart,
		TweenInfo.new(DASH_DURATION, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ CFrame = targetCFrame }
	)
	
	tween:Play()
	
	-- Restore control after dash
	tween.Completed:Connect(function()
		humanoid.WalkSpeed = originalWalkSpeed
		character.StateManager:Set("IsDashing", false)
	end)
	
	return {
		success = true,
		data = {
			distance = DASH_DISTANCE,
			direction = direction,
			duration = DASH_DURATION,
		},
	}
end

-- Export the ability definition
return {
	id = Enums.AbilityId.Dash,
	type = "Active" :: "Active",
	name = "Dash",
	description = "Quickly dash forward a short distance",
	targetType = "Self" :: "Self",
	cooldown = DASH_COOLDOWN,
	staminaCost = DASH_STAMINA_COST,
	range = DASH_DISTANCE,
	castTime = 0,
	interruptible = false,
	serverActivate = performDash,
}
