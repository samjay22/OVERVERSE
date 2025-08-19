--!strict
-- Shifter character with custom ShiftState

local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

local function getEffectsHandler()
	-- Safely get the Effects handler
	local success, result = pcall(function()
		return require(game.ReplicatedStorage.Modules.AssetHandlers).OnModuleLoaded("Effects")
	end)
	if success and result then
		return result
	else
		warn("Failed to load Effects handler:", result)
		return nil
	end
end

local def: CharacterTypes.CharacterDefinition = {
	id = "Rem",
	displayName = "Rem-Ram",
	initialStates = {
		ShiftState = { default = "Rem", validator = function(v)
			return v == "Rem" or v == "Ram"
		end },
	},
	-- Map form/state -> Loadout assetKey from Loadouts registry
	loadoutMapping = {
		Rem = "Rem",
		Ram = "Ram",
		Default = "Rem",
	},
	customFields = {
		ShiftDuration = 10, -- seconds
		LastShiftTime = 0,
	},
	hooks = {
		onInit = function(character : CharacterTypes.Character)
			character.StateManager:Set("ShiftState", "Rem")
			warn("init rem")
		end,
		onUpdate = function(character, dt)
			-- Example: auto revert after duration when in Beast
			local state = character.StateManager:Get("ShiftState")
			if state == "Ram" then
				local last = character.Custom.LastShiftTime or 0
				local dur = character.Custom.ShiftDuration or 10
				if time() - last > dur then
					character.StateManager:Set("ShiftState", "Rem")
				end
			end
		end,
	},
}

return def
