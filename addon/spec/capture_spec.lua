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
    end)

    it("stores the build and locale when switched on", function()
        ns.Capture.setEnabled(db, true)
        assert.is_true(ns.Capture.isEnabled(db))
        assert.same({ version = "12.1.5", build = "70783", date = "Nov 4 2026", toc = 120105 }, db.capture.build)
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
            assert.is_nil(db.capture)
            ns.Capture.setEnabled(db, true)
            ns.ready = false
            ns.Events.dispatch("QUEST_TURNED_IN", 783, 0, 0)
            assert.same({}, db.capture.quests)
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
