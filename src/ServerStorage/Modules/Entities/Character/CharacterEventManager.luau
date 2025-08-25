--!strict
-- CharacterEventManager - Manages all character-related events and signals
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)

type CharacterSignals = CharacterTypes.CharacterSignals
type internalCharacter = CharacterTypes.internalCharacter

local CharacterEventManager = {}
CharacterEventManager.__index = CharacterEventManager

export type ICharacterEventManager = {
	CreateCharacterSignals: (self: ICharacterEventManager) -> CharacterSignals,
	SetupSignalConnections: (self: ICharacterEventManager, characterData: internalCharacter, onDeathCallback: () -> ()) -> (),
	SetupStateChangeSignals: (self: ICharacterEventManager, characterData: internalCharacter) -> (),
	CleanupSignals: (self: ICharacterEventManager, signals: CharacterSignals) -> (),
}

function CharacterEventManager.new(): ICharacterEventManager
	local self = setmetatable({}, CharacterEventManager)
	return self
end

function CharacterEventManager:CreateCharacterSignals(): CharacterSignals
	return {
		OnSpawn = Instance.new("BindableEvent"),
		OnDeath = Instance.new("BindableEvent"),
		OnDamage = Instance.new("BindableEvent"),
		OnAttack = Instance.new("BindableEvent"),
		OnUpdate = Instance.new("BindableEvent"),
		OnStaminaChange = Instance.new("BindableEvent"),
		OnGuardChange = Instance.new("BindableEvent"),
		OnStateChange = Instance.new("BindableEvent"),
		OnCleanup = Instance.new("BindableEvent"),
	}
end

function CharacterEventManager:SetupSignalConnections(characterData: internalCharacter, onDeathCallback: () -> ())
	-- Connect humanoid died signal to character death signal
	if characterData.Humanoid then
		table.insert(characterData._connections, characterData.Humanoid.Died:Connect(function()
			characterData.Signals.OnDeath:Fire()
		end))
		
		-- Connect character death signal to death handler
		table.insert(characterData._connections, characterData.Signals.OnDeath.Event:Connect(onDeathCallback))
	end
end

function CharacterEventManager:SetupStateChangeSignals(characterData: internalCharacter)
	-- Wire specific state change signals
	characterData.StateManager:OnStateChange("Stamina", function(newVal, oldVal)
		characterData.Signals.OnStaminaChange:Fire(newVal, oldVal)
	end)
	
	characterData.StateManager:OnStateChange("Guard", function(newVal, oldVal)
		characterData.Signals.OnGuardChange:Fire(newVal, oldVal)
	end)
	
	-- General state change signal
	characterData.StateManager:OnStateChange("ShiftState", function(stateName, newVal, oldVal)
		characterData.Signals.OnStateChange:Fire(stateName, newVal, oldVal)
	end)
end

function CharacterEventManager:CleanupSignals(signals: CharacterSignals)
	for _, signal in pairs(signals) do
		if typeof(signal) == "Instance" and signal.Destroy then
			signal:Destroy()
		end
	end
end

return CharacterEventManager
