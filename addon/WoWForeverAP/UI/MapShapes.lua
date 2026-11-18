-- Zone shapes on a continent map (plans 010, 013): which zone covers which part of the map, read from the game's own
-- map API as strips and cached per continent for the session. MapOverlay draws them and drives the sampling.
-- APIs (checked against the 12.1.5 UI source): C_Map.GetMapInfoAtPosition(mapID, x, y) -> UiMapDetails, the zone
-- lookup Blizzard's area label uses (it may return nothing); debugprofilestop() -> elapsed milliseconds
-- (FrameScriptDocumentation.lua), only ever used as a difference between two calls, never debugprofilestart, which
-- would reset other addons' profiling. Whatever is missing or fails gives no result and the map stays as it is.
local _, ns = ...

local MapShapes = {}
ns.MapShapes = MapShapes

-- Continent canvases are about 3:2; a cell is about 0.2 % of the map, which is the resolution of the strips.
MapShapes.COLUMNS = 480
MapShapes.ROWS = 321
-- Time one step may spend sampling (a step ends after the row that crosses it), so a frame is never hogged.
MapShapes.FRAME_BUDGET_MS = 4
-- Rows per step when there is no usable clock.
MapShapes.FALLBACK_ROWS_PER_STEP = 4

local cache = {} -- [continentMapId] = { [uiMapId] = { runs = { { row, first, last }, ... } } }
local jobs = {} -- [continentMapId] = { nextRow, runs = { [uiMapId] = runs }, started }

--- The data zone (not the continent itself) of a map info table, or nil.
local function dataZoneId(info, continentMapId)
    local uiMapId = type(info) == "table" and info.mapID
    if type(uiMapId) == "number" and uiMapId ~= continentMapId and ns.Data.zones[uiMapId] then
        return uiMapId
    end
    return nil
end

--- Milliseconds from the game's profiling clock, or nil when it is missing or gives no number.
local function clock()
    if type(debugprofilestop) ~= "function" then
        return nil
    end
    local now = debugprofilestop()
    return type(now) == "number" and now or nil
end

--- Samples the next row of a job into job.runs: one run per stretch of consecutive cells of one zone. False when
--- the very first call of the job errors (the API is not usable), true otherwise; a later error leaves its cell empty.
local function sampleRow(continentMapId, job)
    local columns, row = MapShapes.COLUMNS, job.nextRow
    local y = (row - 0.5) / MapShapes.ROWS
    local current, start
    for col = 1, columns + 1 do
        local zoneId
        if col <= columns then
            -- pcall rather than ns.tryCall: an error on the first call must stop the whole sampling
            local ok, info = pcall(C_Map.GetMapInfoAtPosition, continentMapId, (col - 0.5) / columns, y)
            if not ok and not job.started then
                return false
            end
            job.started = true
            zoneId = ok and dataZoneId(info, continentMapId) or nil
        end
        if zoneId ~= current then
            if current then
                local list = job.runs[current] or {}
                job.runs[current] = list
                list[#list + 1] = { row, start, col - 1 }
            end
            current, start = zoneId, col
        end
    end
    job.nextRow = row + 1
    return true
end

--- The finished partition of a continent: { [uiMapId] = { runs = { { row, first, last }, ... } } }, or nil when it
--- is not (yet) sampled. A continent without data zones is finished with {}.
function MapShapes.cached(continentMapId)
    return cache[continentMapId]
end

--- Samples rows of a continent map until `budgetMs` milliseconds have passed (at least one row per call; without a
--- budget, to the end). Progress is kept between calls, also across other continents. Returns "done" (the result is
--- cached), "pending" (call again) or "failed" (the API is missing or errors; nothing is kept, the next call starts
--- again).
function MapShapes.step(continentMapId, budgetMs)
    if cache[continentMapId] then
        return "done"
    end
    if not (C_Map and type(C_Map.GetMapInfoAtPosition) == "function") then
        jobs[continentMapId] = nil
        return "failed"
    end
    local job = jobs[continentMapId] or { nextRow = 1, runs = {}, started = false }
    jobs[continentMapId] = job
    local start = budgetMs and clock()
    local rowsThisStep = 0
    while true do
        if not sampleRow(continentMapId, job) then
            jobs[continentMapId] = nil
            return "failed"
        end
        rowsThisStep = rowsThisStep + 1
        if job.nextRow > MapShapes.ROWS then
            local zones = {}
            for uiMapId, runs in pairs(job.runs) do
                zones[uiMapId] = { runs = runs }
            end
            cache[continentMapId] = zones
            jobs[continentMapId] = nil
            return "done"
        end
        if budgetMs then
            local now = start and clock()
            local spentUp
            if now then
                spentUp = now - start >= budgetMs
            else -- no usable clock, at the start or later
                spentUp = rowsThisStep >= MapShapes.FALLBACK_ROWS_PER_STEP
            end
            if spentUp then
                return "pending"
            end
        end
    end
end

--- The data zone under the point (x, y) of a continent map, or nil.
function MapShapes.zoneAt(continentMapId, x, y)
    local info = C_Map and ns.tryCall(C_Map.GetMapInfoAtPosition, continentMapId, x, y)
    return dataZoneId(info, continentMapId)
end

--- Forgets the cached shapes and running jobs (specs).
function MapShapes.reset()
    cache, jobs = {}, {}
end
