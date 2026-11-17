-- Quest turn-ins: QUEST_TURNED_IN(questID) becomes a quest location check.
local _, ns = ...

local Quests = {}
ns.Quests = Quests

--- Location id of a quest turn-in, or nil when the quest id is outside the id scheme.
function Quests.locationId(questId)
    local ok, locationId = pcall(ns.Ids.locationId, ns.Ids.LocCat.QUEST, questId)
    return ok and locationId or nil
end

function Quests.onTurnedIn(questId)
    local locationId = Quests.locationId(questId)
    if locationId then
        ns.Tracker.recordForPlayer(locationId)
    end
end

ns.Events.register("QUEST_TURNED_IN", Quests.onTurnedIn)
