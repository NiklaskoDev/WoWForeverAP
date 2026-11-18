-- What the honor-system rules say about the linked slot: the lock state of a zone, the profession skill cap,
-- and the checks still open. Pure: every function takes the inbox slot (and the outbox set), no game API.
local _, ns = ...

local Checks = {}
ns.Checks = Checks

--- Display order of the zone states: where the player may play first, then what is locked or not in the seed.
Checks.STATE_RANK = { start = 1, unlocked = 2, locked = 3, unavailable = 4 }

--- Group id for open quests the addon data cannot place in a zone (an addon older than the apworld).
Checks.UNKNOWN_ZONE = 0

local UNKNOWN_ZONE_RANK = 5

local function releaseOf(slot)
    local release = ns.Inbox.options(slot).contentRelease
    return type(release) == "number" and release or nil
end

--- "start", "unlocked", "locked" or "unavailable" (another faction, a later content release, or a zone that starts
--- above the goal level) for a zone;
--- nil for a map the data does not list (cities, dungeons, zones Forever added after the data was made).
function Checks.zoneState(slot, uiMapId)
    local zone = ns.Data.zones[uiMapId]
    if not zone then
        return nil
    end
    local options = ns.Inbox.options(slot)
    if options.startZone == uiMapId then
        return "start"
    end
    local release = releaseOf(slot)
    local otherFaction = zone.faction ~= "both" and not ns.Link.factionMatches(zone.faction, options.faction)
    if otherFaction or (release and zone.release > release) then
        return "unavailable"
    end
    local goal = options.goalLevel
    if type(goal) == "number" and zone.min > goal then
        return "unavailable" -- no item will ever unlock it: the seed leaves the zone out
    end
    if ns.Inbox.hasItem(slot, ns.Ids.itemId(ns.Ids.ItemCat.ZONE, uiMapId)) then
        return "unlocked"
    end
    return "locked"
end

--- True when the slot's seed includes the profession (its tiers are items, its skills are checks).
function Checks.professionInSeed(slot, skillLineId)
    for _, id in ipairs(ns.Inbox.options(slot).professions or {}) do
        if id == skillLineId then
            return true
        end
    end
    return false
end

local function allowedTiers(slot)
    local release = releaseOf(slot)
    local tiers = {}
    for _, tier in ipairs(ns.Data.tiers) do
        if not release or tier.release <= release then
            tiers[#tiers + 1] = tier
        end
    end
    return tiers
end

--- Highest skill the slot may train in a profession: 0 while no tier item arrived (profession locked),
--- else the `maxSkill` of the highest unlocked tier. nil when the seed does not include the profession.
function Checks.allowedSkill(slot, skillLineId)
    if not Checks.professionInSeed(slot, skillLineId) then
        return nil
    end
    local tierItem = ns.Ids.itemId(ns.Ids.ItemCat.PROFESSION_TIER, skillLineId)
    local tiers = allowedTiers(slot)
    local tier = tiers[math.min(ns.Inbox.countItem(slot, tierItem), #tiers)]
    return tier and tier.maxSkill or 0
end

--- Open locations of the slot as { category, native } pairs: in the seed, not checked by the server and not
--- waiting in the outbox (`pending` is a set of location ids, may be nil).
local function openLocations(slot, pending)
    local open = {}
    for locationId in pairs(type(slot.locations) == "table" and slot.locations or {}) do
        local waiting = pending and pending[locationId]
        if not ns.Inbox.isChecked(slot, locationId) and not waiting then
            local category, native = ns.Ids.tryDecode(locationId)
            if category then
                open[#open + 1] = { category = category, native = native }
            end
        end
    end
    return open
end

local function zoneRank(state)
    return Checks.STATE_RANK[state] or UNKNOWN_ZONE_RANK
end

local function zoneOrder(a, b)
    if zoneRank(a.state) ~= zoneRank(b.state) then
        return zoneRank(a.state) < zoneRank(b.state)
    end
    local zoneA, zoneB = ns.Data.zones[a.uiMapId], ns.Data.zones[b.uiMapId]
    local levelA, levelB = zoneA and zoneA.min or 0, zoneB and zoneB.min or 0
    if levelA ~= levelB then
        return levelA < levelB
    end
    return a.uiMapId < b.uiMapId
end

local function zoneGroup(byZone, slot, uiMapId)
    local group = byZone[uiMapId]
    if not group then
        group = { uiMapId = uiMapId, state = Checks.zoneState(slot, uiMapId), quests = {}, bosses = {}, areas = {} }
        byZone[uiMapId] = group
    end
    return group
end

--- The zone a boss or area check belongs to (`Checks.UNKNOWN_ZONE` when the addon data does not list it).
local function placeOf(dataTable, native)
    local entry = dataTable[native]
    return entry and entry.zone or Checks.UNKNOWN_ZONE
end

--- How many open checks a zone group holds.
function Checks.openCount(group)
    return #group.quests + #group.bosses + #group.areas
end

--- Open quest, boss and area checks grouped by zone: { { uiMapId, state, quests = { questId, ... },
--- bosses = { encounterId, ... }, areas = { areaId, ... } }, ... }, the zones the player may play first. Checks
--- the data cannot place go to the last group (uiMapId `Checks.UNKNOWN_ZONE`, state nil).
function Checks.openByZone(slot, pending)
    local byZone = {}
    local LocCat = ns.Ids.LocCat
    for _, location in ipairs(openLocations(slot, pending)) do
        if location.category == LocCat.QUEST then
            local group = zoneGroup(byZone, slot, ns.Data.quests[location.native] or Checks.UNKNOWN_ZONE)
            group.quests[#group.quests + 1] = location.native
        elseif location.category == LocCat.BOSS then
            local group = zoneGroup(byZone, slot, placeOf(ns.Data.bosses, location.native))
            group.bosses[#group.bosses + 1] = location.native
        elseif location.category == LocCat.AREA_DISCOVERY then
            local group = zoneGroup(byZone, slot, placeOf(ns.Data.areas, location.native))
            group.areas[#group.areas + 1] = location.native
        end
    end
    local groups = {}
    for _, group in pairs(byZone) do
        table.sort(group.quests)
        table.sort(group.bosses)
        table.sort(group.areas)
        groups[#groups + 1] = group
    end
    table.sort(groups, zoneOrder)
    return groups
end

--- Open character checks: { levels = { level, ... }, professions = { [skillLineId] = { skill, ... } },
--- reputations = { [factionId] = { standing, ... } }, pvp = { pvpId, ... } }, every list ascending.
function Checks.openCharacter(slot, pending)
    local result = { levels = {}, professions = {}, reputations = {}, pvp = {} }
    for _, location in ipairs(openLocations(slot, pending)) do
        if location.category == ns.Ids.LocCat.LEVEL then
            result.levels[#result.levels + 1] = location.native
        elseif location.category == ns.Ids.LocCat.PROFESSION_SKILL then
            local factor = ns.Ids.PROFESSION_SKILL_FACTOR
            local skillLineId = math.floor(location.native / factor)
            local skills = result.professions[skillLineId] or {}
            result.professions[skillLineId] = skills
            skills[#skills + 1] = location.native % factor
        elseif location.category == ns.Ids.LocCat.REPUTATION then
            local factionId = math.floor(location.native / 10)
            local standings = result.reputations[factionId] or {}
            result.reputations[factionId] = standings
            standings[#standings + 1] = location.native % 10
        elseif location.category == ns.Ids.LocCat.PVP then
            result.pvp[#result.pvp + 1] = location.native
        end
    end
    table.sort(result.levels)
    table.sort(result.pvp)
    for _, skills in pairs(result.professions) do
        table.sort(skills)
    end
    for _, standings in pairs(result.reputations) do
        table.sort(standings)
    end
    return result
end
