-- Legacy Network Server - loads new NetworkServer
-- This file maintains backwards compatibility while the new system is being integrated

-- Load the new network server
local _NetworkServer = require(game.ServerStorage.Modules.Core.NetworkServer)

-- Keep the old CoreEvent for backwards compatibility
local CoreEvent = Instance.new("RemoteEvent")
CoreEvent.Name = "CoreEvent"
CoreEvent.Parent = game.ReplicatedStorage.Remotes

-- Backend-only routing for abilities and primary attacks
local _Character = require(game.ServerStorage.Modules.Entities.Character)
local AbilityComponent = require(game.ServerStorage.Modules.Components.AbilityComponent)
local WeaponComponent = require(game.ServerStorage.Modules.Components.WeaponComponent)
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local _NetworkTypes = require(game.ReplicatedStorage.Modules.Types.NetworkTypes)

CoreEvent.OnServerEvent:Connect(function(player: Player, msg)
	if typeof(msg) ~= "table" or typeof(msg.t) ~= "string" then return end
	if msg.t == Enums.CoreMessageType.PrimaryWeapon then
		WeaponComponent.Primary(player, (msg :: any).action)
	elseif msg.t == Enums.CoreMessageType.Ability and (msg :: any).id then
		AbilityComponent.Activate(player, (msg :: any).id, (msg :: any).extra)
	end
end)

_NetworkServer:RegisterRemoteEvent("StartCharacterAnimation").OnServerEvent:Connect(function(p)
	warn(p, "tried to start character animation without server-side support")
	error("Not supported")
end)

_NetworkServer:RegisterRemoteEvent("UserInput").OnServerEvent:Connect(function(player: Player, payload: any)
	-- Expected payload (new): { t = "B"|"E", n = number }
	-- Legacy support: { t = "B"|"E", k = string }
	if typeof(payload) ~= "table" then return end
	local actionType = payload.t
	if typeof(actionType) ~= "string" then return end

	local keyId: number? = nil
	if typeof(payload.n) == "number" then
		keyId = payload.n :: number
	elseif typeof(payload.k) == "string" then
		-- Map legacy strings to deterministic numbers for uniform server handling
		local k = payload.k :: string
		if k == "MouseButton1" then
			keyId = 100000 + Enum.UserInputType.MouseButton1.Value
		elseif k == "MouseButton2" then
			keyId = 100000 + Enum.UserInputType.MouseButton2.Value
		elseif k == "MouseButton3" then
			keyId = 100000 + Enum.UserInputType.MouseButton3.Value
		else
			local kc = Enum.KeyCode[k]
			if kc then keyId = kc.Value end
		end
	end
	if not keyId then return end

	local data = _Character:GetCharacterData(player)
	if not data then return end

	-- Clone/update ActiveKeys table immutably to trigger state change events
	local current = data.StateManager:Get("ActiveKeys") :: {[number]: boolean}?
	local updated: {[number]: boolean} = {}
	if typeof(current) == "table" then
		for k, v in pairs(current :: any) do
			updated[k] = v and true or false
		end
	end

	if actionType == "B" then
		updated[keyId] = true
		-- Special: toggle character form on 'C' press (using numeric KeyCode)
		if keyId == Enum.KeyCode.C.Value then
			local ok = pcall(function()
				_Character:ShiftCharacter(player)
			end)
			if not ok then
				warn("ShiftCharacter failed for", player)
			end
		end
	elseif actionType == "E" then
		updated[keyId] = nil
	else
		return
	end

	data.StateManager:Set("ActiveKeys", table.freeze(updated))

	-- Server timestamp for priority resolution
	local ts = os.time()
	local meta = { tsServer = ts }
	-- Route to ability layer (unified input)
	if keyId == (100000 + Enum.UserInputType.MouseButton1.Value) then
		AbilityComponent.HandleInput(player, "M1", actionType == "B", meta)
	elseif keyId == (100000 + Enum.UserInputType.MouseButton2.Value) then
		AbilityComponent.HandleInput(player, "M2", actionType == "B", meta)
	else
		local slot: number? = nil
		if keyId == Enum.KeyCode.Q.Value or keyId == Enum.KeyCode.One.Value then slot = 1 end
		if keyId == Enum.KeyCode.E.Value or keyId == Enum.KeyCode.Two.Value then slot = 2 end
		if keyId == Enum.KeyCode.R.Value or keyId == Enum.KeyCode.Three.Value then slot = 3 end
		if keyId == Enum.KeyCode.F.Value or keyId == Enum.KeyCode.Four.Value then slot = 4 end
		if slot then
			meta.slot = slot
			AbilityComponent.HandleInput(player, "Slot", actionType == "B", meta)
		end
	end
end)