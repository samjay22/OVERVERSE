--!strict
-- Dash ability - physics-based dash using linear velocity and motion profiling

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Enums = require(ReplicatedStorage.Modules.Types.Enums)
local AbilityTypes = require(game.ServerStorage.Modules.Types.AbilityTypes)

-- Tuning
local DASH_DISTANCE: number = 100 -- target dash distance (studs)
local MAX_SPEED: number = 100 -- peak horizontal speed (studs/s)
local MAX_ACCEL: number = 800 -- accel/decel (studs/s^2)
local DASH_COOLDOWN: number = 3 -- seconds
local DASH_STAMINA_COST: number = 15

-- Safety
local OBSTACLE_BUFFER: number = 1 -- stop this far from obstacle (studs)
local MIN_SPACE: number = 0.75 -- minimum space to allow a dash (studs)
local AHEAD_RAY: number = 6 -- dynamic lookahead (studs)
local STOP_EPS: number = 0.2 -- tolerance to stop (studs)

local function horizontalUnit(v: Vector3): Vector3
    local h = Vector3.new(v.X, 0, v.Z)
    if h.Magnitude < 1e-4 then
        return Vector3.zero
    end
    return h.Unit
end

-- Plan a jerk-limited trapezoidal profile (S-curve via smooth ramp of accel)
-- Returns a plan table with times/peaks; falls back to triangular if distance is short
local function planProfile(distance: number, vmax: number, amax: number)
    -- Ideal triangular peak if distance is too short for cruise
    local vPeakTri = math.sqrt(math.max(0, amax * distance))
    local triangular = vPeakTri <= vmax

    if triangular then
        -- Symmetric accelerate then decelerate
        local vPeak = vPeakTri
        local tRamp = vPeak / amax
        local tTotal = 2 * tRamp
        return {
            triangular = true,
            vPeak = vPeak,
            t1 = tRamp,           -- end accel
            t2 = tTotal,          -- end decel
            total = tTotal,
        }
    else
        -- Trapezoidal: accel to vmax, cruise, decel
        local tRamp = vmax / amax
        local dRamp = 0.5 * amax * tRamp * tRamp
        local dCruise = distance - 2 * dRamp
        local tCruise = math.max(0, dCruise / vmax)
        local t1 = tRamp
        local t2 = t1 + tCruise
        local t3 = t2 + tRamp
        return {
            triangular = false,
            vPeak = vmax,
            t1 = t1,              -- end accel
            t2 = t2,              -- end cruise
            t3 = t3,              -- end decel
            total = t3,
        }
    end
end

-- Smoothstep (for jerk-limited ramps)
local function smooth01(x: number): number
    x = math.clamp(x, 0, 1)
    return x * x * (3 - 2 * x)
end

local function _performDash(context: AbilityTypes.AbilityContext): AbilityTypes.AbilityResult
    warn("asd")
    local characterRef: AbilityTypes.CharacterRef = context.character
    if not characterRef.Character or not characterRef.Character.PrimaryPart or not characterRef.Humanoid then
        return { success = false, errorMessage = "No character model, PrimaryPart, or Humanoid" }
    end

    -- Prevent overlapping dashes
    if characterRef.StateManager:Get("IsDashing") then
        return { success = false, errorMessage = "Already dashing" }
    end

    local humanoid: Humanoid = characterRef.Humanoid :: Humanoid
    local rootPart: BasePart = characterRef.Character.PrimaryPart

    -- Direction on horizontal plane
    local desiredDir: Vector3 = context.direction or rootPart.CFrame.LookVector
    local dir: Vector3 = horizontalUnit(desiredDir)
    if dir == Vector3.zero then
        dir = horizontalUnit(rootPart.CFrame.LookVector)
        if dir == Vector3.zero then
            return { success = false, errorMessage = "No valid dash direction" }
        end
    end

    -- Precast to find available distance
    local startPos: Vector3 = rootPart.Position
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { characterRef.Character }

    local hit = workspace:Raycast(startPos, dir * DASH_DISTANCE, params)
    local allowed: number = DASH_DISTANCE
    if hit then
        allowed = math.max(0, (hit.Position - startPos).Magnitude - OBSTACLE_BUFFER)
    end
    if allowed < MIN_SPACE then
        return { success = false, errorMessage = "No space to dash" }
    end

    -- Plan motion
    local plan = planProfile(allowed, MAX_SPEED, MAX_ACCEL)

    -- Save/alter state
    local originalAutoRotate: boolean = humanoid.AutoRotate
    local originalWalkSpeed: number = humanoid.WalkSpeed
    humanoid.AutoRotate = false
    humanoid.WalkSpeed = 0
    characterRef.StateManager:Set("IsDashing", true)

    -- Take network ownership to prevent client from overriding velocity
    local originalOwner = rootPart:GetNetworkOwner()
    rootPart:SetNetworkOwner(nil)

    -- Mass-aware accel cap (feel stays consistent regardless of rig mass)
    local mass = rootPart.AssemblyMass
    local effectiveMaxAccel = MAX_ACCEL -- studs/s^2 (you can scale by mass if you later switch to forces)

    local alive = true
    local cleanupDone = false
    local start = rootPart.Position
    local t0 = os.clock()

    local con: RBXScriptConnection? = nil
    local diedConn = humanoid.Died:Connect(function()
        alive = false
    end)
    local ancestryConn = rootPart.AncestryChanged:Connect(function(_, parent)
        if not parent then
            alive = false
        end
    end)

    local function projected(pos: Vector3): number
        return (pos - start):Dot(dir)
    end

    local function cleanup()
        if cleanupDone then return end
        cleanupDone = true
        if con then con:Disconnect() end
        if diedConn.Connected then diedConn:Disconnect() end
        if ancestryConn.Connected then ancestryConn:Disconnect() end
        -- Zero horizontal velocity, keep vertical component
        local vel = rootPart.AssemblyLinearVelocity
        rootPart.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
        -- Restore humanoid state
        humanoid.AutoRotate = originalAutoRotate
        humanoid.WalkSpeed = originalWalkSpeed
        characterRef.StateManager:Set("IsDashing", false)
        -- Restore network ownership
        if originalOwner then
            -- pcall in case owner left
            pcall(function() rootPart:SetNetworkOwner(originalOwner) end)
        end
    end

    -- Drive velocity BEFORE physics step so it actually integrates
    con = RunService.Stepped:Connect(function(_time: number, _dt: number)
        if not alive then
            cleanup()
            return
        end

        local t = os.clock() - t0
        local s = projected(rootPart.Position)
        local remaining = math.max(0, allowed - s)

        -- Determine nominal target speed from profile
        local vNominal: number
        if plan.triangular then
            local t1 = plan.t1
            local t2 = plan.t2
            if t <= t1 then
                local n = smooth01(t / math.max(1e-6, t1))
                vNominal = plan.vPeak * n
            elseif t <= t2 then
                local n = smooth01((t2 - t) / math.max(1e-6, t1))
                vNominal = plan.vPeak * n
            else
                vNominal = 0
            end
        else
            local t1 = plan.t1
            local t2 = plan.t2
            local t3 = plan.t3 :: number
            if t <= t1 then
                local n = smooth01(t / math.max(1e-6, t1))
                vNominal = plan.vPeak * n
            elseif t <= t2 then
                vNominal = plan.vPeak
            elseif t <= t3 then
                local n = smooth01((t3 - t) / math.max(1e-6, t3 - t2))
                vNominal = plan.vPeak * n
            else
                vNominal = 0
            end
        end

        -- Dynamic obstacle-aware clamp: ensure we can stop within remaining distance
        local ahead = workspace:Raycast(rootPart.Position, dir * AHEAD_RAY, params)
        if ahead then
            local obsDist = math.max(0, (ahead.Position - rootPart.Position):Dot(dir) - OBSTACLE_BUFFER)
            remaining = math.min(remaining, obsDist)
        end

        -- Clamp speed so stopping distance <= remaining (uses effective accel; mass only matters if you switch to forces)
        local vCap = math.sqrt(math.max(0, 2 * effectiveMaxAccel * math.max(0, remaining)))
        local vTarget = math.min(vNominal, vCap)

        -- Apply horizontal velocity while preserving vertical component
        local vel = rootPart.AssemblyLinearVelocity
        local horiz = dir * vTarget
        rootPart.AssemblyLinearVelocity = Vector3.new(horiz.X, vel.Y, horiz.Z)

        -- Termination: finish exactly by distance, not by time
        if remaining <= STOP_EPS then
            cleanup()
            return
        end
    end)

    -- Safety timeout in case of edge cases (e.g., stuck)
    task.delay(3.5, function()
        if not cleanupDone then
            cleanup()
        end
    end)

    return {
        success = true,
        data = {
            distance = allowed,
            direction = dir,
            duration = plan.total,
            mass = mass,
        },
    }
end

-- Export the ability definition
return {
    id = Enums.AbilityId.Dash,
    type = "Active" :: "Active",
    name = "Dash",
    description = "Quickly dash forward a short distance",
    targetType = "Self" :: "Self",
    cooldown = DASH_COOLDOWN,
    staminaCost = DASH_STAMINA_COST,
    range = DASH_DISTANCE,
    castTime = 0,
    interruptible = false,
}