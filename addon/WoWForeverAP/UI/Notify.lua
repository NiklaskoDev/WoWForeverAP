-- Chat output: one prefix and one accent colour (Blizzard gold family), all texts from ns.L.
local _, ns = ...

local Notify = {}
ns.Notify = Notify

Notify.PREFIX = "|cffd4a017[AP]|r"
Notify.MAX_NEW_ITEM_LINES = 5

--- Where text goes; replaced in specs.
function Notify.out(text)
    print(text)
end

function Notify.print(text)
    Notify.out(Notify.PREFIX .. " " .. text)
end

--- Prints the locale string `key`, formatted with the extra arguments when there are any.
function Notify.say(key, ...)
    local text = ns.L[key]
    if select("#", ...) > 0 then
        text = text:format(...)
    end
    Notify.print(text)
end

--- Reminder that checks only reach the server after the game wrote its SavedVariables.
function Notify.unsynced(count)
    if count > 0 then
        Notify.say("UNSYNCED", count)
    end
end

--- Lists the items received since the character last looked (first lines only; /wfap items shows all).
function Notify.newItems(slot, seenCount)
    local received = ns.Inbox.items(slot)
    local fresh = #received - seenCount
    if fresh <= 0 then
        return
    end
    Notify.say("NEW_ITEMS", fresh)
    local shown = math.min(fresh, Notify.MAX_NEW_ITEM_LINES)
    local lines = ns.Names.itemLines(received, seenCount + 1, seenCount + shown)
    for _, line in ipairs(lines) do
        Notify.print(line)
    end
    if fresh > shown then
        Notify.say("MORE_ITEMS", fresh - shown)
    end
end
