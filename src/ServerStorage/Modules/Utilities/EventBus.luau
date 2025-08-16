--!strict
-- EventBus: lightweight local event hub using BindableEvents

export type Event<T...> = {
	Connect: (self: Event<T...>, fn: (T...) -> ()) -> RBXScriptConnection,
	Fire: (self: Event<T...>, T...) -> (),
}

local function createEvent<T...>(): Event<T...>
	local evt = Instance.new("BindableEvent")
	local api = {
		Connect = function(self, fn)
			return evt.Event:Connect(fn)
		end,
		Fire = function(self, ...: T...)
			evt:Fire(...)
		end,
	}
	(api :: any)._inst = evt
	return api
end

local EventBus = {}
EventBus.__index = EventBus

function EventBus.New()
	local self = setmetatable({}, EventBus)
	self._events = {} :: {[string]: any}
	return self
end

function EventBus:Get<T...>(name: string): Event<T...>
	local ev = self._events[name]
	if not ev then
		ev = createEvent()
		self._events[name] = ev
	end
	return ev
end

function EventBus:Destroy()
	for _, ev in pairs(self._events) do
		local inst = (ev :: any)._inst
		if inst and inst.Destroy then inst:Destroy() end
	end
	self._events = {}
end

return EventBus
