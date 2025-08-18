--!strict
--[[
	Target validation utilities for mouse targeting system
	
	@author: GitHub Copilot
	@version: 1.0.0
]]

--// Services \\--
local _Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

--// Module \\--
local TargetValidator = {}

--[[
	Determines if a model can be targeted by the mouse controller
	
	@param model - The model to check for targetability
	@param localPlayer - The local player (to exclude self-targeting)
	@return boolean - Whether the model can be targeted
]]
function TargetValidator.isTargetable(model: Model?, localPlayer: Player?): boolean
	if not model then 
		return false 
	end
	
	-- Must be a character-like model with humanoid
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then 
		return false 
	end

	-- Don't target the local player's own character
	if localPlayer and localPlayer.Character and model == localPlayer.Character then
		return false
	end

	-- Check explicit targetable attribute (takes precedence)
	local attr = model:GetAttribute("Targetable")
	if typeof(attr) == "boolean" then
		return attr
	end

	-- Check for targetable tag
	if CollectionService:HasTag(model, "Targetable") then
		return true
	end

	-- Check for non-targetable tag
	if CollectionService:HasTag(model, "NonTargetable") then
		return false
	end

	-- Default: allow humanoid models
	return true
end

--[[
	Finds the targetable model from a hit part by climbing the hierarchy
	
	@param part - The part that was hit by the raycast
	@param localPlayer - The local player (to exclude self-targeting)
	@return Model? - The targetable model, if found
]]
function TargetValidator.getTargetableModelFromHit(part: Instance?, localPlayer: Player?): Model?
	if not part then 
		return nil 
	end
	
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then 
		return nil 
	end

	-- Check if this model is targetable first
	if TargetValidator.isTargetable(model, localPlayer) then
		return model
	end

	-- Climb up to find a humanoid-bearing model
	local probe: Model? = model
	while probe do
		if probe:FindFirstChildOfClass("Humanoid") and TargetValidator.isTargetable(probe, localPlayer) then
			return probe
		end
		
		local parent = probe.Parent
		if not parent or parent == workspace then 
			break 
		end
		
		probe = parent:FindFirstAncestorOfClass("Model")
	end

	return nil
end

return TargetValidator
