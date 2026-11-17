-- Area discovery: reads which map-exploration areas the player stands in. Detection of discovery checks is added
-- below the read function; dev capture mode (Capture.lua) shares the read.
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
