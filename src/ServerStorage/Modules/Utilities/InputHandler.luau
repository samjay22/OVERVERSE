--!strict
-- InputHandler: Separates input handling from business logic
-- Provides clean interface for handling different input types

local CharacterService = require(game.ServerStorage.Modules.Services.CharacterService)
local ErrorHandler = require(game.ServerStorage.Modules.Utilities.ErrorHandler)

export type InputAction = "M1" | "M2" | "Slot" | "Custom"

export type InputContext = {
	player: Player,
	action: InputAction,
	isDown: boolean,
	metadata: {[string]: any}?,
	timestamp: number?,
}

export type InputResult = {
	success: boolean,
	handled: boolean,
	message: string?,
}

export type IInputHandler = {
	HandleInput: (self: IInputHandler, context: InputContext) -> InputResult,
	RegisterCustomHandler: (self: IInputHandler, actionName: string, handler: (InputContext) -> InputResult) -> (),
	UnregisterCustomHandler: (self: IInputHandler, actionName: string) -> (),
	SetAbilityService: (self: IInputHandler, abilityService: any) -> (),
}

type InputHandlerDependencies = {
	characterService: CharacterService.ICharacterService,
	abilityService: any?, -- Will be set later to avoid circular dependencies
}

local InputHandler = {}
InputHandler.__index = InputHandler

function InputHandler.New(dependencies: InputHandlerDependencies): IInputHandler
	local self = setmetatable({}, InputHandler)
	
	self._characterService = dependencies.characterService
	self._abilityService = dependencies.abilityService
	self._customHandlers = {} :: {[string]: (InputContext) -> InputResult}
	self._errorContext = ErrorHandler.CreateContext("InputHandler")
	
	return (self :: any) :: IInputHandler
end

-- Set ability service (for late binding to avoid circular dependencies)
function InputHandler:SetAbilityService(abilityService: any): ()
	self._abilityService = abilityService
end

-- Main input handling function
function InputHandler:HandleInput(context: InputContext): InputResult
	local errorContext = ErrorHandler.CreateContext("InputHandler", "HandleInput", context.player.UserId)
	
	-- Validate input
	if not self:_validateInputContext(context) then
		return {
			success = false,
			handled = false,
			message = "Invalid input context",
		}
	end
	
	-- Check if ability service is available
	if not self._abilityService then
		ErrorHandler.Warn("AbilityService not set on InputHandler", errorContext)
		return {
			success = false,
			handled = false,
			message = "AbilityService not available",
		}
	end
	
	-- Update last input timestamp
	self:_updateInputTimestamp(context)
	
	-- Route to appropriate handler
	local result = ErrorHandler.SafeCall(function()
		return self:_routeInput(context)
	end, errorContext)
	
	if result.success then
		return result.data or {success = false, handled = false}
	else
		return {
			success = false,
			handled = false,
			message = result.error,
		}
	end
end

-- Internal input routing
function InputHandler:_routeInput(context: InputContext): InputResult
	if context.action == "M1" then
		return self:_handleM1(context)
	elseif context.action == "M2" then
		return self:_handleM2(context)
	elseif context.action == "Slot" then
		return self:_handleSlot(context)
	elseif context.action == "Custom" then
		return self:_handleCustom(context)
	else
		return {
			success = false,
			handled = false,
			message = `Unknown action: {context.action}`,
		}
	end
end

-- Handle M1 (primary attack)
function InputHandler:_handleM1(context: InputContext): InputResult
	return self._characterService:WithCharacter(context.player, function(character)
		local keyBinds = character.StateManager:Get("KeyBindings") :: any or {}
		local m1Ability = keyBinds.M1Ability
		
		if context.isDown and m1Ability then
			-- Custom ability bound to M1
			local success = self._abilityService:Activate(
				context.player, 
				m1Ability, 
				{ source = "M1", ts = context.timestamp }
			)
			return {
				success = success,
				handled = true,
				message = if success then nil else "Ability activation failed",
			}
		elseif context.isDown then
			-- Default M1 attack
			local attackType = context.metadata and context.metadata.attackType
			local success = self._abilityService:M1(context.player, attackType)
			return {
				success = success,
				handled = true,
				message = if success then nil else "Attack failed",
			}
		else
			-- M1 release - usually no action needed
			return {
				success = true,
				handled = true,
				message = nil,
			}
		end
	end) or {
		success = false,
		handled = false,
		message = "Character not available",
	}
end

-- Handle M2 (secondary action/block)
function InputHandler:_handleM2(context: InputContext): InputResult
	return self._characterService:WithCharacter(context.player, function(character)
		local keyBinds = character.StateManager:Get("KeyBindings") :: any or {}
		local m2Ability = keyBinds.M2Ability
		
		if context.isDown and m2Ability then
			-- Custom ability bound to M2
			local success = self._abilityService:Activate(
				context.player, 
				m2Ability, 
				{ source = "M2", ts = context.timestamp }
			)
			return {
				success = success,
				handled = true,
				message = if success then nil else "Ability activation failed",
			}
		else
			-- Default M2 behavior (blocking)
			local success = self._abilityService:M2(context.player, context.isDown)
			return {
				success = success,
				handled = true,
				message = if success then nil else "Block action failed",
			}
		end
	end) or {
		success = false,
		handled = false,
		message = "Character not available",
	}
end

-- Handle slot abilities
function InputHandler:_handleSlot(context: InputContext): InputResult
	if not context.isDown then
		return {success = true, handled = true, message = nil}
	end
	
	local slot = context.metadata and context.metadata.slot
	if not slot or type(slot) ~= "number" then
		return {
			success = false,
			handled = false,
			message = "Invalid slot number",
		}
	end
	
	return self._characterService:WithCharacter(context.player, function(character)
		-- Get ability for this slot from character's loadout
		local abilityService = self._abilityService
		local state = abilityService:_getState(context.player.UserId)
		
		if not state then
			return {
				success = false,
				handled = false,
				message = "No ability state found",
			}
		end
		
		local abilityId = state.loadout.actives[slot]
		if not abilityId then
			return {
				success = false,
				handled = true, -- Handled but no ability in slot
				message = `No ability in slot {slot}`,
			}
		end
		
		local success = abilityService:Activate(
			context.player,
			abilityId,
			{ source = `Slot{slot}`, ts = context.timestamp }
		)
		
		return {
			success = success,
			handled = true,
			message = if success then "Success" else "Slot ability activation failed",
		}
	end) or {
		success = false,
		handled = false,
		message = "Character not available",
	}
end

-- Handle custom input actions
function InputHandler:_handleCustom(context: InputContext): InputResult
	local actionName = context.metadata and context.metadata.actionName
	if not actionName or type(actionName) ~= "string" then
		return {
			success = false,
			handled = false,
			message = "Missing or invalid custom action name",
		}
	end
	
	local handler = self._customHandlers[actionName]
	if not handler then
		return {
			success = false,
			handled = false,
			message = `No handler registered for custom action: {actionName}`,
		}
	end
	
	return handler(context)
end

-- Register custom input handlers
function InputHandler:RegisterCustomHandler(actionName: string, handler: (InputContext) -> InputResult): ()
	self._customHandlers[actionName] = handler
end

-- Unregister custom input handlers
function InputHandler:UnregisterCustomHandler(actionName: string): ()
	self._customHandlers[actionName] = nil
end

-- Input validation
function InputHandler:_validateInputContext(context: InputContext): boolean
	if not context.player or not context.player.Parent then
		return false
	end
	
	if not context.action then
		return false
	end
	
	return true
end

-- Update input timestamp on character
function InputHandler:_updateInputTimestamp(context: InputContext): ()
	self._characterService:WithCharacter(context.player, function(character)
		local timestamp = context.timestamp or os.time()
		character.StateManager:Set("LastInputTS", timestamp)
		return true
	end)
end

-- Utility: Create input context
function InputHandler.CreateInputContext(
	player: Player, 
	action: InputAction, 
	isDown: boolean, 
	metadata: {[string]: any}?
): InputContext
	return {
		player = player,
		action = action,
		isDown = isDown,
		metadata = metadata,
		timestamp = os.time(),
	}
end

return InputHandler
