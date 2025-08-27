--!strict
-- Effect registry - auto-discovers effect definition modules (asset handler pattern)

local EffectTypes = require(game.ServerStorage.Modules.Types.EffectTypes)

export type EffectId = EffectTypes.EffectId
export type EffectDef = EffectTypes.EffectDef

local effectCache: {[EffectId]: EffectDef} = {}

local function loadEffect(effectId: EffectId): EffectDef?
    if effectCache[effectId] then
        return effectCache[effectId]
    end

    local definitionsFolder: Folder? = script:FindFirstChild("Definitions")
    if not definitionsFolder then
        warn("No Definitions folder found for effects")
        return nil
    end

    -- Look for a module with the effect ID
    local effectModule: ModuleScript? = definitionsFolder:FindFirstChild(effectId)
    if not effectModule then
        return nil
    end

    local success: boolean, result: any = pcall(require, effectModule)
    if success and result then
        -- Validate the effect definition
        if result.id == effectId and result.onApply and result.onRemove then
            effectCache[effectId] = result
            return result
        else
            warn("Invalid effect definition in module:", effectId)
        end
    else
        warn("Failed to load effect definition:", effectId, result)
    end

    return nil
end

local function loadAllEffects()
    local definitionsFolder: Folder? = script:FindFirstChild("Definitions")
    if not definitionsFolder then
        return
    end

    for _, child: Instance in ipairs(definitionsFolder:GetChildren()) do
        if child:IsA("ModuleScript") then
            local effectId: string = child.Name
            loadEffect(effectId)
        end
    end
end

local EffectRegistry = {}

function EffectRegistry.GetHandlerName(): string
    return "Effects"
end

function EffectRegistry.GetAllEffects(): {[EffectId]: EffectDef}
    return effectCache
end

function EffectRegistry.GetEffect(effectId: EffectId): EffectDef?
    return loadEffect(effectId)
end

function EffectRegistry.PreloadEffects(effectIds: {EffectId}): ()
    for _, id: EffectId in effectIds do
        loadEffect(id)
    end
end

-- Auto-load all effects on first require
loadAllEffects()

return EffectRegistry
