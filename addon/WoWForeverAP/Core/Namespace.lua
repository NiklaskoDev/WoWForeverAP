-- Addon namespace, constants and the event dispatcher. Every other file receives the same `ns` table.
local addonName, ns = ...

ns.name = addonName
ns.SCHEMA = 1 -- version of the SavedVariables and inbox layouts; the client writes the same number

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
