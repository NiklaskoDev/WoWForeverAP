-- Zone shapes on a continent map (plan 010): which zone covers which part of the map, and the zone's highlight art,
-- both read from the game's own map API and cached per continent for the session. MapOverlay draws them.
-- APIs (checked against the 12.1.5 UI source): C_Map.GetMapInfoAtPosition(mapID, x, y) -> UiMapDetails, the zone
-- lookup Blizzard's area label uses; C_Map.GetMapHighlightInfoAtPosition(mapID, x, y) -> fileDataID, atlasID,
-- texPercentageX, texPercentageY, textureX, textureY, scrollChildX, scrollChildY, the zone hover art of the map.
-- Both may return nothing. Whatever is missing or fails gives an empty result and the map stays as it is.
local _, ns = ...

local MapShapes = {}
ns.MapShapes = MapShapes

-- Continent canvases are about 3:2; a cell is about 0.6 % of the map, which is the resolution of the fallback strips.
MapShapes.COLUMNS = 160
MapShapes.ROWS = 107

local cache = {}

--- The data zone (not the continent itself) of a map info table, or nil.
local function dataZoneId(info, continentMapId)
    local uiMapId = type(info) == "table" and info.mapID
    if type(uiMapId) == "number" and uiMapId ~= continentMapId and ns.Data.zones[uiMapId] then
        return uiMapId
    end
    return nil
end

--- The zone partition of a continent map: { [uiMapId] = { { row, first, last }, ... } }, one run per stretch of
--- consecutive cells of one row that belong to the zone. Empty when the API is missing or fails on the first call;
--- the second result tells a finished sampling (true, even with no zones) from that case (false).
function MapShapes.sampleRuns(continentMapId)
    local runs = {}
    if not (C_Map and type(C_Map.GetMapInfoAtPosition) == "function") then
        return runs, false
    end
    local columns, rows = MapShapes.COLUMNS, MapShapes.ROWS
    local firstCall = true
    for row = 1, rows do
        local y = (row - 0.5) / rows
        local current, start
        for col = 1, columns + 1 do
            local zoneId
            if col <= columns then
                -- pcall rather than ns.tryCall: an error on the first call must stop the whole sampling
                local ok, info = pcall(C_Map.GetMapInfoAtPosition, continentMapId, (col - 0.5) / columns, y)
                if not ok and firstCall then
                    return {}, false
                end
                firstCall = false
                zoneId = ok and dataZoneId(info, continentMapId) or nil
            end
            if zoneId ~= current then
                if current then
                    local list = runs[current] or {}
                    runs[current] = list
                    list[#list + 1] = { row, start, col - 1 }
                end
                current, start = zoneId, col
            end
        end
    end
    return runs, true
end

--- The hover art of the zone at (x, y) on the map: { file | atlas, texRight, texBottom, width, height, left, top }
--- with the values as the game returns them (normalised to the canvas), or nil when there is none.
function MapShapes.highlightArt(continentMapId, x, y)
    if not C_Map then
        return nil
    end
    local file, atlas, texRight, texBottom, width, height, left, top =
        ns.tryCall(C_Map.GetMapHighlightInfoAtPosition, continentMapId, x, y)
    local hasFile = type(file) == "number" and file > 0
    local hasAtlas = type(atlas) == "string" and atlas ~= ""
    if not (hasFile or hasAtlas) then
        return nil
    end
    local numbers = { texRight, texBottom, width, height, left, top }
    for index = 1, 6 do -- not ipairs: a missing value is a hole in the list
        if type(numbers[index]) ~= "number" then
            return nil
        end
    end
    return {
        file = hasFile and file or nil, atlas = hasAtlas and atlas or nil, texRight = texRight,
        texBottom = texBottom, width = width, height = height, left = left, top = top,
    }
end

--- The middle of the longest run of a zone, normalised: always a point inside the zone.
local function probePoint(runs)
    local longest = runs[1]
    for _, run in ipairs(runs) do
        if run[3] - run[2] > longest[3] - longest[2] then
            longest = run
        end
    end
    return (longest[2] + longest[3] - 1) / 2 / MapShapes.COLUMNS, (longest[1] - 0.5) / MapShapes.ROWS
end

--- Every data zone on a continent map: { [uiMapId] = { runs = { { row, first, last }, ... }, art = art | nil } }.
--- Sampled once per continent and session. An empty result is kept too when the API worked (a continent without
--- data zones), and not kept when it is missing or failed, so the next call tries again.
function MapShapes.forContinent(continentMapId)
    local cached = cache[continentMapId]
    if cached then
        return cached
    end
    local zones = {}
    local sampled, completed = MapShapes.sampleRuns(continentMapId)
    for uiMapId, runs in pairs(sampled) do
        local x, y = probePoint(runs)
        zones[uiMapId] = { runs = runs, art = MapShapes.highlightArt(continentMapId, x, y) }
    end
    if completed then
        cache[continentMapId] = zones
    end
    return zones
end

--- The data zone under the point (x, y) of a continent map, or nil.
function MapShapes.zoneAt(continentMapId, x, y)
    local info = C_Map and ns.tryCall(C_Map.GetMapInfoAtPosition, continentMapId, x, y)
    return dataZoneId(info, continentMapId)
end

--- Forgets the cached shapes (specs).
function MapShapes.reset()
    cache = {}
end
