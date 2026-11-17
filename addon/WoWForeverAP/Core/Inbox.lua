-- Reads the client-written WoWForeverAP_Inbox: validation and lookups. Pure: functions take the inbox table.
local _, ns = ...

local Inbox = {}
ns.Inbox = Inbox

--- The inbox global written by the WoWForeverAP_Inbox addon (nil if that addon is missing).
function Inbox.current()
    return WoWForeverAP_Inbox
end

--- True when the table has the layout this addon version understands; otherwise false plus a locale key.
function Inbox.validate(inbox)
    if type(inbox) ~= "table" or inbox.schema ~= ns.SCHEMA or type(inbox.slots) ~= "table" then
        return false, "INBOX_INVALID"
    end
    return true
end

--- Slot keys of the inbox, sorted, so `/wfap link <n>` numbers stay stable between sessions.
function Inbox.slotKeys(inbox)
    local keys = {}
    if Inbox.validate(inbox) then
        for key, slot in pairs(inbox.slots) do
            if type(key) == "string" and type(slot) == "table" then
                keys[#keys + 1] = key
            end
        end
        table.sort(keys)
    end
    return keys
end

function Inbox.slot(inbox, slotKey)
    if not Inbox.validate(inbox) then
        return nil
    end
    local slot = inbox.slots[slotKey]
    return type(slot) == "table" and slot or nil
end

local function contains(set, id)
    return type(set) == "table" and set[id] == true
end

function Inbox.isLocationInSeed(slot, locationId)
    return contains(slot.locations, locationId)
end

function Inbox.isChecked(slot, locationId)
    return contains(slot.checked, locationId)
end

--- The server's checked set (location id to true); an empty table when the client wrote none.
function Inbox.checkedSet(slot)
    return type(slot.checked) == "table" and slot.checked or {}
end

local function items(slot)
    return type(slot.items) == "table" and slot.items or {}
end

--- How many times the slot received the item with `itemId`.
function Inbox.countItem(slot, itemId)
    local count = 0
    for _, item in ipairs(items(slot)) do
        if item.id == itemId then
            count = count + 1
        end
    end
    return count
end

function Inbox.hasItem(slot, itemId)
    return Inbox.countItem(slot, itemId) > 0
end

--- Counts for the status line: locations in the seed, already checked, still open, items received.
function Inbox.counts(slot)
    local total, checked = 0, 0
    for locationId in pairs(type(slot.locations) == "table" and slot.locations or {}) do
        total = total + 1
        if Inbox.isChecked(slot, locationId) then
            checked = checked + 1
        end
    end
    return { locations = total, checked = checked, open = total - checked, items = #items(slot) }
end

--- Received items in the order the server sent them.
function Inbox.items(slot)
    return items(slot)
end

--- Option table of the slot (faction, goalLevel, ...); empty when the client wrote none.
function Inbox.options(slot)
    return type(slot.options) == "table" and slot.options or {}
end
