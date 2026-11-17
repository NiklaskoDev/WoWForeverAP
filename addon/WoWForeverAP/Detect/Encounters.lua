-- Boss kills: ENCOUNTER_END(encounterID, encounterName, difficultyID, groupSize, success) becomes a boss check
-- when the encounter ended in a kill (success == 1) and the seed lists the encounter.
local _, ns = ...

local Encounters = {}
ns.Encounters = Encounters

--- Location id of a boss kill, or nil when the encounter id is outside the id scheme.
function Encounters.locationId(encounterId)
    local ok, locationId = pcall(ns.Ids.locationId, ns.Ids.LocCat.BOSS, encounterId)
    return ok and locationId or nil
end

--- The encounter id when the event reports a kill, nil otherwise. Wrapped in pcall: if the client ever hands
--- over a restricted ("secret") value, comparing it raises instead of answering, and that counts as no kill.
local function killedEncounter(encounterId, success)
    local ok, result = pcall(function()
        return success == 1 and type(encounterId) == "number" and encounterId or nil
    end)
    return ok and result or nil
end

function Encounters.onEnd(encounterId, _, _, _, success)
    local killed = killedEncounter(encounterId, success)
    local locationId = killed and Encounters.locationId(killed)
    if locationId then
        ns.Tracker.recordForPlayer(locationId)
    end
end

ns.Events.tryRegister("ENCOUNTER_END", Encounters.onEnd)
