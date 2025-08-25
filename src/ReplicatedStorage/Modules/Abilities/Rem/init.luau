local Types = require(game.ReplicatedStorage.Modules.Types.AbilityTypes)

local loaded = {}

for _, module in ipairs(script:GetChildren()) do
    if module:IsA("ModuleScript") then
        local success, result : Types.AbilityModule = pcall(require, module)
        if success then
            loaded[result.Enum] = result
        else
            warn("Failed to load ability config from module:", module.Name, result)
        end
    end
end

return loaded