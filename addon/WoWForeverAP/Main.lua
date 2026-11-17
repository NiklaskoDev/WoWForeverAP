-- Wiring: initialise the SavedVariables when the addon loads, then set up the character at login.
local _, ns = ...

local function onAddonLoaded(loadedName)
    if loadedName ~= ns.name then
        return
    end
    local db, errorKey = ns.DB.init(WoWForeverAP_DB)
    if db then
        WoWForeverAP_DB = db
        ns.db = db
    else
        ns.dbError = errorKey -- shown at login, when the chat frame is ready
    end
end

--- Linked character: drop confirmed checks from the outbox, announce new items and unsynced checks.
local function refreshLinkedCharacter(character, slotKey, slot)
    ns.DB.prune(ns.db, slotKey, ns.Inbox.checkedSet(slot))
    ns.Notify.newItems(slot, character.seenItemCount or 0)
    character.seenItemCount = #ns.Inbox.items(slot)
    ns.Notify.unsynced(ns.DB.unsyncedCount(ns.db, slotKey, ns.Inbox.checkedSet(slot)))
end

local function onPlayerLogin()
    if not ns.db then
        ns.Notify.say(ns.dbError or "DB_NEWER")
        return
    end
    local guid = UnitGUID("player")
    local _, classFile = UnitClass("player")
    local character = ns.DB.touchCharacter(ns.db, guid, UnitName("player"), UnitFactionGroup("player"), classFile)
    ns.ready = true
    if not character.slotKey then
        ns.Link.promptIfNeeded()
        return
    end
    local _, slotKey, slot = ns.Tracker.linkedSlot(ns.db, ns.Inbox.current(), guid)
    if slot then
        refreshLinkedCharacter(character, slotKey, slot)
        ns.Professions.scan() -- catches skill gained while the addon was not looking
    else
        ns.Notify.say("SLOT_MISSING", character.slotKey)
    end
end

ns.Events.register("ADDON_LOADED", onAddonLoaded)
ns.Events.register("PLAYER_LOGIN", onPlayerLogin)
