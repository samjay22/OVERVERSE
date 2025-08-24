--!strict
-- WeldUtility.luau
-- Utility for welding two parts together

export type WeldUtility = {
    WeldParts: (partA: BasePart, partB: BasePart, offset: CFrame?) -> WeldConstraint,
}

local WeldUtility = {}

-- Welds partB to partA at the given offset (relative to partA)
function WeldUtility.WeldParts(partA: BasePart, partB: BasePart, offset: CFrame?): WeldConstraint
    local usedOffset = offset or CFrame.new()
    partB.CFrame = partA.CFrame * usedOffset
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = partA
    weld.Part1 = partB
    weld.Parent = partB
    return weld
end

return WeldUtility
