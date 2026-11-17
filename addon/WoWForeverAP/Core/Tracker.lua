-- Decides whether a detected event becomes a check, and records it. The pure functions take their inputs
-- (db, inbox, guid); recordForPlayer wraps them with the live game state for the Detect/* files.
local _, ns = ...

local Tracker = {}
ns.Tracker = Tracker

--- The character record, slot key and inbox slot of a linked character; nil when it is not linked
--- or the inbox does not hold its slot (then nothing can be a check).
function Tracker.linkedSlot(db, inbox, guid)
    local character = db.characters[guid]
    if not character or not character.slotKey then
        return nil
    end
    local slot = ns.Inbox.slot(inbox, character.slotKey)
    if not slot then
        return nil
    end
    return character, character.slotKey, slot
end

--- The same for the logged-in character: character, slot key and inbox slot, nil unless it is linked and the
--- inbox holds its slot.
function Tracker.playerContext()
    local guid = ns.ready and UnitGUID("player")
    if not guid then
        return nil
    end
    return Tracker.linkedSlot(ns.db, ns.Inbox.current(), guid)
end

--- Records `locationId` for the linked character `guid` when the seed contains it and the server has not
--- checked it yet. Returns true when a new outbox entry was added.
function Tracker.record(db, inbox, guid, locationId, now)
    local _, slotKey, slot = Tracker.linkedSlot(db, inbox, guid)
    if not slot then
        return false
    end
    if not ns.Inbox.isLocationInSeed(slot, locationId) or ns.Inbox.isChecked(slot, locationId) then
        return false
    end
    return ns.DB.addCheck(db, slotKey, locationId, guid, now)
end

--- The same for the logged-in character, followed by chat feedback.
function Tracker.recordForPlayer(locationId)
    local guid = ns.ready and UnitGUID("player")
    if not guid then
        return false
    end
    local inbox = ns.Inbox.current()
    if not Tracker.record(ns.db, inbox, guid, locationId, time()) then
        return false
    end
    ns.Notify.say("CHECK_RECORDED", ns.Names.location(locationId))
    local _, slotKey, slot = Tracker.linkedSlot(ns.db, inbox, guid)
    ns.Notify.unsynced(ns.DB.unsyncedCount(ns.db, slotKey, ns.Inbox.checkedSet(slot)))
    return true
end

--- Marks the goal reached for the logged-in character's slot (once per slot).
function Tracker.goalForPlayer()
    local guid = ns.ready and UnitGUID("player")
    local inbox = ns.Inbox.current()
    if not guid or not Tracker.linkedSlot(ns.db, inbox, guid) then
        return false
    end
    local character = ns.db.characters[guid]
    if not ns.DB.setGoal(ns.db, character.slotKey, guid, time()) then
        return false
    end
    ns.Notify.say("GOAL_REACHED")
    return true
end
