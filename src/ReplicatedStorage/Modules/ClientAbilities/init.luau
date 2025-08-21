local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(game.ReplicatedStorage.Modules.Types.ClientAbilityTypes)

type Loader<T> = {
    GetAbility: (abilityId: number) -> T
}

local AbilityCache = {}
local Loader = {}

Loader.GetAbility = function(abilityId: string): any
    return AbilityCache[abilityId]
end

local function _loadClientAbility(abilityId : number, abilityPackage: Types.AbilityPackage)
    AbilityCache[abilityId] = require(abilityPackage:WaitForChild("Client"))
    AbilityCache[abilityId].GetSharedModule = function()
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

local function _loadServerAbility(abilityId : number, abilityPackage: Types.AbilityPackage)
    AbilityCache[abilityId] = require(abilityPackage:WaitForChild("Server"))
    AbilityCache[abilityId].GetSharedModule = function()
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

if RunService:IsClient() then
   script.Loaders.LoadModule.OnClientEvent:Connect(_loadClientAbility)
else
   script.Loaders.LoadServerModule.Event:Connect(_loadServerAbility)
end

return Loader