-- Client-side ability registry with per-ability modules and a static interface (refactored)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Modules.Types.ClientAbilityTypes)

type AbilityId = Types.AbilityId
type SharedAbilityContext = Types.SharedAbilityContext
type AbilityResult = Types.AbilityResult
type ClientAbility = Types.ClientAbilityModule
type ClassId = Types.ClassId

local ClientAbilities = {}

-- Internal state
local _registry: {[AbilityId]: ClientAbility} = {}
local _childAddedConn: RBXScriptConnection? = nil

local DEFAULT_INPUT: Enum.KeyCode | Enum.UserInputType = Enum.UserInputType.MouseButton1

-- Utility: find or wait for the abilities folder
local function _ensureAbilitiesFolder(): Folder?
    local container = ReplicatedStorage:WaitForChild("Modules")
    return container and container:WaitForChild("ClientAbilities") :: Folder?
end

-- Utility: adapt a raw module to the ClientAbility shape (with legacy compatibility)
local function _adapt(abilityModule: any): ClientAbility
    local onRequestFn = typeof(abilityModule.onRequest) == "function" and abilityModule.onRequest or nil
    local onCastFn = typeof(abilityModule.onCast) == "function" and abilityModule.onCast or nil
    local onConfirmFn = typeof(abilityModule.onConfirm) == "function" and abilityModule.onConfirm or nil

    -- Legacy compatibility: prefer onReject, fallback to OnCancel
    local rejectFn = if typeof(abilityModule.onReject) == "function"
        then abilityModule.onReject
        elseif typeof(abilityModule.OnCancel) == "function"
        then abilityModule.OnCancel
        else nil

    local getInput = if typeof(abilityModule.getAbilityInputRequired) == "function"
        then abilityModule.getAbilityInputRequired
        else function(): Enum.KeyCode | Enum.UserInputType
            -- Sensible default to keep UX consistent instead of returning a warn() value
            return DEFAULT_INPUT
        end

    local getClassId = if typeof(abilityModule.getAbilityClassId) == "function"
        then abilityModule.getAbilityClassId
        else function(): ClassId? return nil end

    return {
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
        onConfirm = onConfirmFn,
        onReject = rejectFn,
        OnCancel = rejectFn, -- keep legacy alias
        getAbilityInputRequired = getInput,
        getAbilityClassId = getClassId,
        getAbilityRange = if typeof(abilityModule.getAbilityRange) == "function"
            then abilityModule.getAbilityRange
            else function(): number? return nil end,
        getRequiresTarget = if typeof(abilityModule.getRequiresTarget) == "function"
            then abilityModule.getRequiresTarget
            else function(): boolean? return nil end,
    }
end

-- Loader: require module by id (or a specific ModuleScript) and cache adapted version
local function _loadModuleFor(id: AbilityId, mod: ModuleScript?): ClientAbility?
    local abilitiesFolder = mod and mod.Parent or _ensureAbilitiesFolder()
    local moduleScript = mod or (abilitiesFolder and abilitiesFolder:FindFirstChild(tostring(id)))
    if moduleScript and moduleScript:IsA("ModuleScript") then
        local ok, abilityModule = pcall(require, moduleScript)
        if ok and typeof(abilityModule) == "table" then
            local adapted = _adapt(abilityModule)
            _registry[id] = adapted
            return adapted
        end
    end
    return nil
end

-- Autoload: pre-load all current modules and watch for new ones
local function _tryAutoloadOne(child: Instance)
    if not child:IsA("ModuleScript") or child == script then
        return
    end
    local id = (child.Name :: any) :: AbilityId
    if not _registry[id] then
        _loadModuleFor(id, child)
    end
end

local function _autoloadAll()
    local abilitiesFolder = _ensureAbilitiesFolder()
    if not abilitiesFolder then
        return
    end

    -- Initial pass
    for _, child in abilitiesFolder:GetChildren() do
        _tryAutoloadOne(child)
    end

    -- Refresh watcher
    if _childAddedConn then
        _childAddedConn:Disconnect()
        _childAddedConn = nil
    end
    _childAddedConn = abilitiesFolder.ChildAdded:Connect(_tryAutoloadOne)
end

-- Helpers
local function _classMatches(ability: ClientAbility, classId: ClassId): boolean
    local flag = ability.getAbilityClassId()
    return flag == nil or flag == classId
end

-- Treat nil and the literal "General" as general-purpose abilities
local function _isGeneralClassId(id: ClassId?): boolean
    return id == nil or ((id :: any) == "General")
end

-- Public API

function ClientAbilities.Get(id: AbilityId): ClientAbility?
    local cached = _registry[id]
    if cached then
        return cached
    end

    local loaded = _loadModuleFor(id)
    if loaded then
        return loaded
    end

    -- Do NOT cache fallback; try loading again next time
    local fallback: ClientAbility = {
        onCast = function(): AbilityResult return { success = false, reason = "No client module" } end,
        onRequest = function(): AbilityResult return { success = false, reason = "No client module" } end,
        getAbilityInputRequired = function(): Enum.KeyCode | Enum.UserInputType
            return DEFAULT_INPUT
        end,
        getAbilityClassId = function(): ClassId? return nil end,
    }
    return fallback
end

function ClientAbilities.Register(id: AbilityId, ability: ClientAbility)
    _registry[id] = ability
end

function ClientAbilities.GetAbilityByInputValue(input: Enum.KeyCode | Enum.UserInputType): (string?, ClientAbility?)
    for id, ability in pairs(_registry) do
        if ability.getAbilityInputRequired() == input then
            return id, ability
        end
    end
    return nil
end

function ClientAbilities.GetAbilityByInputValueForClass(input: Enum.KeyCode | Enum.UserInputType, classId: ClassId): (string?, ClientAbility?)
    -- Prefer exact class match first
    for id, ability in pairs(_registry) do
        if ability.getAbilityInputRequired() == input then
            local flag = ability.getAbilityClassId()
            if flag ~= nil and flag == classId then
                return id, ability
            end
        end
    end
    -- Fallback to General (nil or "General")
    for id, ability in pairs(_registry) do
        if ability.getAbilityInputRequired() == input then
            local flag = ability.getAbilityClassId()
            if _isGeneralClassId(flag) then
                return id, ability
            end
        end
    end
    return nil
end

function ClientAbilities.GetAllForClass(classId: ClassId): {AbilityId}
    local results: {AbilityId} = {}
    for id, ability in pairs(_registry) do
        if _classMatches(ability, classId) then
            table.insert(results, id)
        end
    end
    return results
end

function ClientAbilities.Reload()
    -- Clear state and watchers
    _registry = {}
    if _childAddedConn then
        _childAddedConn:Disconnect()
        _childAddedConn = nil
    end
    _autoloadAll()
end

function ClientAbilities.GetAbilityByInputForPlayer(input: Enum.KeyCode | Enum.UserInputType, player: Player): (string?, ClientAbility?)
    local attr = if player then player:GetAttribute("classId") else nil

    -- If no class or player is "General", only return General abilities
    if attr == nil or _isGeneralClassId(attr :: any) then
        for id, ability in pairs(_registry) do
            if ability.getAbilityInputRequired() == input then
                local flag = ability.getAbilityClassId()
                if _isGeneralClassId(flag) then
                    return id, ability
                end
            end
        end
        return nil
    end

    -- Otherwise, prefer exact class then fallback to General
    return ClientAbilities.GetAbilityByInputValueForClass(input, attr :: any)
end

-- Initial autoload
_autoloadAll()

return ClientAbilities
