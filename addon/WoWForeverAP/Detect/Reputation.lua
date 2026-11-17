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

--- Standings of the factions the slot lists, `{ [factionID] = standing }`, as the link baseline. A faction the
--- client does not report is left out (it counts as Neutral later).
function Reputation.standings(slot)
    local standings = {}
    for locationId in pairs(type(slot.locations) == "table" and slot.locations or {}) do
        local factionId = Reputation.decode(locationId)
        if factionId and standings[factionId] == nil then
            standings[factionId] = Reputation.currentStanding(factionId)
        end
    end
    return standings
end

--- Location ids of the seed that `current` (`{ [factionID] = standing }`) satisfies: the standing is reached and
--- lies above the baseline. Ascending, so chat feedback comes in a stable order.
function Reputation.milestones(slot, baseline, current)
    local found = {}
    for locationId in pairs(type(slot.locations) == "table" and slot.locations or {}) do
        local factionId, standing = Reputation.decode(locationId)
        if factionId and (current[factionId] or 0) >= standing
            and standing > (baseline[factionId] or Reputation.NEUTRAL) then
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
    for _, locationId in ipairs(Reputation.milestones(slot, baselines.rep or {}, Reputation.standings(slot))) do
        ns.Tracker.recordForPlayer(locationId)
    end
end

ns.Events.register("UPDATE_FACTION", Reputation.scan)
