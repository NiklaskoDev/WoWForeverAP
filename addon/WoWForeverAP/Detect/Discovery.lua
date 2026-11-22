-- Area discovery: ZONE_CHANGED* and MAP_EXPLORATION_UPDATED become "Discover <area>" checks for the map-exploration
-- areas the player stands in. The zone event fires before the client marks a new area explored, which the
-- exploration event reports afterwards. The read function is shared with dev capture mode (Capture.lua).
local _, ns = ...

local Discovery = {}
ns.Discovery = Discovery

--- Area ids the client reports as explored at the player's position, ascending, plus the map they were read on.
--- Both the map APIs and the exploration API are optional: a missing or failing call gives an empty list.
function Discovery.exploredAreaIds()
    if not (C_Map and C_MapExplorationInfo) then
        return {}
    end
    local uiMapId = ns.tryCall(C_Map.GetBestMapForUnit, "player")
    -- The position (a Vector2D) goes to the exploration call unchanged, as Blizzard's own MapUtil does.
    local position = uiMapId and ns.tryCall(C_Map.GetPlayerMapPosition, uiMapId, "player")
    local answer = position and ns.tryCall(C_MapExplorationInfo.GetExploredAreaIDsAtPosition, uiMapId, position)
    local areaIds = {}
    for _, areaId in ipairs(type(answer) == "table" and answer or {}) do
        if type(areaId) == "number" then
            areaIds[#areaIds + 1] = areaId
        end
    end
    table.sort(areaIds)
    return areaIds, uiMapId
end

--- Location ids of the seed for the explored `areaIds`, in the order given.
function Discovery.milestones(slot, areaIds)
    local found = {}
    for _, areaId in ipairs(areaIds) do
        local ok, locationId = pcall(ns.Ids.locationId, ns.Ids.LocCat.AREA_DISCOVERY, areaId)
        if ok and ns.Inbox.isLocationInSeed(slot, locationId) then
            found[#found + 1] = locationId
        end
    end
    return found
end

--- Records the areas explored at the player's position that the seed lists. Areas explored before linking are
--- counted when the player stands in them again: the client does not say when an area was discovered.
function Discovery.scan()
    local _, _, slot = ns.Tracker.playerContext()
    if not slot then
        return
    end
    for _, locationId in ipairs(Discovery.milestones(slot, (Discovery.exploredAreaIds()))) do
        ns.Tracker.recordForPlayer(locationId)
    end
end

for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
    ns.Events.register(event, Discovery.scan)
end
ns.Events.tryRegister("MAP_EXPLORATION_UPDATED", Discovery.scan)
