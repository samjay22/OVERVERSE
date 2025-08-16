--!strict
-- Weapon registry bootstrap: auto-discovers weapon handler modules

local WeaponService = require(game.ServerStorage.Modules.Services.WeaponService)

local function registerWeapon(service, def)
    if not def or not def.id then return end
    -- Accept both new and legacy shapes
    if def.OnAttack or def.OnHit or def.OnAction then
        service:RegisterWeapon(def.id, def)
    end
end

local function loadDefinitions(service)
    local candidates = {}
    for _, child in ipairs(script:GetChildren()) do
        if child:IsA("ModuleScript") then
            table.insert(candidates, child)
        end
    end
    local handlersFolder = script:FindFirstChild("Handlers")
    if handlersFolder then
        for _, child in ipairs(handlersFolder:GetChildren()) do
            if child:IsA("ModuleScript") then
                table.insert(candidates, child)
            end
        end
    end

    for _, child in ipairs(candidates) do
        if child:IsA("ModuleScript") then
            local ok, mod = pcall(require, child)
            if not ok or mod == nil then continue end

            if type(mod) == "table" then
                local defs = nil
                if mod.Definitions and type(mod.Definitions) == "table" then
                    defs = mod.Definitions
                elseif mod.id and (mod.OnAttack or mod.OnHit or mod.OnAction) then
                    -- Single weapon handler
                    defs = {mod}
                else
                    -- Check if it's an array of handlers
                    local isArray = false
                    for k, _ in pairs(mod) do
                        if type(k) == "number" then isArray = true break end
                    end
                    if isArray then defs = mod else defs = {mod} end
                end

                for _, d in ipairs(defs) do
                    pcall(function()
                        registerWeapon(service, d)
                    end)
                end
            end
        end
    end
end

return function(weaponService)
    if not weaponService then return end
    loadDefinitions(weaponService)
end
