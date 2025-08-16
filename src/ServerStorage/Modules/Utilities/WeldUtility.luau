--!nonstrict
-- WeldUtility.luau
-- Utility for welding two parts together

local WeldUtility = {}

-- Welds partB to partA at the given offset (relative to partA)
function WeldUtility.WeldParts(partA: BasePart, partB: BasePart, offset: CFrame?)
    offset = offset or CFrame.new()
    partB.CFrame = partA.CFrame * offset
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = partA
    weld.Part1 = partB
    weld.Parent = partB
    return weld
end

return WeldUtility
