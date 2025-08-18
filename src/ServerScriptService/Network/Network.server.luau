-- Network Server bridge to new NetworkServer with ultra-fast input processing

-- Load the new network server and object pools
local _NetworkServer = require(game.ServerStorage.Modules.Core.NetworkServer)
local ObjectPools = require(game.ServerStorage.Modules.Utilities.ObjectPool)

local _Character = require(game.ServerStorage.Modules.Entities.Character)
local AbilityComponent = require(game.ServerStorage.Modules.Components.AbilityComponent)
local _WeaponComponent = require(game.ServerStorage.Modules.Components.WeaponComponent)
local _Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local _NetworkTypes = require(game.ReplicatedStorage.Modules.Types.NetworkTypes)

-- Pre-allocated input processing pools
local inputStatePool = ObjectPools.TablePool

_NetworkServer:RegisterRemoteEvent("StartCharacterAnimation").OnServerEvent:Connect(function(p)
	warn(p, "tried to start character animation without server-side support")
	error("Not supported")
end)

_NetworkServer:RegisterRemoteEvent("UserInput").OnServerEvent:Connect(function(player: Player, payload: any)
	-- Expected payload: { t = "B"|"E", n = number }
	if typeof(payload) ~= "table" then return end
	local actionType = payload.t
	if typeof(actionType) ~= "string" then return end

	local keyId: number? = nil
	if typeof(payload.n) == "number" then
		keyId = payload.n :: number
	end
	if not keyId then return end

	local data = _Character:GetCharacterData(player)
	if not data then return end

	-- Ultra-fast state update with object pooling (when possible)
	local current = data.StateManager:Get("ActiveKeys") :: {[number]: boolean}?
	local updated: {[number]: boolean}
	
	-- Fast path: reuse existing table, only modify needed keys
	if current then
		updated = current
		-- Direct mutation for performance (StateManager will handle immutability)
	else
		updated = {}
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