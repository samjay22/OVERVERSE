--!strict
-- Shifter character with custom ShiftState

local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

local def: CharacterTypes.CharacterDefinition = {
	id = "Shifter",
	displayName = "Shifter",
	animationPack = "Default",
	initialStates = {
		ShiftState = { default = "Human", validator = function(v)
			return v == "Human" or v == "Beast"
		end },
	},
	customFields = {
		ShiftDuration = 10, -- seconds
		LastShiftTime = 0,
	},
	hooks = {
		onInit = function(character)
			-- Could add visual indicators or load extra assets
		end,
		onUpdate = function(character, dt)
			-- Example: auto revert after duration when in Beast
			local state = character.StateManager:Get("ShiftState")
			if state == "Beast" then
				local last = character.Custom.LastShiftTime or 0
				local dur = character.Custom.ShiftDuration or 10
				if time() - last > dur then
					character.StateManager:Set("ShiftState", "Human")
				end
			end
		end,
	},
}

return def
