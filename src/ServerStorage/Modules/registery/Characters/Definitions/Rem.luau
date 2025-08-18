--!strict
-- Shifter character with custom ShiftState

local Effects = require(game.ReplicatedStorage.Modules.AssetHandlers).OnModuleLoaded("Effects")
assert(Effects)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

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

			--load effects
			local allEffects = Effects.GetAllAssets()
			local effectsFolder = Instance.new("Folder")
			effectsFolder.Name = "Effects"
			for effectName, effectData in pairs(allEffects) do
				if effectName:find("Rem:") then 
					if effectData.Instance then
						local effectClone = effectData.Instance:Clone()
						-- Extract just the effect name after the colon (e.g., "Heal" from "Rem:Heal")
						local cleanName = effectName:split(":")[2] or effectName
						effectClone.Name = cleanName
						effectClone.Parent = effectsFolder
					end
				end
			end

			task.defer(function()
				effectsFolder.Parent = character.Character
			end)
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
