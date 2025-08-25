--!strict
-- InputComponent: tracks client-reported input and dispatches per-frame actions
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
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

local OFFSET = 0
local SLOT_TO_NUM_CODES: {[number]: {number}} = {
	[1] = { Enum.KeyCode.Q.Value, Enum.KeyCode.One.Value },
	[2] = { Enum.KeyCode.E.Value, Enum.KeyCode.Two.Value },
	[3] = { Enum.KeyCode.R.Value, Enum.KeyCode.Three.Value },
	[4] = { Enum.KeyCode.F.Value, Enum.KeyCode.Four.Value },
}
-- Legacy string key names removed; numeric-only mapping is used throughout

function InputComponent.Initialize(characterData: CharacterRef)

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
			print("Called")
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
