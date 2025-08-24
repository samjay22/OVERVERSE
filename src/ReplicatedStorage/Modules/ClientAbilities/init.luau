local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(game.ReplicatedStorage.Modules.Types.ClientAbilityTypes)

-- Import configuration modules
local Configuration = ReplicatedStorage.Modules:WaitForChild("Configuration")
local AbilityConfiguration = require(Configuration:WaitForChild("AbilityConfiguration"))

type Loader<T> = {
    GetAbility: (abilityId: number) -> T
}

local AbilityCache = {}
local Loader = {}

Loader.GetAbility = function(abilityId: string): any
    local cached = AbilityCache[abilityId]
    print("[ClientAbilities] GetAbility called for:", abilityId, "- Cached:", cached ~= nil)
    if cached then
        if cached.Execute then
            print("[ClientAbilities] Ability has Execute method")
        end
        if cached.GetSharedModule then
            print("[ClientAbilities] Ability has GetSharedModule")
            local shared = cached.GetSharedModule()
            if shared and shared.GetConfig then
                local config = shared.GetConfig()
                print("[ClientAbilities] Config exists:", config ~= nil)
            else
                print("[ClientAbilities] GetConfig not found in shared module")
            end
        else
            print("[ClientAbilities] No GetSharedModule method!")
        end
    end
    return cached
end

local function _loadClientAbility(abilityId : string, abilityPackage: Types.AbilityPackage)
    print("[ClientAbilities] Loading ability:", abilityId)
    
    -- Check if ability is in configuration
    local abilityConfig = AbilityConfiguration.GetAbility(abilityId)
    if abilityConfig and not abilityConfig.enabled then
        print("[ClientAbilities] Ability", abilityId, "is disabled in configuration")
        return
    end
    
    local clientModule = require(abilityPackage:WaitForChild("Client"))
    
    -- Check if GetSharedModule needs to be created or is a placeholder
    local needsInjection = false
    if not clientModule.GetSharedModule then
        needsInjection = true
        print("[ClientAbilities] Creating GetSharedModule for", abilityId)
    else
        -- Check if it's a placeholder that needs injection
        local success, result = pcall(clientModule.GetSharedModule)
        if not success and string.find(tostring(result), "inject") then
            needsInjection = true
            print("[ClientAbilities] Replacing placeholder GetSharedModule for", abilityId)
        else
            print("[ClientAbilities] GetSharedModule already properly implemented for", abilityId)
        end
    end
    
    if needsInjection then
        clientModule.GetSharedModule = function()
            local sharedMod = (require(abilityPackage.Shared) :: Types.Shared)

            sharedMod.GetAssets = function()
                return abilityPackage.Assets
            end

            sharedMod.GetConfig = function()
                return require(abilityPackage.Config)
            end

            return sharedMod
        end
    end
    
    -- Enhance with configuration data
    clientModule.GetConfiguration = function()
        return AbilityConfiguration.GetAbility(abilityId)
    end
    
    AbilityCache[abilityId] = clientModule
    print("[ClientAbilities] Loaded ability:", abilityId, "- Has Execute:", clientModule.Execute ~= nil)
end

local function _loadServerAbility(abilityId : string, abilityPackage: Types.AbilityPackage)
    print("[ClientAbilities Server] Loading ability:", abilityId)
    
    local serverModule = require(abilityPackage:WaitForChild("Server"))
    
    -- Check if GetSharedModule needs to be created or is a placeholder
    local needsInjection = false
    if not serverModule.GetSharedModule then
        needsInjection = true
        print("[ClientAbilities Server] Creating GetSharedModule for", abilityId)
    else
        -- Check if it's a placeholder that needs injection
        local success, result = pcall(serverModule.GetSharedModule)
        if not success and string.find(tostring(result), "inject") then
            needsInjection = true
            print("[ClientAbilities Server] Replacing placeholder GetSharedModule for", abilityId)
        else
            print("[ClientAbilities Server] GetSharedModule already properly implemented for", abilityId)
        end
    end
    
    if needsInjection then
        serverModule.GetSharedModule = function()
            local sharedMod = (require(abilityPackage.Shared) :: Types.Shared)
            
            sharedMod.GetAssets = function()
                return abilityPackage.Assets
            end
    
            sharedMod.GetConfig = function()
                return require(abilityPackage.Config)
            end
    
            return sharedMod
        end
    end
    
    AbilityCache[abilityId] = serverModule
    print("[ClientAbilities Server] Loaded ability:", abilityId)
end

if RunService:IsClient() then
   script.Loaders.LoadModule.OnClientEvent:Connect(_loadClientAbility)
else
   script.Loaders.LoadServerModule.Event:Connect(_loadServerAbility)
end

return Loader