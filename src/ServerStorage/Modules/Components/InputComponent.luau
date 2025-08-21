--!strict
-- InputComponent: tracks client-reported input and dispatches per-frame actions

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local ClientAbilities = require(game.ReplicatedStorage.Modules.ClientAbilities)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)
local AbilityComponent = require(game.ServerStorage.Modules.Components.AbilityComponent)
local CombatComponent = require(game.ServerStorage.Modules.Components.CombatComponent)

export type Loadout = AbilityTypes.Loadout

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
-- Legacy string key names removed; numeric-only mapping is used throughout

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
			-- Only freeze if not already frozen
			if not table.isfrozen(current) then
				characterData.StateManager:Set("ActiveKeys", table.freeze(current))
			end
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

	-- Helper to convert an EnumItem (KeyCode or UserInputType) into our binding entry (numeric-only)
	local function toBindingEntry(input: EnumItem): { numeric: {number} }
		if input.EnumType == Enum.KeyCode then
			return { numeric = { (input :: any).Value } }
		elseif input.EnumType == Enum.UserInputType then
			return { numeric = { OFFSET + (input :: any).Value } }
		else
			-- Fallback: no valid mapping
			return { numeric = {} }
		end
	end

	-- Build keybinds from current Loadout + ClientAbilities, with safe fallbacks
	local binds = {
		PrimaryAttacks = {toBindingEntry(Enum.UserInputType.MouseButton1), toBindingEntry(Enum.UserInputType.MouseButton2)},
		Slots = {} :: { [number]: { numeric: {number} } },
	}

	local loadout: Loadout? = (AbilityComponent.GetLoadout and AbilityComponent.GetLoadout(characterData.PlayerId))
	local activeIds = (loadout and loadout.actives) or {}

	-- Optionally map primary attacks if provided in loadout
	local function toNumericCode(input: any): number?
		if typeof(input) == "EnumItem" then
			local enumItem = (input :: any)
			if enumItem.EnumType == Enum.UserInputType then
				return OFFSET + enumItem.Value
			elseif enumItem.EnumType == Enum.KeyCode then
				return enumItem.Value
			end
		end
		return nil
	end
	if loadout and (loadout :: any).primaryAttacks then
		local pa = (loadout :: any).primaryAttacks
		local c1 = toNumericCode(pa[1])
		local c2 = toNumericCode(pa[2])
		if c1 then binds.M1 = { numeric = { c1 } } end
		if c2 then binds.M2 = { numeric = { c2 } } end
	end

	for slot = 1, 4 do
		local abilityId: string? = activeIds[slot]
		local entry
		if abilityId ~= nil then
			local clientMod = ClientAbilities.Get(abilityId :: any)
			if clientMod and typeof(clientMod.getAbilityInputRequired) == "function" then
				local ok, input = pcall(function()
					return (clientMod :: any).getAbilityInputRequired()
				end)
				if ok and input ~= nil then
					entry = toBindingEntry(input :: EnumItem)
				end
			end
		end
		-- Fallback to defaults for the slot if no client-specified input
		if not entry or (#entry.numeric == 0) then
			entry = { numeric = table.clone(SLOT_TO_NUM_CODES[slot]) }
		end
		binds.Slots[slot] = entry
	end

	characterData.StateManager:Set("KeyBindings", binds)
end

-- (helper removed; inlined checks for minimal overhead)

function InputComponent.Update(characterData: CharacterRef, dt: number)
	local keysAny = (characterData.StateManager:Get("ActiveKeys") :: any)
	if typeof(keysAny) ~= "table" then return end
	local keys = keysAny :: {[number]: boolean}

	-- Primary / Secondary
	local hasM1: boolean = (keys :: any)[OFFSET + Enum.UserInputType.MouseButton1.Value] == true
	local hasM2: boolean = (keys :: any)[OFFSET + Enum.UserInputType.MouseButton2.Value] == true

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
				-- Prefer dynamic bindings from state; fallback to legacy defaults
				local kbAny = characterData.StateManager:Get("KeyBindings")
				local slotBind = (typeof(kbAny) == "table" and (kbAny :: any).Slots and (kbAny :: any).Slots[slot]) or nil
				local codes = (slotBind and slotBind.numeric) or SLOT_TO_NUM_CODES[slot]
			local down = false
			-- numeric codes only
			for _, code in ipairs(codes) do
				if (keys :: any)[code] == true then
					down = true
					break
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
