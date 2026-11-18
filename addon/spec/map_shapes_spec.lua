local Env = require("helpers.addon_env")

describe("MapShapes", function()
    local ns, Shapes
    local CONTINENT, ELWYNN, DUROTAR, CITY = 1415, 1429, 1411, 1453
    local COLUMNS, ROWS
    local defaultColumns, defaultRows

    local calls

    --- Fake zone lookup: the first row is a city, the last row the continent itself, the rest is Elwynn on the left
    --- half and Durotar on the right half.
    local function installLookup(overrides)
        calls = { info = 0 }
        _G.C_Map = {
            GetMapInfoAtPosition = function(mapId, x, y)
                calls.info = calls.info + 1
                assert.equals(CONTINENT, mapId)
                if y < 1 / ROWS then return { mapID = CITY } end
                if y > (ROWS - 1) / ROWS then return { mapID = CONTINENT } end
                return { mapID = x < 0.5 and ELWYNN or DUROTAR }
            end,
        }
        for key, value in pairs(overrides or {}) do _G.C_Map[key] = value end
    end

    after_each(function()
        _G.debugprofilestop = nil
    end)

    before_each(function()
        ns = Env.new()
        Shapes = ns.MapShapes
        -- a small grid keeps the specs fast (the sampling is the same on any size); the cases that pin the real
        -- grid call useFullGrid()
        defaultColumns, defaultRows = Shapes.COLUMNS, Shapes.ROWS
        Shapes.COLUMNS, Shapes.ROWS = 40, 24
        COLUMNS, ROWS = Shapes.COLUMNS, Shapes.ROWS
        installLookup()
    end)

    local function useFullGrid()
        Shapes.COLUMNS, Shapes.ROWS = defaultColumns, defaultRows
        COLUMNS, ROWS = Shapes.COLUMNS, Shapes.ROWS
    end

    --- The fake clock: every call to debugprofilestop() returns the next multiple of `stepMs`.
    local function installClock(stepMs)
        local now = 0
        _G.debugprofilestop = function()
            now = now + stepMs
            return now
        end
    end

    --- Steps a continent to the end with the budget; the number of calls that returned "pending".
    local function stepToDone(id, budgetMs)
        local pending = 0
        for _ = 1, 100000 do
            local status = Shapes.step(id, budgetMs)
            if status == "done" then return pending end
            assert.equals("pending", status)
            pending = pending + 1
        end
        error("never finished")
    end

    it("samples a 480 x 321 grid", function()
        assert.equals(480, defaultColumns)
        assert.equals(321, defaultRows)
        assert.equals(4, Shapes.FRAME_BUDGET_MS)
        assert.equals(4, Shapes.FALLBACK_ROWS_PER_STEP)
    end)

    describe("step without a budget", function()
        it("finishes at once and gives one run per row and zone over the whole half, none for cities or the continent",
            function()
                useFullGrid()
                assert.is_nil(Shapes.cached(CONTINENT))
                assert.equals("done", Shapes.step(CONTINENT))
                local runs = Shapes.cached(CONTINENT)
                local ids = {}
                for id in pairs(runs) do ids[#ids + 1] = id end
                table.sort(ids)
                assert.same({ DUROTAR, ELWYNN }, ids)
                assert.equals(ROWS - 2, #runs[ELWYNN].runs)
                assert.same({ 2, 1, COLUMNS / 2 }, runs[ELWYNN].runs[1])
                assert.same({ ROWS - 1, 1, COLUMNS / 2 }, runs[ELWYNN].runs[ROWS - 2])
                assert.same({ 2, COLUMNS / 2 + 1, COLUMNS }, runs[DUROTAR].runs[1])
                assert.equals(COLUMNS * ROWS, calls.info)
            end)

        it("splits a row where the zone leaves and comes back", function()
            useFullGrid()
            _G.C_Map.GetMapInfoAtPosition = function(_, x)
                local gap = x > 0.3 and x < 0.4
                return { mapID = gap and CITY or ELWYNN }
            end
            Shapes.step(CONTINENT)
            local runs = Shapes.cached(CONTINENT)[ELWYNN].runs
            -- columns 1-144 (x up to 0.3), a gap, then 193-480 (x from 0.4)
            assert.same({ 1, 1, 144 }, runs[1])
            assert.same({ 1, 193, COLUMNS }, runs[2])
        end)

        it("ignores answers that are not a map info", function()
            _G.C_Map.GetMapInfoAtPosition = function() return nil end
            assert.equals("done", Shapes.step(CONTINENT))
            assert.same({}, Shapes.cached(CONTINENT))
            Shapes.reset()
            _G.C_Map.GetMapInfoAtPosition = function() return { mapID = "x" } end
            assert.equals("done", Shapes.step(CONTINENT))
            assert.same({}, Shapes.cached(CONTINENT))
        end)
    end)

    describe("step with a time budget", function()
        it("stops after the row that crosses the budget and gives the same result as a synchronous run", function()
            installClock(1) -- 1 ms per clock call: the start and one check per row
            assert.equals("pending", Shapes.step(CONTINENT, 4))
            -- start = 1; checks after rows 1, 2, 3, 4 read 2, 3, 4, 5; 5 - 1 >= 4 after the 4th row
            assert.equals(4 * COLUMNS, calls.info)
            assert.is_nil(Shapes.cached(CONTINENT))
            stepToDone(CONTINENT, 4)
            local sliced = Shapes.cached(CONTINENT)
            Shapes.reset()
            assert.equals("done", Shapes.step(CONTINENT))
            assert.same(Shapes.cached(CONTINENT), sliced)
        end)

        it("samples at least one row per call even when the budget is already spent", function()
            installClock(100)
            assert.equals("pending", Shapes.step(CONTINENT, 4))
            assert.equals(COLUMNS, calls.info)
            assert.equals("pending", Shapes.step(CONTINENT, 0))
            assert.equals(2 * COLUMNS, calls.info)
        end)

        it("needs about ROWS / rows-per-step calls and finishes in the call that samples the last row", function()
            installClock(1)
            assert.equals(math.ceil(ROWS / 4) - 1, stepToDone(CONTINENT, 4))
        end)

        it("samples FALLBACK_ROWS_PER_STEP rows per call without a clock", function()
            assert.is_nil(_G.debugprofilestop)
            assert.equals("pending", Shapes.step(CONTINENT, 4))
            assert.equals(Shapes.FALLBACK_ROWS_PER_STEP * COLUMNS, calls.info)
            assert.equals("pending", Shapes.step(CONTINENT, 4))
            assert.equals(2 * Shapes.FALLBACK_ROWS_PER_STEP * COLUMNS, calls.info)
        end)

        it("uses the fallback when the clock gives no number", function()
            _G.debugprofilestop = function() return "soon" end
            assert.equals("pending", Shapes.step(CONTINENT, 4))
            assert.equals(Shapes.FALLBACK_ROWS_PER_STEP * COLUMNS, calls.info)
        end)

        it("switches to the fallback when the clock stops giving numbers in the middle of a step", function()
            local count = 0
            _G.debugprofilestop = function()
                count = count + 1
                return count == 1 and 0 or nil
            end
            assert.equals("pending", Shapes.step(CONTINENT, 4))
            assert.equals(Shapes.FALLBACK_ROWS_PER_STEP * COLUMNS, calls.info)
        end)

        it("never reads the clock without a budget", function()
            local reads = 0
            _G.debugprofilestop = function() reads = reads + 1 return 0 end
            Shapes.step(CONTINENT)
            assert.equals(0, reads)
        end)
    end)

    describe("resuming and several continents", function()
        it("continues at the next row after pending steps and samples no row twice", function()
            installClock(1)
            assert.equals("pending", Shapes.step(CONTINENT, 4))
            assert.equals("pending", Shapes.step(CONTINENT, 4))
            assert.equals(8 * COLUMNS, calls.info)
            stepToDone(CONTINENT, 4)
            assert.equals(COLUMNS * ROWS, calls.info)
            assert.equals(ROWS - 2, #Shapes.cached(CONTINENT)[ELWYNN].runs)
        end)

        it("keeps the jobs of two continents independent", function()
            local OTHER = 1414
            local seen = {}
            _G.C_Map.GetMapInfoAtPosition = function(mapId)
                seen[mapId] = (seen[mapId] or 0) + 1
                return { mapID = mapId == CONTINENT and ELWYNN or DUROTAR }
            end
            assert.equals("pending", Shapes.step(CONTINENT, 4)) -- the fallback: 4 rows
            assert.equals("pending", Shapes.step(OTHER, 4))
            assert.equals("pending", Shapes.step(OTHER, 4))
            assert.same({ [CONTINENT] = 4 * COLUMNS, [OTHER] = 8 * COLUMNS }, seen)
            stepToDone(OTHER, 4)
            assert.is_nil(Shapes.cached(CONTINENT))
            stepToDone(CONTINENT, 4)
            assert.equals(COLUMNS * ROWS, seen[CONTINENT])
            assert.equals(COLUMNS * ROWS, seen[OTHER])
            assert.equals(ROWS, #Shapes.cached(CONTINENT)[ELWYNN].runs)
            assert.is_nil(Shapes.cached(CONTINENT)[DUROTAR])
            assert.is_nil(Shapes.cached(OTHER)[ELWYNN])
        end)

        it("forgets finished shapes and running jobs on reset", function()
            Shapes.step(CONTINENT, 4)
            Shapes.reset()
            Shapes.step(CONTINENT, 4)
            assert.equals(2 * Shapes.FALLBACK_ROWS_PER_STEP * COLUMNS, calls.info)
            Shapes.reset()
            Shapes.step(CONTINENT)
            Shapes.reset()
            assert.is_nil(Shapes.cached(CONTINENT))
        end)
    end)

    describe("the cache", function()
        it("answers a cached continent without any API call", function()
            Shapes.step(CONTINENT)
            local after = calls.info
            assert.equals("done", Shapes.step(CONTINENT))
            assert.equals("done", Shapes.step(CONTINENT, 4))
            assert.equals(after, calls.info)
            _G.C_Map = nil
            assert.equals("done", Shapes.step(CONTINENT))
        end)

        it("keeps an empty result when the API worked, so a continent without data zones is sampled once", function()
            local count = 0
            _G.C_Map.GetMapInfoAtPosition = function()
                count = count + 1
                return { mapID = CITY }
            end
            assert.equals("done", Shapes.step(CONTINENT))
            assert.same({}, Shapes.cached(CONTINENT))
            assert.equals(COLUMNS * ROWS, count)
            assert.equals("done", Shapes.step(CONTINENT))
            assert.equals(COLUMNS * ROWS, count)
        end)
    end)

    describe("failures", function()
        it("fails without the API and keeps nothing", function()
            _G.C_Map = nil
            assert.equals("failed", Shapes.step(CONTINENT))
            assert.equals("failed", Shapes.step(CONTINENT, 4))
            _G.C_Map = {}
            assert.equals("failed", Shapes.step(CONTINENT))
            assert.is_nil(Shapes.cached(CONTINENT))
        end)

        it("fails after one call when the first call errors, then starts again at row 1 once it works", function()
            local count = 0
            _G.C_Map.GetMapInfoAtPosition = function()
                count = count + 1
                error("restricted")
            end
            assert.equals("failed", Shapes.step(CONTINENT, 4))
            assert.equals(1, count)
            assert.is_nil(Shapes.cached(CONTINENT))
            installLookup()
            assert.equals("pending", Shapes.step(CONTINENT, 4))
            assert.equals(Shapes.FALLBACK_ROWS_PER_STEP * COLUMNS, calls.info) -- row 1 again, not a resume
            stepToDone(CONTINENT, 4)
            assert.is_not_nil(Shapes.cached(CONTINENT)[ELWYNN])
        end)

        it("drops a job whose API disappears and does not resume it", function()
            Shapes.step(CONTINENT, 4)
            _G.C_Map = nil
            assert.equals("failed", Shapes.step(CONTINENT, 4))
            installLookup()
            Shapes.step(CONTINENT, 4)
            assert.equals(Shapes.FALLBACK_ROWS_PER_STEP * COLUMNS, calls.info)
        end)

        it("leaves a cell empty when a later call errors and carries on", function()
            local count = 0
            _G.C_Map.GetMapInfoAtPosition = function()
                count = count + 1
                if count == 5 then error("restricted") end
                return { mapID = ELWYNN }
            end
            assert.equals("done", Shapes.step(CONTINENT))
            local runs = Shapes.cached(CONTINENT)[ELWYNN].runs
            assert.same({ 1, 1, 4 }, runs[1])
            assert.same({ 1, 6, COLUMNS }, runs[2])
            assert.equals(ROWS + 1, #runs)
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
