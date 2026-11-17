-- Developer capture mode (/wfap capture on|off): logs zone ids, names and level ranges and every turned-in
-- quest into WoWForeverAP_DB.capture, using only official API reads. tools/import_capture.py turns the
-- SavedVariables into review CSVs; nothing here changes what the addon does for the player.
local _, ns = ...

local Capture = {}
ns.Capture = Capture

--- The capture table of the db, created on first use.
function Capture.table(db)
    db.capture = db.capture or {}
    db.capture.zones = db.capture.zones or {}
    db.capture.quests = db.capture.quests or {}
    return db.capture
end

function Capture.isEnabled(db)
    return db.capture ~= nil and db.capture.enabled == true
end

--- Switches capture on or off. Turning it on stores the client's build and locale for the data review.
function Capture.setEnabled(db, enabled)
    local capture = Capture.table(db)
    capture.enabled = enabled
    if enabled then
        local version, build, buildDate, toc = GetBuildInfo()
        capture.build = { version = version, build = build, date = buildDate, toc = toc }
        capture.locale = GetLocale()
    end
end

function Capture.recordZone(capture, uiMapId, name, minLevel, maxLevel, now)
    capture.zones[uiMapId] = { name = name, minLevel = minLevel, maxLevel = maxLevel, seen = now }
end

function Capture.recordQuest(capture, questId, title, uiMapId, level, faction, now)
    capture.quests[questId] = { title = title, uiMapId = uiMapId, level = level, faction = faction, seen = now }
end

local function currentMap()
    local uiMapId = C_Map and C_Map.GetBestMapForUnit("player")
    local info = uiMapId and C_Map.GetMapInfo(uiMapId)
    return uiMapId, info
end

function Capture.onZoneChanged()
    if not (ns.ready and Capture.isEnabled(ns.db)) then
        return
    end
    local uiMapId, info = currentMap()
    if not (uiMapId and info) then
        return
    end
    local minLevel, maxLevel = C_Map.GetMapLevels(uiMapId)
    Capture.recordZone(Capture.table(ns.db), uiMapId, info.name, minLevel, maxLevel, time())
end

function Capture.onQuestTurnedIn(questId)
    if not (ns.ready and Capture.isEnabled(ns.db)) then
        return
    end
    local uiMapId = currentMap()
    Capture.recordQuest(Capture.table(ns.db), questId, C_QuestLog.GetTitleForQuestID(questId), uiMapId,
        UnitLevel("player"), UnitFactionGroup("player"), time())
end

ns.Events.register("QUEST_TURNED_IN", Capture.onQuestTurnedIn)
ns.Events.register("ZONE_CHANGED_NEW_AREA", Capture.onZoneChanged)
ns.Events.register("PLAYER_ENTERING_WORLD", Capture.onZoneChanged)
