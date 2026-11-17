-- Addon namespace, constants and the event dispatcher. Every other file receives the same `ns` table.
local addonName, ns = ...

ns.name = addonName
ns.SCHEMA = 1 -- version of the SavedVariables and inbox layouts; the client writes the same number

--- Calls `fn` when it exists and returns its results; a missing function or an error (for example from
--- restricted values) counts as "no answer" and returns nothing.
function ns.tryCall(fn, ...)
    if type(fn) ~= "function" then
        return
    end
    local results = { pcall(fn, ...) }
    if not results[1] then
        return
    end
    return unpack(results, 2)
end

local Events = {}
ns.Events = Events

local handlers = {}
local frame

local function reportError(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(err)
    end
end

--- Calls every handler of `event`; one failing handler must not keep the others from running.
function Events.dispatch(event, ...)
    for _, handler in ipairs(handlers[event] or {}) do
        local ok, err = pcall(handler, ...)
        if not ok then
            reportError(err)
        end
    end
end

--- Registers `handler(...)` for a game event; the frame is created on first use.
function Events.register(event, handler)
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", function(_, firedEvent, ...)
            Events.dispatch(firedEvent, ...)
        end)
    end
    handlers[event] = handlers[event] or {}
    handlers[event][#handlers[event] + 1] = handler
    frame:RegisterEvent(event)
end

--- Like register, for an event the client may not know: skips it (and returns false) when the client reports it as
--- invalid or refuses the registration, so one missing event cannot stop the rest of the file from loading.
function Events.tryRegister(event, handler)
    local isEventValid = C_EventUtils and C_EventUtils.IsEventValid
    if type(isEventValid) == "function" and isEventValid(event) ~= true then
        return false
    end
    return (pcall(Events.register, event, handler))
end
