local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Abilities = game.ReplicatedStorage.Modules.Abilities

local Types = require(game.ReplicatedStorage.Modules.Types.AbilityTypes)

local SetCharacter : RemoteEvent = game.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SetCharacter")
local CastAbility : RemoteEvent = game.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CastAbility")

local CharacterName : string?
local CanCast : boolean = true
local Down : boolean = true

RemoteEvent.OnClientEvent:Connect(function(name: string)
    CharacterName = name
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
    if gameProcessed then
        return
    end
    
    local abilities = Abilities:FindFirstChild(CharacterName)
    if not abilities then
        error("Abilities for character '" .. tostring(CharacterName) .. "' not found.")
    end

    while Down do
        if not CanCast then
            return
        end

        local data = require(abilities)
        local clientAbility : Types.AbilityModule = data[Enum.KeyCode] or data[input.UserInputType]
        if clientAbility and clientAbility.Client and clientAbility.Client.OnUse then
        task.spawn(function()
            CanCast = false
            clientAbility.Client:OnUse(Players.LocalPlayer)
            CanCast = true
        end)
    end
        task.wait()
    end
end)

