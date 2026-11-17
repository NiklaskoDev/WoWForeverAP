-- Honor-system warnings: entering a locked zone, learning a locked profession, training a profession above the
-- unlocked tier. The addon only warns (screen and chat); it never blocks, moves or presses anything.
-- Primary APIs (checked against the 12.x UI source): events ZONE_CHANGED_NEW_AREA, PLAYER_ENTERING_WORLD and
-- SKILL_LINES_CHANGED, C_Map.GetBestMapForUnit and C_Map.GetMapInfo (mapType, parentMapID), Enum.UIMapType.
-- A missing API means no zone warning, never an error.
local _, ns = ...

local Warnings = {}
ns.Warnings = Warnings

local MAX_PARENT_STEPS = 8 -- map trees are three or four levels deep; the cap only guards against a loop

local lastZone
local reported = { learned = {}, rank = {} }

local function walkToZone(mapId)
    local types = Enum and Enum.UIMapType
    if not (C_Map and types) then
        return nil
    end
    for _ = 1, MAX_PARENT_STEPS do
        local info = type(mapId) == "number" and ns.tryCall(C_Map.GetMapInfo, mapId)
        if type(info) ~= "table" then
            return nil
        elseif info.mapType == types.Zone then
            return mapId
        elseif info.mapType ~= types.Micro then
            return nil -- continent, world, dungeon, orphan: not an outdoor zone
        end
        mapId = info.parentMapID
    end
    return nil
end

--- The outdoor zone map the map `mapId` belongs to: itself for a zone, the parent for a micro map (a sub-area),
--- nothing for dungeons, continents and maps the API cannot describe. Restricted values count as "unknown".
function Warnings.zoneOf(mapId)
    local ok, zoneId = pcall(walkToZone, mapId)
    return ok and zoneId or nil
end

--- True when entering `zoneId` (coming from `previousZoneId`) deserves a warning: a locked zone, once per entry.
function Warnings.zoneWarning(slot, zoneId, previousZoneId)
    if zoneId == nil or zoneId == previousZoneId then
        return false
    end
    return ns.Checks.zoneState(slot, zoneId) == "locked"
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

-- The warning one profession earns, or nil. `cap` is Checks.allowedSkill (non-nil: the seed governs the
-- profession), `baseline` the skill it had when the character was linked, `memory` what was reported already.
local function judgeSkill(skillLineId, rank, cap, baseline, memory)
    if cap == 0 and baseline == 0 then
        if rank > 0 and not memory.learned[skillLineId] then
            memory.learned[skillLineId] = true
            return { key = "PROFESSION_LOCKED", skillLineId = skillLineId, rank = rank, allowed = 0 }
        end
        return nil
    end
    local allowed = math.max(cap, baseline)
    if rank > allowed and rank > (memory.rank[skillLineId] or 0) then
        memory.rank[skillLineId] = rank
        return { key = "PROFESSION_ABOVE_CAP", skillLineId = skillLineId, rank = rank, allowed = allowed }
    end
    return nil
end

--- Profession warnings for the current `ranks` ({[skillLineId] = rank}): { { key = locale key, skillLineId, rank,
--- allowed }, ... }. A profession learned while locked warns once; a rank above the unlocked tier warns once per
--- rank. Skill that existed when the character was linked (`skillAtLink`) is never held against it.
--- `memory` ({ learned = {}, rank = {} }) records what was already reported; it is updated.
function Warnings.skillWarnings(slot, skillAtLink, ranks, memory)
    local found = {}
    for _, skillLineId in ipairs(sortedKeys(ranks)) do
        local rank = ranks[skillLineId]
        local cap = ns.Checks.allowedSkill(slot, skillLineId)
        if cap and type(rank) == "number" then
            found[#found + 1] = judgeSkill(skillLineId, rank, cap, skillAtLink[skillLineId] or 0, memory)
        end
    end
    return found
end

local function enabled()
    return ns.db and ns.db.ui and ns.db.ui.zoneWarnings
end

function Warnings.onZoneChanged()
    local mapId = C_Map and ns.tryCall(C_Map.GetBestMapForUnit, "player")
    local zoneId = Warnings.zoneOf(mapId)
    local previous = lastZone
    lastZone = zoneId
    if not (ns.ready and enabled()) then
        return
    end
    local _, _, slot = ns.Tracker.playerContext()
    if slot and Warnings.zoneWarning(slot, zoneId, previous) then
        ns.Notify.alert(ns.L.ZONE_LOCKED:format(ns.Names.zone(zoneId)))
    end
end

function Warnings.onSkillLinesChanged()
    if not (ns.ready and enabled()) then
        return
    end
    local character, _, slot = ns.Tracker.playerContext()
    local ranks = slot and ns.Professions.currentRanks()
    if not ranks then
        return
    end
    for _, warning in ipairs(Warnings.skillWarnings(slot, character.skillAtLink or {}, ranks, reported)) do
        local name = ns.Names.profession(warning.skillLineId)
        if warning.key == "PROFESSION_LOCKED" then
            ns.Notify.alert(ns.L.PROFESSION_LOCKED:format(name))
        else
            ns.Notify.alert(ns.L.PROFESSION_ABOVE_CAP:format(name, warning.rank, warning.allowed))
        end
    end
end

--- Forgets which zone the player was in and which warnings were shown (a new session, or a spec).
function Warnings.reset()
    lastZone = nil
    reported = { learned = {}, rank = {} }
end

--- Registers the events; returns the names that registered (a client that refuses one just skips it).
function Warnings.register()
    local wanted = {
        { "ZONE_CHANGED_NEW_AREA", Warnings.onZoneChanged },
        { "PLAYER_ENTERING_WORLD", Warnings.onZoneChanged },
        { "SKILL_LINES_CHANGED", Warnings.onSkillLinesChanged },
    }
    local registered = {}
    for _, entry in ipairs(wanted) do
        if pcall(ns.Events.register, entry[1], entry[2]) then
            registered[#registered + 1] = entry[1]
        end
    end
    return registered
end

Warnings.register()
