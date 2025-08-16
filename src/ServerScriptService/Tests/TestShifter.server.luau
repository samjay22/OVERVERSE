--!nonstrict
-- Test spawning a Shifter character and toggling shift state

local Players = game:GetService("Players")
local CharacterManager = require(game.ServerStorage.Modules.Entities.Character)

local function setupPlayer(plr: Player)
	plr:SetAttribute("ClassId", "Shifter")
	-- Toggle shift after a short delay
	task.delay(3, function()
		CharacterManager:ShiftCharacter(plr)
	end)
end

for _, p in ipairs(Players:GetPlayers()) do
	setupPlayer(p)
end

Players.PlayerAdded:Connect(setupPlayer)
