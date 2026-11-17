-- /wfap slash command and the addon-compartment click.
local _, ns = ...

local Commands = {}
ns.Commands = Commands

--- Splits "link 2" into ("link", "2"): the first word lower-cased, the rest trimmed.
function Commands.parse(message)
    local word, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    return word:lower(), rest
end

--- Which slot an argument of /wfap link picks. Returns the slot key, or nil plus "none" (no slots),
--- "choose" (several slots and no argument) or "bad" (argument is not a listed number).
function Commands.resolveSlot(slotKeys, argument)
    if #slotKeys == 0 then
        return nil, "none"
    end
    if argument == "" then
        if #slotKeys == 1 then
            return slotKeys[1]
        end
        return nil, "choose"
    end
    local index = tonumber(argument)
    local slotKey = index and index % 1 == 0 and slotKeys[index]
    if slotKey then
        return slotKey
    end
    return nil, "bad"
end

local function player()
    local guid = ns.ready and UnitGUID("player")
    return guid, guid and ns.db.characters[guid]
end

--- The logged-in character when it is linked, its slot key, and its inbox slot (nil while the inbox lacks it).
local function linkedContext()
    local guid, character = player()
    if not (character and character.slotKey) then
        return nil
    end
    local _, _, slot = ns.Tracker.linkedSlot(ns.db, ns.Inbox.current(), guid)
    return character, character.slotKey, slot
end

local handlers = {}

function handlers.status()
    local character, slotKey, slot = linkedContext()
    if not character then
        ns.Notify.say("NOT_LINKED")
        ns.Notify.say("STATUS_SLOTS", #ns.Inbox.slotKeys(ns.Inbox.current()))
        return
    end
    if not slot then
        ns.Notify.say("SLOT_MISSING", character.slotKey)
        return
    end
    local counts = ns.Inbox.counts(slot)
    local unsynced = ns.DB.unsyncedCount(ns.db, slotKey, ns.Inbox.checkedSet(slot))
    ns.Notify.say("STATUS_LINKED", slotKey)
    ns.Notify.say("STATUS_ITEMS", counts.items)
    ns.Notify.say("STATUS_OPEN", math.max(counts.open - unsynced, 0))
    ns.Notify.say("STATUS_UNSYNCED", unsynced)
end

function handlers.link(argument)
    local slotKeys = ns.Inbox.slotKeys(ns.Inbox.current())
    local slotKey, problem = Commands.resolveSlot(slotKeys, argument)
    if slotKey then
        ns.Link.linkPlayer(slotKey)
    elseif problem == "none" then
        ns.Notify.say("LINK_NO_SLOTS")
    elseif problem == "bad" then
        ns.Notify.say("LINK_BAD_INDEX")
    else
        ns.Notify.say("LINK_CHOOSE")
    end
    if problem == "bad" or problem == "choose" then
        for index, key in ipairs(slotKeys) do
            ns.Notify.say("LINK_SLOT_LINE", index, key)
        end
    end
end

function handlers.unlink()
    local guid = player()
    if guid and ns.Link.unlink(ns.db, guid) then
        ns.Notify.say("UNLINK_OK")
    else
        ns.Notify.say("NOT_LINKED")
    end
end

function handlers.items()
    local character, _, slot = linkedContext()
    if not character then
        ns.Notify.say("NOT_LINKED")
        return
    end
    if not slot then
        ns.Notify.say("SLOT_MISSING", character.slotKey)
        return
    end
    local received = ns.Inbox.items(slot)
    if #received == 0 then
        ns.Notify.say("ITEMS_EMPTY")
        return
    end
    ns.Notify.say("ITEMS_HEADER", #received)
    for _, line in ipairs(ns.Names.itemLines(received, 1, #received)) do
        ns.Notify.print(line)
    end
    character.seenItemCount = #received
end

function handlers.rules()
    local character, _, slot = linkedContext()
    if not character then
        ns.Notify.say("NOT_LINKED")
    elseif not slot then
        ns.Notify.say("SLOT_MISSING", character.slotKey)
    else
        ns.Economy.printRules(slot)
    end
end

function handlers.care(argument)
    local character, slotKey, slot = linkedContext()
    if not character then
        ns.Notify.say("NOT_LINKED")
    elseif not slot then
        ns.Notify.say("SLOT_MISSING", character.slotKey)
    elseif argument:lower() == "use" then
        ns.Economy.askToUse(ns.db, slotKey, slot)
    else
        ns.Economy.printCare(ns.db, slotKey, slot)
    end
end

function handlers.capture(argument)
    local choice = argument:lower()
    if (choice ~= "on" and choice ~= "off") or not ns.ready then
        ns.Notify.say("CAPTURE_USAGE")
        return
    end
    ns.Capture.setEnabled(ns.db, choice == "on")
    ns.Notify.say(choice == "on" and "CAPTURE_ON" or "CAPTURE_OFF")
end

function handlers.help()
    ns.Notify.say("HELP_HEADER")
    local keys = { "HELP_STATUS", "HELP_LINK", "HELP_UNLINK", "HELP_ITEMS", "HELP_RULES", "HELP_CARE", "HELP_CAPTURE" }
    for _, key in ipairs(keys) do
        ns.Notify.print(ns.L[key])
    end
end

--- Runs one /wfap command line; anything unknown shows the help.
function Commands.run(message)
    local word, rest = Commands.parse(message)
    local handler = handlers[word] or handlers.help
    handler(rest)
end

SLASH_WFAP1 = "/wfap"
SlashCmdList["WFAP"] = Commands.run

--- Addon compartment (minimap addon menu) click: show the status.
function WoWForeverAP_OnCompartmentClick()
    Commands.run("status")
end
