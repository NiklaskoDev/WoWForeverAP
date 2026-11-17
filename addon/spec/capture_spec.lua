local Env = require("helpers.addon_env")

describe("Capture", function()
    local ns, game, db

    before_each(function()
        ns, game = Env.new()
        db = ns.DB.init(nil)
        ns.db, ns.ready = db, true
    end)

    it("is off by default and creates its tables on first use", function()
        assert.is_false(ns.Capture.isEnabled(db))
        local capture = ns.Capture.table(db)
        assert.same({}, capture.zones)
        assert.same({}, capture.quests)
        assert.same({}, capture.encounters)
        assert.same({}, capture.areas)
    end)

    it("stores the build and locale when switched on", function()
        ns.Capture.setEnabled(db, true)
        assert.is_true(ns.Capture.isEnabled(db))
        assert.same({ version = "1.60.1", build = "70938", date = "Nov 12 2026", toc = 16001 }, db.capture.build)
        assert.equals("enUS", db.capture.locale)
        ns.Capture.setEnabled(db, false)
        assert.is_false(ns.Capture.isEnabled(db))
        assert.is_not_nil(db.capture.build)
    end)

    describe("with the game API", function()
        before_each(function()
            _G.C_Map = {
                GetBestMapForUnit = function() return 1429 end,
                GetMapInfo = function(id) return { name = "Elwynn Forest", mapID = id } end,
                GetMapLevels = function() return 1, 10 end,
            }
            _G.C_QuestLog = { GetTitleForQuestID = function() return "A Threat Within" end }
            game.level = 4
        end)

        it("logs the zone with its level range", function()
            ns.Capture.setEnabled(db, true)
            ns.Events.dispatch("ZONE_CHANGED_NEW_AREA")
            assert.same({ name = "Elwynn Forest", minLevel = 1, maxLevel = 10, seen = game.now },
                db.capture.zones[1429])
            db.capture.zones[1429] = nil
            ns.Events.dispatch("PLAYER_ENTERING_WORLD")
            assert.is_not_nil(db.capture.zones[1429])
        end)

        it("logs a turned-in quest with title, zone, level and faction", function()
            ns.Capture.setEnabled(db, true)
            ns.Events.dispatch("QUEST_TURNED_IN", 783, 0, 0)
            assert.same({ title = "A Threat Within", uiMapId = 1429, level = 4, faction = "Alliance", seen = game.now },
                db.capture.quests[783])
        end)

        it("logs nothing while off, and nothing before the addon is ready", function()
            ns.Events.dispatch("QUEST_TURNED_IN", 783, 0, 0)
            ns.Events.dispatch("ZONE_CHANGED_NEW_AREA")
            ns.Events.dispatch("ENCOUNTER_END", 593, "Edwin", 1, 5, 1)
            ns.Events.dispatch("ZONE_CHANGED")
            assert.is_nil(db.capture)
            ns.Capture.setEnabled(db, true)
            ns.ready = false
            ns.Events.dispatch("QUEST_TURNED_IN", 783, 0, 0)
            ns.Events.dispatch("ENCOUNTER_END", 593, "Edwin", 1, 5, 1)
            ns.Events.dispatch("ZONE_CHANGED")
            assert.same({}, db.capture.quests)
            assert.same({}, db.capture.encounters)
            assert.same({}, db.capture.areas)
        end)

        describe("encounters", function()
            before_each(function()
                _G.GetInstanceInfo = function() return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36, 5 end
                ns.Capture.setEnabled(db, true)
            end)

            it("logs the ENCOUNTER_END payload with the instance id of the map the player stands in", function()
                ns.Events.dispatch("ENCOUNTER_END", 593, "Edwin VanCleef", 1, 5, 1, {})
                assert.same({ name = "Edwin VanCleef", difficultyId = 1, groupSize = 5, instanceId = 36,
                    success = true, seen = game.now }, db.capture.encounters[593])
            end)

            it("logs a wipe as not successful, and a later kill keeps the success", function()
                ns.Events.dispatch("ENCOUNTER_END", 593, "Edwin VanCleef", 1, 5, 0)
                assert.is_false(db.capture.encounters[593].success)
                ns.Events.dispatch("ENCOUNTER_END", 593, "Edwin VanCleef", 1, 5, 1)
                ns.Events.dispatch("ENCOUNTER_END", 593, "Edwin VanCleef", 1, 5, 0)
                assert.is_true(db.capture.encounters[593].success)
            end)

            it("ignores an event without a numeric id and works without GetInstanceInfo", function()
                ns.Events.dispatch("ENCOUNTER_END", nil, "Nobody", 1, 5, 1)
                assert.same({}, db.capture.encounters)
                _G.GetInstanceInfo = nil
                ns.Events.dispatch("ENCOUNTER_END", 593, "Edwin VanCleef", 1, 5, 1)
                assert.is_nil(db.capture.encounters[593].instanceId)
                assert.same({}, game.errors)
            end)
        end)

        describe("explored areas", function()
            local function explore(areaIds)
                _G.C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end
                _G.C_Map.GetAreaInfo = function(areaId) return "Area " .. areaId end
                _G.C_MapExplorationInfo = {
                    GetExploredAreaIDsAtPosition = function(uiMapId, position)
                        assert.equals(1429, uiMapId)
                        assert.is_function(position.GetXY)
                        return areaIds
                    end,
                }
            end

            it("logs every explored area at the position on each zone event, with its name and map", function()
                explore({ 57, 18 })
                ns.Capture.setEnabled(db, true)
                for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
                    "PLAYER_ENTERING_WORLD" }) do
                    db.capture.areas = {}
                    ns.Events.dispatch(event)
                    assert.same({ name = "Area 18", uiMapId = 1429, seen = game.now }, db.capture.areas[18], event)
                    assert.same({ name = "Area 57", uiMapId = 1429, seen = game.now }, db.capture.areas[57], event)
                end
            end)

            it("logs an area without a name when the client cannot name it", function()
                explore({ 18 })
                _G.C_Map.GetAreaInfo = nil
                ns.Capture.setEnabled(db, true)
                ns.Events.dispatch("ZONE_CHANGED")
                assert.same({ uiMapId = 1429, seen = game.now }, db.capture.areas[18])
            end)
        end)

        it("skips a zone the API cannot describe", function()
            ns.Capture.setEnabled(db, true)
            _G.C_Map.GetBestMapForUnit = function() return nil end
            ns.Events.dispatch("ZONE_CHANGED_NEW_AREA")
            assert.same({}, db.capture.zones)
        end)
    end)

    describe("with game APIs missing", function()
        before_each(function()
            _G.GetBuildInfo = nil
            _G.GetLocale = nil
        end)

        it("switches on without the build and locale fields and raises no error", function()
            assert.has_no.errors(function() ns.Capture.setEnabled(db, true) end)
            assert.is_true(ns.Capture.isEnabled(db))
            assert.is_nil(db.capture.build)
            assert.is_nil(db.capture.locale)
        end)

        it("records a quest without title and zone, and no error is raised", function()
            ns.Capture.setEnabled(db, true)
            assert.has_no.errors(function() ns.Events.dispatch("QUEST_TURNED_IN", 783, 0, 0) end)
            assert.same({}, game.errors)
            assert.same({ level = 1, faction = "Alliance", seen = game.now }, db.capture.quests[783])
        end)

        it("logs no encounter or area, and raises no error, without the exploration API", function()
            ns.Capture.setEnabled(db, true)
            ns.Events.dispatch("ZONE_CHANGED")
            ns.Events.dispatch("ENCOUNTER_END", 593, "Edwin VanCleef", 1, 5, 1)
            assert.same({}, db.capture.areas)
            assert.same({ name = "Edwin VanCleef", difficultyId = 1, groupSize = 5, success = true, seen = game.now },
                db.capture.encounters[593])
            assert.same({}, game.errors)
        end)

        it("records no zone when there is no map API", function()
            ns.Capture.setEnabled(db, true)
            assert.has_no.errors(function() ns.Events.dispatch("ZONE_CHANGED_NEW_AREA") end)
            assert.same({}, game.errors)
            assert.same({}, db.capture.zones)
        end)

        it("records a zone without levels when only GetMapLevels is missing", function()
            _G.C_Map = {
                GetBestMapForUnit = function() return 1429 end,
                GetMapInfo = function() return { name = "Elwynn Forest" } end,
            }
            ns.Capture.setEnabled(db, true)
            ns.Events.dispatch("ZONE_CHANGED_NEW_AREA")
            assert.same({ name = "Elwynn Forest", seen = game.now }, db.capture.zones[1429])
            assert.same({}, game.errors)
        end)

        it("treats a failing API like a missing one", function()
            _G.C_Map = {
                GetBestMapForUnit = function() return 1429 end,
                GetMapInfo = function() error("restricted") end,
            }
            _G.C_QuestLog = { GetTitleForQuestID = function() error("restricted") end }
            ns.Capture.setEnabled(db, true)
            ns.Events.dispatch("ZONE_CHANGED_NEW_AREA")
            ns.Events.dispatch("QUEST_TURNED_IN", 5, 0, 0)
            assert.same({}, db.capture.zones)
            assert.same({ uiMapId = 1429, level = 1, faction = "Alliance", seen = game.now }, db.capture.quests[5])
            assert.same({}, game.errors)
        end)
    end)
end)
