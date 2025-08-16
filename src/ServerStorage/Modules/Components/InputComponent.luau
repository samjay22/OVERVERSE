--!strict
-- InputComponent: tracks client-reported input and dispatches per-frame actions

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Modules.Types.Enums)
local AbilityComponent = require(game.ServerStorage.Modules.Components.AbilityComponent)
local CombatComponent = require(game.ServerStorage.Modules.Components.CombatComponent)

export type CharacterRef = {
	PlayerId: number,
	Player: Player,
	Character: Model?,
	Humanoid: Humanoid?,
	StateManager: any,
	Components: {[string]: any},
}

local InputComponent = {}

-- Fast numeric key mapping; matches Network.server encoding
local OFFSET = 100000
local SLOT_TO_NUM_CODES: {[number]: {number}} = {
	[1] = { Enum.KeyCode.Q.Value, Enum.KeyCode.One.Value },
	[2] = { Enum.KeyCode.E.Value, Enum.KeyCode.Two.Value },
	[3] = { Enum.KeyCode.R.Value, Enum.KeyCode.Three.Value },
	[4] = { Enum.KeyCode.F.Value, Enum.KeyCode.Four.Value },
}
local SLOT_TO_LEGACY_NAMES: {[number]: {string}} = {
	[1] = { "Q", "One" },
	[2] = { "E", "Two" },
	[3] = { "R", "Three" },
	[4] = { "F", "Four" },
}

function InputComponent.Initialize(characterData: CharacterRef)
	-- Ensure ActiveKeys exists
	if not characterData.StateManager:Has("ActiveKeys") then
		characterData.StateManager:DefineState("ActiveKeys", table.freeze({}), function(v)
			return typeof(v) == "table"
		end)
	else
		-- normalize to a frozen numeric-key table
		local current = characterData.StateManager:Get("ActiveKeys")
		if typeof(current) ~= "table" then
			characterData.StateManager:Set("ActiveKeys", table.freeze({}))
		else
			characterData.StateManager:Set("ActiveKeys", table.freeze(current))
		end
	end

	-- Cache component reference
	characterData.Components = characterData.Components or {}
	characterData.Components.Input = InputComponent
	-- Per-character transient state for edge detection
	characterData.Components.InputState = {
		prevSlotDown = {} :: {[number]: boolean},
	}

	-- Define and set default key bindings per character (modifiable later)
	if not characterData.StateManager:Has("KeyBindings") then
		characterData.StateManager:DefineState("KeyBindings", {}, function(v)
			return typeof(v) == "table"
		end)
	end
	local defaultBinds = {
		M1 = { numeric = { OFFSET + Enum.UserInputType.MouseButton1.Value }, legacy = { "MouseButton1" } },
		M2 = { numeric = { OFFSET + Enum.UserInputType.MouseButton2.Value }, legacy = { "MouseButton2" } },
		Slots = {
			[1] = { numeric = { Enum.KeyCode.Q.Value, Enum.KeyCode.One.Value }, legacy = { "Q", "One" } },
			[2] = { numeric = { Enum.KeyCode.E.Value, Enum.KeyCode.Two.Value }, legacy = { "E", "Two" } },
			[3] = { numeric = { Enum.KeyCode.R.Value, Enum.KeyCode.Three.Value }, legacy = { "R", "Three" } },
			[4] = { numeric = { Enum.KeyCode.F.Value, Enum.KeyCode.Four.Value }, legacy = { "F", "Four" } },
		},
	}
	characterData.StateManager:Set("KeyBindings", defaultBinds)
end

-- (helper removed; inlined checks for minimal overhead)

function InputComponent.Update(characterData: CharacterRef, dt: number)
	local keysAny = (characterData.StateManager:Get("ActiveKeys") :: any)
	if typeof(keysAny) ~= "table" then return end
	local keys = keysAny :: {[number]: boolean} | {[string]: boolean}

	-- Primary / Secondary
	local hasM1: boolean
	local hasM2: boolean
	if (keys :: any)[OFFSET + Enum.UserInputType.MouseButton1.Value] ~= nil then
		hasM1 = (keys :: any)[OFFSET + Enum.UserInputType.MouseButton1.Value]
	else
		hasM1 = (keys :: any)["MouseButton1"] == true -- legacy fallback
	end
	if (keys :: any)[OFFSET + Enum.UserInputType.MouseButton2.Value] ~= nil then
		hasM2 = (keys :: any)[OFFSET + Enum.UserInputType.MouseButton2.Value]
	else
		hasM2 = (keys :: any)["MouseButton2"] == true
	end

	if hasM1 then
		if AbilityComponent and AbilityComponent.M1 then
			AbilityComponent.M1(characterData.Player, Enums.AttackType.Default)
		else
			if CombatComponent and CombatComponent.PerformAttack then
				CombatComponent.PerformAttack(characterData, Enums.AttackType.Default)
			end
		end
	end

	if AbilityComponent and AbilityComponent.M2 then
		AbilityComponent.M2(characterData.Player, hasM2 == true)
	else
		if CombatComponent and CombatComponent.PerformBlock then
			CombatComponent.PerformBlock(characterData, hasM2 == true)
		end
	end

	-- Ability keys (Q/E/R/F and 1/2/3/4) via numeric codes
	local loadout = (AbilityComponent.GetLoadout and AbilityComponent.GetLoadout(characterData.PlayerId))
	local activeIds = (loadout and loadout.actives) or {}
	if #activeIds > 0 then
		local inputState = (characterData.Components and characterData.Components.InputState) or { prevSlotDown = {} }
		local prev = inputState.prevSlotDown :: {[number]: boolean}

		for slot = 1, 4 do
			local codes = SLOT_TO_NUM_CODES[slot]
			local names = SLOT_TO_LEGACY_NAMES[slot]
			local down = false
			-- numeric codes
			for _, code in ipairs(codes) do
				if (keys :: any)[code] == true then
					down = true
					break
				end
			end
			-- legacy fallback strings
			if not down then
				for _, name in ipairs(names) do
					if (keys :: any)[name] == true then
						down = true
						break
					end
				end
			end

			local wasDown = prev[slot] == true
			if down and not wasDown then
				local abilityId = activeIds[slot]
				if abilityId then
					AbilityComponent.Activate(characterData.Player, abilityId, nil)
				end
			end
			prev[slot] = down
		end
	end
end

function InputComponent.Cleanup(characterData: CharacterRef)
	if characterData.Components then
		characterData.Components.Input = nil
	end
end

-- Public API: override per-character key bindings (merges shallowly with existing)
function InputComponent.SetKeyBindings(characterData: CharacterRef, partial: any)
	local current = characterData.StateManager:Get("KeyBindings")
	if typeof(current) ~= "table" then return end
	local merged = table.clone(current)
	for k, v in pairs(partial) do
		merged[k] = v
	end
	characterData.StateManager:Set("KeyBindings", merged)
end

return InputComponent
