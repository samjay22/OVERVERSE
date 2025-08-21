--!strict
-- Passive Abilities Registry and Management System
-- Handles stat modifications, continuous effects, and passive ability lifecycle

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(game.ReplicatedStorage.Modules.Types.ClientAbilityTypes)

type AbilityId = string -- Using string instead of the specific union to allow flexibility
type StateSnapshot = Types.StateSnapshot
type PassiveAbilityModule = Types.PassiveAbilityModule
type ClassId = Types.ClassId

local PassiveAbilities = {}

-- Internal state
local _registry: {[AbilityId]: PassiveAbilityModule} = {}
local _childAddedConn: RBXScriptConnection? = nil

-- Utility: find or wait for the passive abilities folder
local function _ensurePassiveAbilitiesFolder(): Folder?
    local container = ReplicatedStorage:WaitForChild("Modules")
    local passiveFolder = container and container:FindFirstChild("PassiveAbilities")
    return if passiveFolder and passiveFolder:IsA("Folder") then passiveFolder :: Folder else nil
end

-- Utility: adapt a raw module to the PassiveAbilityModule shape
local function _adaptPassive(abilityModule: any): PassiveAbilityModule
    local onEquipFn = typeof(abilityModule.onEquip) == "function" and abilityModule.onEquip or nil
    local onUnequipFn = typeof(abilityModule.onUnequip) == "function" and abilityModule.onUnequip or nil
    local onTickFn = typeof(abilityModule.onTick) == "function" and abilityModule.onTick or nil

    local getClassId = if typeof(abilityModule.getAbilityClassId) == "function"
        then abilityModule.getAbilityClassId
        else function(): ClassId? return nil end

    local getCategory = if typeof(abilityModule.getAbilityCategory) == "function"
        then abilityModule.getAbilityCategory
        else function(): Types.AbilityCategory return "Passive" end

    local getStatModifiers = if typeof(abilityModule.getStatModifiers) == "function"
        then abilityModule.getStatModifiers
        else function(): {[string]: number}? return nil end

    return {
        onEquip = onEquipFn or function(_playerId: number, _state: StateSnapshot): {[string]: number}?
            return getStatModifiers()
        end,
        onUnequip = onUnequipFn or function(_playerId: number, _state: StateSnapshot)
            -- Default: no cleanup needed
        end,
        onTick = onTickFn,
        getAbilityClassId = getClassId,
        getAbilityCategory = getCategory,
        getStatModifiers = getStatModifiers,
    }
end

-- Loader: require module by id and cache adapted version
local function _loadPassiveModuleFor(id: AbilityId, mod: ModuleScript?): PassiveAbilityModule?
    local passiveFolder = mod and mod.Parent or _ensurePassiveAbilitiesFolder()
    local moduleScript = mod or (passiveFolder and passiveFolder:FindFirstChild(tostring(id)))
    if moduleScript and moduleScript:IsA("ModuleScript") then
        local ok, abilityModule = pcall(require, moduleScript)
        if ok and typeof(abilityModule) == "table" then
            local adapted = _adaptPassive(abilityModule)
            _registry[id] = adapted
            return adapted
        end
    end
    return nil
end

-- Autoload: pre-load all current passive modules and watch for new ones
local function _tryAutoloadPassive(child: Instance)
    if not child:IsA("ModuleScript") or child == script then
        return
    end
    local id = (child.Name :: any) :: AbilityId
    if not _registry[id] then
        _loadPassiveModuleFor(id, child)
    end
end

local function _autoloadAllPassives()
    local passiveFolder = _ensurePassiveAbilitiesFolder()
    if not passiveFolder then
        return
    end

    -- Initial pass
    for _, child in passiveFolder:GetChildren() do
        _tryAutoloadPassive(child)
    end

    -- Refresh watcher
    if _childAddedConn then
        _childAddedConn:Disconnect()
        _childAddedConn = nil
    end
    _childAddedConn = passiveFolder.ChildAdded:Connect(_tryAutoloadPassive)
end

-- Helpers
local function _classMatches(ability: PassiveAbilityModule, classId: ClassId): boolean
    local flag = ability.getAbilityClassId()
    return flag == nil or flag == classId
end

-- Public API

function PassiveAbilities.Get(id: AbilityId): PassiveAbilityModule?
    local cached = _registry[id]
    if cached then
        return cached
    end

    local loaded = _loadPassiveModuleFor(id)
    if loaded then
        return loaded
    end

    warn(`Passive ability {id} not found or failed to load`)
    return nil
end

function PassiveAbilities.Register(id: AbilityId, ability: PassiveAbilityModule)
    _registry[id] = ability
end

function PassiveAbilities.GetAllForClass(classId: ClassId): {AbilityId}
    local results: {AbilityId} = {}
    for id, ability in pairs(_registry) do
        if _classMatches(ability, classId) then
            table.insert(results, id)
        end
    end
    return results
end

function PassiveAbilities.GetAllPassives(): {[AbilityId]: PassiveAbilityModule}
    return table.clone(_registry)
end

function PassiveAbilities.Reload()
    -- Clear state and watchers
    if _childAddedConn then
        _childAddedConn:Disconnect()
        _childAddedConn = nil
    end
    table.clear(_registry)
    
    -- Reload all
    _autoloadAllPassives()
end

-- Initialize on module load
_autoloadAllPassives()

return PassiveAbilities
