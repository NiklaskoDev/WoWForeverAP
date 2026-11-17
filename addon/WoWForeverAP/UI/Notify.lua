-- Chat output: one prefix and one accent colour (Blizzard gold family), all texts from ns.L.
local _, ns = ...

local Notify = {}
ns.Notify = Notify

Notify.PREFIX = "|cffd4a017[AP]|r"
Notify.MAX_NEW_ITEM_LINES = 5

local ALERT_COLOR = { r = 1, g = 0.1, b = 0.1 }

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

--- Shows `text` on screen (honor-system warning) and in chat. On screen it uses the raid warning frame, the way
--- the 12.x UI source does (RaidWarningUtil.AddMessage; RaidNotice_AddMessage is its deprecated predecessor),
--- then the error frame. Returns which one was used: "raidwarning", "raidnotice", "errorframe" or "chat".
function Notify.alert(text)
    local used = "chat"
    if RaidWarningUtil and type(RaidWarningUtil.AddMessage) == "function" then
        if pcall(RaidWarningUtil.AddMessage, text, ALERT_COLOR) then
            used = "raidwarning"
        end
    elseif type(RaidNotice_AddMessage) == "function" and RaidWarningFrame then
        if pcall(RaidNotice_AddMessage, RaidWarningFrame, text, ALERT_COLOR) then
            used = "raidnotice"
        end
    end
    if used == "chat" and UIErrorsFrame and pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, 1, 0.1, 0.1, 1) then
        used = "errorframe"
    end
    Notify.print(text)
    return used
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
