local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(game.ReplicatedStorage.Modules.Types.ClientAbilityTypes)

type Loader<T> = {
    GetAbility: (abilityId: number) -> T
}

local AbilityCache = {}
local Loader = {}

Loader.GetAbility = function(abilityId: string): any
    local cached = AbilityCache[abilityId]
    print("[ClientAbilities] GetAbility called for:", abilityId, "- Cached:", cached ~= nil)
    if cached and cached.Execute then
        print("[ClientAbilities] Ability has Execute method")
    end
    return cached
end

local function _loadClientAbility(abilityId : string, abilityPackage: Types.AbilityPackage)
    print("[ClientAbilities] Loading ability:", abilityId)
    
    local clientModule = require(abilityPackage:WaitForChild("Client"))
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
    
    AbilityCache[abilityId] = clientModule
    print("[ClientAbilities] Loaded ability:", abilityId, "- Has Execute:", clientModule.Execute ~= nil)
end

local function _loadServerAbility(abilityId : string, abilityPackage: Types.AbilityPackage)
    print("[ClientAbilities Server] Loading ability:", abilityId)
    
    local serverModule = require(abilityPackage:WaitForChild("Server"))
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
    
    AbilityCache[abilityId] = serverModule
    print("[ClientAbilities Server] Loaded ability:", abilityId)
end

if RunService:IsClient() then
   script.Loaders.LoadModule.OnClientEvent:Connect(_loadClientAbility)
else
   script.Loaders.LoadServerModule.Event:Connect(_loadServerAbility)
end

return Loader