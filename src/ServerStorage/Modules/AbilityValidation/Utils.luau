--!strict

local Utils = {}

function Utils.now(): number
    return workspace:GetServerTimeNow()
end

function Utils.isFinite(n: number?): boolean
    if n == nil then return false end
    if n ~= n then return false end -- NaN
    if n == math.huge or n == -math.huge then return false end
    return true
end

function Utils.isFiniteVector3(v: Vector3?): boolean
    if v == nil then return false end
    return Utils.isFinite(v.X) and Utils.isFinite(v.Y) and Utils.isFinite(v.Z)
end

function Utils.shallowClone<T>(t: T): T
    if t == nil then
        return ({} :: any) :: T
    end
    local ok, cloned = pcall(function()
        return table.clone(t :: any)
    end)
    if ok then
        return (cloned :: any) :: T
    end
    return (t :: any) :: T
end

function Utils.safeRequire(moduleScript: ModuleScript): (boolean, any)
    return pcall(require, moduleScript)
end

return Utils
