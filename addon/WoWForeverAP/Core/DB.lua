-- SavedVariables WoWForeverAP_DB: initialisation, migration, character records and the outbox.
-- Pure: every function takes the db table, so the specs run without the game.
local _, ns = ...

local DB = {}
ns.DB = DB

local KIND_CHECK = "check"

local function ensureTables(db)
    db.characters = db.characters or {}
    db.slots = db.slots or {}
end

--- Upgrades `db` to the current schema in place. Safe to run repeatedly.
--- Returns true, or false plus a locale key when the data comes from a newer addon version.
function DB.migrate(db)
    local schema = db.schema or ns.SCHEMA
    if schema > ns.SCHEMA then
        return false, "DB_NEWER"
    end
    -- Schema 1 is the first version: later versions add their upgrade steps here, in order.
    db.schema = ns.SCHEMA
    ensureTables(db)
    return true
end

--- Returns (db, errorKey). `existing` is the loaded SavedVariable, nil on the first run.
function DB.init(existing)
    local db = existing or {}
    local ok, errorKey = DB.migrate(db)
    if not ok then
        return nil, errorKey
    end
    return db
end

--- Creates or refreshes the record of the character with `guid`; the name can change.
function DB.touchCharacter(db, guid, name, faction, classFile)
    local character = db.characters[guid] or {}
    db.characters[guid] = character
    character.name = name
    character.faction = faction
    character.classFile = classFile
    return character
end

local function slotTable(db, slotKey)
    local slot = db.slots[slotKey] or {}
    db.slots[slotKey] = slot
    slot.outbox = slot.outbox or {}
    return slot
end

function DB.hasCheck(db, slotKey, locationId)
    local slot = db.slots[slotKey]
    for _, entry in ipairs(slot and slot.outbox or {}) do
        if entry.kind == KIND_CHECK and entry.id == locationId then
            return true
        end
    end
    return false
end

--- Appends a check to the slot's outbox. Returns false (and changes nothing) when it is already there.
function DB.addCheck(db, slotKey, locationId, guid, now)
    if DB.hasCheck(db, slotKey, locationId) then
        return false
    end
    local outbox = slotTable(db, slotKey).outbox
    outbox[#outbox + 1] = { kind = KIND_CHECK, id = locationId, char = guid, t = now }
    return true
end

--- Drops outbox checks the server already knows (`checked` maps location id to true). Returns how many.
function DB.prune(db, slotKey, checked)
    local slot = db.slots[slotKey]
    if not slot or not slot.outbox then
        return 0
    end
    local kept, removed = {}, 0
    for _, entry in ipairs(slot.outbox) do
        if entry.kind == KIND_CHECK and checked[entry.id] then
            removed = removed + 1
        else
            kept[#kept + 1] = entry
        end
    end
    slot.outbox = kept
    return removed
end

--- Number of outbox checks the server has not confirmed yet.
function DB.unsyncedCount(db, slotKey, checked)
    local slot = db.slots[slotKey]
    local count = 0
    for _, entry in ipairs(slot and slot.outbox or {}) do
        if entry.kind == KIND_CHECK and not (checked and checked[entry.id]) then
            count = count + 1
        end
    end
    return count
end

--- Records that a linked character reached the goal. Returns false when the slot already has it.
function DB.setGoal(db, slotKey, guid, now)
    local slot = slotTable(db, slotKey)
    if slot.goal then
        return false
    end
    slot.goal = { char = guid, t = now }
    return true
end

--- Care Packages the slot has used (honor-system counter); 0 when none was recorded.
function DB.carePackagesUsed(db, slotKey)
    local slot = db.slots[slotKey]
    local count = slot and slot.carePackagesUsed
    return type(count) == "number" and count > 0 and count or 0
end

--- Counts one more used Care Package for the slot and returns the new total.
function DB.addCarePackageUse(db, slotKey)
    local slot = slotTable(db, slotKey)
    slot.carePackagesUsed = DB.carePackagesUsed(db, slotKey) + 1
    return slot.carePackagesUsed
end
