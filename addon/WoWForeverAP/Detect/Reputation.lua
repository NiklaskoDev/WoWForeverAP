-- Reputation standings: UPDATE_FACTION becomes a check for every listed standing the character has reached
-- above what it had when it was linked. Standing ids are the client's: 5 Friendly, 6 Honored, 7 Revered, 8 Exalted.
local _, ns = ...

local Reputation = {}
ns.Reputation = Reputation

--- The standing a faction counts as having when no baseline was stored: Neutral, where every faction starts.
Reputation.NEUTRAL = 4

--- Standing of the faction as the client reports it, nil when the API is missing or does not know the faction.
function Reputation.currentStanding(factionId)
    local data = C_Reputation and ns.tryCall(C_Reputation.GetFactionDataByID, factionId)
    return type(data) == "table" and type(data.reaction) == "number" and data.reaction or nil
end

--- Faction id and standing of a reputation location id (native = factionID * 10 + standing).
function Reputation.decode(locationId)
    local category, native = ns.Ids.tryDecode(locationId)
    if category ~= ns.Ids.LocCat.REPUTATION then
        return nil
    end
    return math.floor(native / 10), native % 10
end

local function seedFactionIds(slot)
    local factionIds = {}
    for locationId in pairs(type(slot.locations) == "table" and slot.locations or {}) do
        local factionId = Reputation.decode(locationId)
        if factionId then
            factionIds[factionId] = true
        end
    end
    return factionIds
end

--- Standings of the factions the slot lists, `{ [factionID] = standing }`. A faction the client does not report
--- is left out.
function Reputation.standings(slot)
    local standings = {}
    for factionId in pairs(seedFactionIds(slot)) do
        standings[factionId] = Reputation.currentStanding(factionId)
    end
    return standings
end

--- The link baseline: the standings of `Reputation.standings`, with `false` ("baseline unknown") for a listed
--- faction the client did not report. Nothing is awarded for such a faction until a later read gives its standing,
--- which then becomes its baseline: what the character had before it was linked never counts.
function Reputation.baseline(slot)
    local baseline = {}
    for factionId in pairs(seedFactionIds(slot)) do
        baseline[factionId] = Reputation.currentStanding(factionId) or false
    end
    return baseline
end

--- Location ids of the seed that `current` (`{ [factionID] = standing }`) satisfies: the standing is reached and
--- lies above the baseline (no entry: Neutral; `false`: unknown, nothing is awarded). Ascending, so chat feedback
--- comes in a stable order.
function Reputation.milestones(slot, baseline, current)
    local found = {}
    for locationId in pairs(type(slot.locations) == "table" and slot.locations or {}) do
        local factionId, standing = Reputation.decode(locationId)
        local known = baseline[factionId]
        if factionId and known ~= false and (current[factionId] or 0) >= standing
            and standing > (known or Reputation.NEUTRAL) then
            found[#found + 1] = locationId
        end
    end
    table.sort(found)
    return found
end

function Reputation.scan()
    local character, _, slot = ns.Tracker.playerContext()
    if not slot then
        return
    end
    local baselines = character.baselines or {}
    local current = Reputation.standings(slot)
    local baseline = baselines.rep or {}
    for factionId, known in pairs(baseline) do
        if known == false and current[factionId] then
            baseline[factionId] = current[factionId] -- first successful read: progress so far does not count
        end
    end
    for _, locationId in ipairs(Reputation.milestones(slot, baseline, current)) do
        ns.Tracker.recordForPlayer(locationId)
    end
end

ns.Events.register("UPDATE_FACTION", Reputation.scan)
