local RunService = game:GetService("RunService")

local Types = require(game.ReplicatedStorage.Modules.Types.AbilityTypes)

local loaded = {}

for _, module in ipairs(script:GetChildren()) do
    if module:IsA("ModuleScript") then
        local success, result : Types.AbilityModule = pcall(require, module)
        if success then
            loaded[result.Enum] = result
            loaded[module.Name] = result
            if RunService:IsServer() then
               RunService.Heartbeat:Connect(function(dt)
                   result.Server:OnUpdate(dt)
               end)
            end
        else
            warn("Failed to load ability config from module:", module.Name, result)
        end
    end
end

return loaded