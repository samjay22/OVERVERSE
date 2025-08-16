-- Legacy Network Server - loads new NetworkServer
-- This file maintains backwards compatibility while the new system is being integrated

-- Load the new network server
local _NetworkServer = require(game.ServerStorage.Modules.Core.NetworkServer)

-- Keep the old CoreEvent for backwards compatibility
local CoreEvent = Instance.new("RemoteEvent")
CoreEvent.Name = "CoreEvent"
CoreEvent.Parent = game.ReplicatedStorage.Remotes

-- Backend-only routing for abilities and primary attacks
local _Character = require(game.ServerStorage.Modules.Entities.Character)
local AbilityComponent = require(game.ServerStorage.Modules.Components.AbilityComponent)
local WeaponComponent = require(game.ServerStorage.Modules.Components.WeaponComponent)
local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local _NetworkTypes = require(game.ReplicatedStorage.Modules.Types.NetworkTypes)

CoreEvent.OnServerEvent:Connect(function(player: Player, msg)
	if typeof(msg) ~= "table" or typeof(msg.t) ~= "string" then return end
	if msg.t == Enums.CoreMessageType.PrimaryWeapon then
		WeaponComponent.Primary(player, (msg :: any).action)
	elseif msg.t == Enums.CoreMessageType.Ability and (msg :: any).id then
		AbilityComponent.Activate(player, (msg :: any).id, (msg :: any).extra)
	end
end)

print("Legacy network server loaded with new NetworkServer integration")