-- Client-side ability registry with per-ability modules and a static interface

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

type AbilityId = Types.AbilityId
type SharedAbilityContext = Types.SharedAbilityContext
type AbilityResult = Types.AbilityResult
type ClientAbility = Types.ClientAbilityModule

local ClientAbilities = {}

local _registry: {[AbilityId]: ClientAbility} = {}

-- Auto-loader for per-ability modules that implement the static interface
local function _loadModuleFor(id: AbilityId): ClientAbility?
	-- Be resilient to replication timing by waiting for the folders to exist
	local container = ReplicatedStorage:WaitForChild("Modules")
	local abilitiesFolder = container and container:WaitForChild("ClientAbilities")
	local mod = abilitiesFolder and abilitiesFolder:FindFirstChild(tostring(id))
	if mod and mod:IsA("ModuleScript") then
		local ok, abilityModule = pcall(require, mod)
		if ok and typeof(abilityModule) == "table" then
			-- Adapt to the registry shape while preserving backwards compatibility
	    	local onRequestFn = (typeof(abilityModule.onRequest) == "function") and abilityModule.onRequest or nil
			local onCastFn = (typeof(abilityModule.onCast) == "function") and abilityModule.onCast or nil

			local getInput = if typeof(abilityModule.getAbilityInputRequired) == "function"
				then abilityModule.getAbilityInputRequired
				else function(): Enum.KeyCode | Enum.UserInputType
					return error("Ability module missing getAbilityInputRequired")
				end

			local adapted: ClientAbility = {
				onCast = function(ctx: SharedAbilityContext): AbilityResult
					if onCastFn then
						return onCastFn(ctx)
					end
					if onRequestFn then
						return onRequestFn(ctx)
					end
					return { success = false, reason = "No onCast/onRequest implementation" }
				end,
				onRequest = onRequestFn or function(): AbilityResult
					return { success = false, reason = "No onRequest implementation" }
				end,
				onConfirm = if typeof(abilityModule.onConfirm) == "function" then abilityModule.onConfirm else nil,
				onReject = if typeof(abilityModule.onReject) == "function" then abilityModule.onReject elseif typeof(abilityModule.OnCancel) == "function" then abilityModule.OnCancel else nil,
				OnCancel = if typeof(abilityModule.OnCancel) == "function" then abilityModule.OnCancel else nil,
				getAbilityInputRequired = getInput,
			}
			_registry[id] = adapted
			return adapted
		end
	end
	return nil
end

-- Eagerly load all ability modules and watch for new ones
local function _autoloadAll()
	local container = ReplicatedStorage:WaitForChild("Modules")
	local abilitiesFolder = container and container:WaitForChild("ClientAbilities")
	if abilitiesFolder then
		for _, child in ipairs(abilitiesFolder:GetChildren()) do
			if child:IsA("ModuleScript") and child ~= script then
				local id = (child.Name :: any) :: AbilityId
				if not _registry[id] then
					_loadModuleFor(id)
				end
			end
		end
		abilitiesFolder.ChildAdded:Connect(function(child)
			if child:IsA("ModuleScript") and child ~= script then
				local id = (child.Name :: any) :: AbilityId
				if not _registry[id] then
					_loadModuleFor(id)
				end
			end
		end)
	end
end

function ClientAbilities.Get(id: AbilityId): ClientAbility?
	local cached = _registry[id]
	if cached then return cached end

	local loaded = _loadModuleFor(id)
	if loaded then return loaded end

	-- Do NOT cache fallback; try loading again next time
	local fallback: ClientAbility = {
		onCast = function(): AbilityResult return { success = false, reason = "No client module" } end,
		onRequest = function(): AbilityResult return { success = false, reason = "No client module" } end,
		getAbilityInputRequired = function(): Enum.KeyCode | Enum.UserInputType
			return Enum.UserInputType.MouseButton1
		end,
	}
	return fallback
end

function ClientAbilities.Register(id: AbilityId, ability: ClientAbility)
	_registry[id] = ability
end

function ClientAbilities.GetAbilityByInputValue(input : Enum.KeyCode | Enum.UserInputType): (string?, ClientAbility?)
	for id, ability in pairs(_registry) do
		if ability.getAbilityInputRequired() == input then
			return id, ability
		end
	end
	return nil
	
end

function ClientAbilities.Reload()
	-- Non-destructive reload: loads anything missing; does not clear existing
	_autoloadAll()
end

-- Perform initial autoload on module require
_autoloadAll()

return ClientAbilities
