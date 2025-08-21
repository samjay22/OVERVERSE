--!strict
-- Minimal ErrorHandler shim to satisfy dependencies without changing behavior

export type ErrorContext = { scope: string, op: string?, userId: number? }

local ErrorHandler = {}

function ErrorHandler.CreateContext(scope: string, op: string?, userId: number?): ErrorContext
	return { scope = scope, op = op, userId = userId }
end

function ErrorHandler.SafeCall<T>(fn: () -> T, _ctx: ErrorContext?): { success: boolean, data: T? , error: any? }
	local ok, res = pcall(fn)
	if ok then
		return { success = true, data = res }
	end
	return { success = false, error = res }
end

function ErrorHandler.SafeCallWithHandler<T>(fn: () -> T, onError: (any) -> (), _ctx: ErrorContext?): T
	local ok, res = pcall(fn)
	if ok then return res end
	onError(res)
	return (nil :: any) :: T
end

function ErrorHandler.ValidateParams(obj: {[string]: any}, required: {string}, _ctx: ErrorContext?): boolean
	for _, key in ipairs(required) do
		if obj[key] == nil then return false end
	end
	return true
end

-- Logging helpers
function ErrorHandler.Debug(msg: string, _ctx: ErrorContext?) print("[DEBUG]", msg) end
function ErrorHandler.Info(msg: string, _ctx: ErrorContext?) print("[INFO]", msg) end
function ErrorHandler.Warn(msg: string, _ctx: ErrorContext?) warn("[WARN]", msg) end
function ErrorHandler.Error(msg: string, _ctx: ErrorContext?) warn("[ERROR]", msg) end
function ErrorHandler.SetLogLevel(_level: string) end

return ErrorHandler
