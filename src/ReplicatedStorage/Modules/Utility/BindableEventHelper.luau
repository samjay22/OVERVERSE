
local BindableEventHelper = {}
local BindableEvents : {[string]: BindableEvent} = {}

function BindableEventHelper.CreateBindableEvent(name: string): BindableEvent
    local event = Instance.new("BindableEvent")
    event.Name = name
    BindableEvents[name] = event
    return event
end

function BindableEventHelper.GetBindableEvent(name: string): BindableEvent?
    return BindableEvents[name]
end

return BindableEventHelper
