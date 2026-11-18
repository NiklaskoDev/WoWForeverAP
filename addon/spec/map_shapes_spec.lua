local Env = require("helpers.addon_env")

describe("MapShapes", function()
    local ns, Shapes
    local CONTINENT, ELWYNN, DUROTAR, CITY = 1415, 1429, 1411, 1453
    local COLUMNS, ROWS

    local calls

    --- Fake zone lookup: the first row is a city, the last row the continent itself, the rest is Elwynn on the left
    --- half and Durotar on the right half.
    local function installLookup(overrides)
        calls = { info = 0, highlight = {} }
        _G.C_Map = {
            GetMapInfoAtPosition = function(mapId, x, y)
                calls.info = calls.info + 1
                assert.equals(CONTINENT, mapId)
                if y < 1 / ROWS then return { mapID = CITY } end
                if y > (ROWS - 1) / ROWS then return { mapID = CONTINENT } end
                return { mapID = x < 0.5 and ELWYNN or DUROTAR }
            end,
            GetMapHighlightInfoAtPosition = function(mapId, x, y)
                calls.highlight[#calls.highlight + 1] = { mapId, x, y }
                return nil
            end,
        }
        for key, value in pairs(overrides or {}) do _G.C_Map[key] = value end
    end

    before_each(function()
        ns = Env.new()
        Shapes = ns.MapShapes
        COLUMNS, ROWS = Shapes.COLUMNS, Shapes.ROWS
        installLookup()
    end)

    describe("sampleRuns", function()
        it("gives one run per row and zone over the whole half, and none for cities or the continent", function()
            local runs = Shapes.sampleRuns(CONTINENT)
            local ids = {}
            for id in pairs(runs) do ids[#ids + 1] = id end
            table.sort(ids)
            assert.same({ DUROTAR, ELWYNN }, ids)
            assert.equals(ROWS - 2, #runs[ELWYNN])
            assert.same({ 2, 1, COLUMNS / 2 }, runs[ELWYNN][1])
            assert.same({ ROWS - 1, 1, COLUMNS / 2 }, runs[ELWYNN][ROWS - 2])
            assert.same({ 2, COLUMNS / 2 + 1, COLUMNS }, runs[DUROTAR][1])
        end)

        it("splits a row where the zone leaves and comes back", function()
            _G.C_Map.GetMapInfoAtPosition = function(_, x)
                local gap = x > 0.3 and x < 0.4
                return { mapID = gap and CITY or ELWYNN }
            end
            local runs = Shapes.sampleRuns(CONTINENT)
            assert.same({ 1, 1, 48 }, runs[ELWYNN][1])
            assert.same({ 1, 65, COLUMNS }, runs[ELWYNN][2])
        end)

        it("is empty without the API", function()
            _G.C_Map = nil
            assert.same({}, Shapes.sampleRuns(CONTINENT))
            _G.C_Map = {}
            assert.same({}, Shapes.sampleRuns(CONTINENT))
        end)

        it("stops after the first call when the API errors", function()
            local count = 0
            _G.C_Map.GetMapInfoAtPosition = function()
                count = count + 1
                error("restricted")
            end
            assert.same({}, Shapes.sampleRuns(CONTINENT))
            assert.equals(1, count)
        end)

        it("ignores answers that are not a map info", function()
            _G.C_Map.GetMapInfoAtPosition = function() return nil end
            assert.same({}, Shapes.sampleRuns(CONTINENT))
            _G.C_Map.GetMapInfoAtPosition = function() return { mapID = "x" } end
            assert.same({}, Shapes.sampleRuns(CONTINENT))
        end)
    end)

    describe("highlightArt", function()
        local function stubArt(...)
            local values = { ... }
            _G.C_Map.GetMapHighlightInfoAtPosition = function() return unpack(values, 1, 8) end
        end

        it("is nil when the game gives nothing, or a zero file without an atlas", function()
            assert.is_nil(Shapes.highlightArt(CONTINENT, 0.5, 0.5))
            stubArt(0, nil, 1, 1, 0.1, 0.1, 0.2, 0.2)
            assert.is_nil(Shapes.highlightArt(CONTINENT, 0.5, 0.5))
            _G.C_Map = nil
            assert.is_nil(Shapes.highlightArt(CONTINENT, 0.5, 0.5))
        end)

        it("is nil when the API errors or a value is missing", function()
            _G.C_Map.GetMapHighlightInfoAtPosition = function() error("restricted") end
            assert.is_nil(Shapes.highlightArt(CONTINENT, 0.5, 0.5))
            stubArt(123, nil, 1, 1, 0.1, 0.1, 0.2)
            assert.is_nil(Shapes.highlightArt(CONTINENT, 0.5, 0.5))
        end)

        it("maps a file texture as returned", function()
            stubArt(123, nil, 0.75, 0.5, 0.1, 0.2, 0.3, 0.4)
            assert.same({ file = 123, texRight = 0.75, texBottom = 0.5, width = 0.1, height = 0.2, left = 0.3,
                top = 0.4 }, Shapes.highlightArt(CONTINENT, 0.5, 0.5))
        end)

        it("maps an atlas as returned", function()
            stubArt(0, "MapHighlight-Elwynn", 1, 1, 0.1, 0.2, 0.3, 0.4)
            assert.same({ atlas = "MapHighlight-Elwynn", texRight = 1, texBottom = 1, width = 0.1, height = 0.2,
                left = 0.3, top = 0.4 }, Shapes.highlightArt(CONTINENT, 0.5, 0.5))
        end)
    end)

    describe("forContinent", function()
        it("gives every zone its runs and the art at the middle of its longest run", function()
            -- Elwynn is narrow on the upper half of the map and wide on the lower half
            _G.C_Map.GetMapInfoAtPosition = function(_, x, y)
                local edge = y < 0.5 and 0.25 or 0.5
                return { mapID = x < edge and ELWYNN or DUROTAR }
            end
            _G.C_Map.GetMapHighlightInfoAtPosition = function(mapId, x, y)
                calls.highlight[#calls.highlight + 1] = { mapId, x, y }
                return 0, "atlas-" .. (x < 0.5 and "left" or "right"), 1, 1, 0.1, 0.1, 0, 0
            end
            local zones = Shapes.forContinent(CONTINENT)
            assert.equals(ROWS, #zones[ELWYNN].runs)
            assert.equals("atlas-left", zones[ELWYNN].art.atlas)
            assert.equals("atlas-right", zones[DUROTAR].art.atlas)
            local elwynnProbe
            for _, call in ipairs(calls.highlight) do
                if call[2] < 0.5 then elwynnProbe = call end
            end
            -- the longest Elwynn run is the first full-width one, columns 1-80 of row 54
            assert.equals(CONTINENT, elwynnProbe[1])
            assert.is_true(math.abs(elwynnProbe[2] - 0.25) < 1e-9)
            assert.is_true(math.abs(elwynnProbe[3] - 53.5 / ROWS) < 1e-9)
        end)

        it("leaves art nil for a zone the game has no art for", function()
            local zones = Shapes.forContinent(CONTINENT)
            assert.is_nil(zones[ELWYNN].art)
            assert.is_not_nil(zones[ELWYNN].runs)
        end)

        it("samples once per continent and session", function()
            Shapes.forContinent(CONTINENT)
            local after = calls.info
            assert.is_true(after > 0)
            Shapes.forContinent(CONTINENT)
            assert.equals(after, calls.info)
            assert.equals(2, #calls.highlight)
            Shapes.reset()
            Shapes.forContinent(CONTINENT)
            assert.equals(after * 2, calls.info)
        end)

        it("does not keep an empty result, so the next open tries again", function()
            _G.C_Map = nil
            assert.same({}, Shapes.forContinent(CONTINENT))
            installLookup()
            assert.is_not_nil(Shapes.forContinent(CONTINENT)[ELWYNN])
        end)
    end)

    describe("zoneAt", function()
        local function lookup(info)
            _G.C_Map.GetMapInfoAtPosition = function() return info end
        end

        it("gives the data zone under the point", function()
            assert.equals(ELWYNN, Shapes.zoneAt(CONTINENT, 0.2, 0.5))
            assert.equals(DUROTAR, Shapes.zoneAt(CONTINENT, 0.8, 0.5))
        end)

        it("gives nil for a city, the continent itself, no info or an API error", function()
            assert.is_nil(Shapes.zoneAt(CONTINENT, 0.2, 0))
            assert.is_nil(Shapes.zoneAt(CONTINENT, 0.2, 1))
            lookup(nil)
            assert.is_nil(Shapes.zoneAt(CONTINENT, 0.2, 0.5))
            _G.C_Map.GetMapInfoAtPosition = function() error("restricted") end
            assert.is_nil(Shapes.zoneAt(CONTINENT, 0.2, 0.5))
            _G.C_Map = nil
            assert.is_nil(Shapes.zoneAt(CONTINENT, 0.2, 0.5))
        end)
    end)
end)
