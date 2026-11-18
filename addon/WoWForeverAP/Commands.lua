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

--- Chat lines with the slot's faction, start zone, goal level and professions, from the inbox options.
--- Professions the generated data does not know are listed as primary ones, under their numbered name.
function Commands.startLines(slot)
    local options = ns.Inbox.options(slot)
    local primary, secondary = {}, {}
    for _, skillLineId in ipairs(type(options.professions) == "table" and options.professions or {}) do
        local known = ns.Data.professions[skillLineId]
        local list = known and known.kind == "secondary" and secondary or primary
        list[#list + 1] = ns.Names.profession(skillLineId)
    end
    local none = ns.L.START_NONE
    return {
        ns.L.START_FACTION:format(ns.Names.side(options.faction)),
        ns.L.START_ZONE:format(options.startZone and ns.Names.zone(options.startZone) or "?"),
        ns.L.START_GOAL:format(tonumber(options.goalLevel) or 0),
        ns.L.START_PRIMARY:format(#primary > 0 and table.concat(primary, ", ") or none),
        ns.L.START_SECONDARY:format(#secondary > 0 and table.concat(secondary, ", ") or none),
    }
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

function handlers.start()
    local character, _, slot = linkedContext()
    if character then
        if not slot then
            ns.Notify.say("SLOT_MISSING", character.slotKey)
            return
        end
        for _, line in ipairs(Commands.startLines(slot)) do
            ns.Notify.print(line)
        end
        return
    end
    local inbox = ns.Inbox.current()
    local slotKeys = ns.Inbox.slotKeys(inbox)
    if #slotKeys == 0 then
        ns.Notify.say("LINK_NO_SLOTS")
        return
    end
    for index, key in ipairs(slotKeys) do
        ns.Notify.say("START_SLOT_HEADER", index, ns.Style.escape(key))
        for _, line in ipairs(Commands.startLines(ns.Inbox.slot(inbox, key))) do
            ns.Notify.print(line)
        end
    end
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

function handlers.panel()
    ns.Panel.toggle()
end

function handlers.options()
    if not ns.UISettings.open() then
        ns.Notify.say("OPTIONS_UNAVAILABLE")
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
    local keys = {
        "HELP_PANEL", "HELP_STATUS", "HELP_START", "HELP_LINK", "HELP_UNLINK", "HELP_ITEMS", "HELP_RULES", "HELP_CARE",
        "HELP_OPTIONS", "HELP_CAPTURE",
    }
    for _, key in ipairs(keys) do
        ns.Notify.print(ns.L[key])
    end
end

--- Runs one /wfap command line: no command opens the window, anything unknown shows the help.
function Commands.run(message)
    local word, rest = Commands.parse(message)
    local handler = handlers[word] or (word == "" and handlers.panel) or handlers.help
    handler(rest)
end

SLASH_WFAP1 = "/wfap"
SlashCmdList["WFAP"] = Commands.run

--- Addon compartment (minimap addon menu) click: open or close the window.
function WoWForeverAP_OnCompartmentClick()
    Commands.run("")
end
