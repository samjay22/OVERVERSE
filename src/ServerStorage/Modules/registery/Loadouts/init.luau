--!strict
-- Loadout registry - auto-discovers loadout definition modules

local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

export type Loadout = AbilityTypes.Loadout

local loadoutCache: {[string]: Loadout} = {}

local function loadDefinition(assetKey: string): Loadout?
    if loadoutCache[assetKey] then
        return loadoutCache[assetKey]
    end

    -- Look for a module with the asset key
    local loadoutModule: ModuleScript? = script:FindFirstChild(assetKey)
    if loadoutModule then
        local success: boolean, result: any = pcall(require, loadoutModule)
        if success and result and result.loadout then
            loadoutCache[assetKey] = result.loadout
            return result.loadout
        end
    end

    -- Check legacy modules with Definitions arrays
    for _, child: Instance in ipairs(script:GetChildren()) do
        if child:IsA("ModuleScript") then
            local ok: boolean, mod: any = pcall(require, child)
            if ok and mod and mod.Definitions then
                for _, def: any in ipairs(mod.Definitions) do
                    if def.assetKey == assetKey and def.loadout then
                        loadoutCache[assetKey] = def.loadout
                        return def.loadout
                    end
                end
            end
        end
    end

    return nil
end

local function loadAllDefinitions()
    for _, child: Instance in ipairs(script:GetChildren()) do
        if child:IsA("ModuleScript") then
            local ok: boolean, mod: any = pcall(require, child)
            if ok and mod then
                if mod.assetKey and mod.loadout then
                    -- Individual loadout module
                    loadoutCache[mod.assetKey] = mod.loadout
                elseif mod.Definitions then
                    -- Legacy module with Definitions array
                    for _, def: any in ipairs(mod.Definitions) do
                        if def.assetKey and def.loadout then
                            loadoutCache[def.assetKey] = def.loadout
                        end
                    end
                end
            end
        end
    end
end

local LoadoutRegistry = {}

function LoadoutRegistry.Get(assetKey: string): Loadout
    local loadout: Loadout? = loadDefinition(assetKey)
    if loadout then
        return loadout
    end
    
    -- Return default loadout if not found (match Loadout type)
    return {
        primaryAttacks = {},
        actives = {},
        passive = nil,
        animationPack = "Default",
    }
end

function LoadoutRegistry.GetAllLoadouts(): {[string]: Loadout}
    return loadoutCache
end

-- Auto-load all loadouts on first require
loadAllDefinitions()

return LoadoutRegistry
