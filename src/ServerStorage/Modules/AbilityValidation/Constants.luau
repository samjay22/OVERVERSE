--!strict

local Constants = {
    POSITION_TOLERANCE_BASE = 10.0, -- studs
    VELOCITY_TOLERANCE = 50.0, -- studs/s
    TIME_TOLERANCE = 0.2, -- s (max future skew)
    MAX_POSITION_DESYNC = 50.0, -- studs (hard ceiling)
    RATE_LIMIT_TOKENS_PER_SEC = 1000, -- abilities per second
    RATE_LIMIT_BUCKET_SIZE = 50, -- burst size
    FUDGE_STUDS = 25,
}

function Constants.AllowedPositionDesync(vel: number, dt: number): number
    local dynamic = Constants.POSITION_TOLERANCE_BASE + vel * dt
    -- Hard ceiling = never allow more than MAX_POSITION_DESYNC
    return math.min(dynamic, Constants.MAX_POSITION_DESYNC)
end

return Constants
