local Env = require("helpers.addon_env")

describe("DB", function()
    local ns, DB

    before_each(function()
        ns = Env.new({ "Core/Namespace.lua", "Core/DB.lua" })
        DB = ns.DB
    end)

    describe("init and migrate", function()
        it("creates the tables on the first run", function()
            local db = DB.init(nil)
            assert.equals(1, db.schema)
            assert.same({}, db.characters)
            assert.same({}, db.slots)
        end)

        it("is idempotent and keeps existing data", function()
            local db = DB.init(nil)
            DB.touchCharacter(db, "Player-1", "Arthas", "Alliance", "PALADIN")
            DB.addCheck(db, "S1:Wow", 5110000783, "Player-1", 10)
            local before = { characters = db.characters, slots = db.slots }
            assert.equals(db, DB.init(db))
            assert.is_true(DB.migrate(db))
            assert.equals(before.characters, db.characters)
            assert.equals(before.slots, db.slots)
            assert.equals(1, #db.slots["S1:Wow"].outbox)
        end)

        it("fills in missing tables of a partial db", function()
            local db = DB.init({ schema = 1 })
            assert.same({}, db.characters)
            assert.same({}, db.slots)
        end)

        it("refuses data written by a newer schema and leaves it untouched", function()
            local newer = { schema = 2, future = true }
            local db, errorKey = DB.init(newer)
            assert.is_nil(db)
            assert.equals("DB_NEWER", errorKey)
            assert.equals(2, newer.schema)
            assert.is_nil(newer.characters)
        end)
    end)

    describe("characters", function()
        it("refreshes name, faction and class without touching the link", function()
            local db = DB.init(nil)
            local character = DB.touchCharacter(db, "Player-1", "Old Name", "Alliance", "MAGE")
            character.slotKey = "S1:Wow"
            DB.touchCharacter(db, "Player-1", "New Name", "Alliance", "MAGE")
            assert.equals("New Name", db.characters["Player-1"].name)
            assert.equals("S1:Wow", db.characters["Player-1"].slotKey)
        end)
    end)

    describe("outbox", function()
        local db

        before_each(function()
            db = DB.init(nil)
        end)

        it("appends a check entry with kind, id, character and time", function()
            assert.is_true(DB.addCheck(db, "S1:Wow", 5110000783, "Player-1", 123))
            assert.same({ { kind = "check", id = 5110000783, char = "Player-1", t = 123 } }, db.slots["S1:Wow"].outbox)
        end)

        it("never adds the same location twice, whichever character reports it", function()
            assert.is_true(DB.addCheck(db, "S1:Wow", 5120000002, "Player-1", 1))
            assert.is_false(DB.addCheck(db, "S1:Wow", 5120000002, "Player-1", 2))
            assert.is_false(DB.addCheck(db, "S1:Wow", 5120000002, "Player-2", 3))
            assert.equals(1, #db.slots["S1:Wow"].outbox)
            assert.is_true(DB.addCheck(db, "S2:Other", 5120000002, "Player-1", 4)) -- other slot, own outbox
        end)

        it("prune drops the checks the server knows and keeps the rest and other kinds", function()
            DB.addCheck(db, "S1:Wow", 1, "P", 1)
            DB.addCheck(db, "S1:Wow", 2, "P", 2)
            DB.addCheck(db, "S1:Wow", 3, "P", 3)
            local outbox = db.slots["S1:Wow"].outbox
            outbox[#outbox + 1] = { kind = "future", id = 2 }
            assert.equals(1, DB.prune(db, "S1:Wow", { [2] = true, [99] = true }))
            local ids = {}
            for _, entry in ipairs(db.slots["S1:Wow"].outbox) do
                ids[#ids + 1] = entry.kind .. entry.id
            end
            assert.same({ "check1", "check3", "future2" }, ids)
        end)

        it("prune on an unknown slot does nothing", function()
            assert.equals(0, DB.prune(db, "none", { [1] = true }))
        end)

        it("counts the checks the server has not confirmed", function()
            DB.addCheck(db, "S1:Wow", 1, "P", 1)
            DB.addCheck(db, "S1:Wow", 2, "P", 2)
            assert.equals(2, DB.unsyncedCount(db, "S1:Wow", {}))
            assert.equals(1, DB.unsyncedCount(db, "S1:Wow", { [1] = true }))
            assert.equals(0, DB.unsyncedCount(db, "unknown", {}))
        end)
    end)

    describe("goal", function()
        it("is stored once per slot", function()
            local db = DB.init(nil)
            assert.is_true(DB.setGoal(db, "S1:Wow", "Player-1", 5))
            assert.is_false(DB.setGoal(db, "S1:Wow", "Player-2", 9))
            assert.same({ char = "Player-1", t = 5 }, db.slots["S1:Wow"].goal)
        end)
    end)

    describe("ui options", function()
        it("fills the defaults on the first run and keeps what the player chose", function()
            local db = DB.init(nil)
            assert.same({ mapOverlay = true, zoneWarnings = true }, db.ui)
            db.ui.mapOverlay = false
            db.ui.panelPoint = { "CENTER", "CENTER", 10, 20 }
            DB.init(db)
            assert.is_false(db.ui.mapOverlay)
            assert.is_true(db.ui.zoneWarnings)
            assert.same({ "CENTER", "CENTER", 10, 20 }, db.ui.panelPoint)
        end)

        it("repairs a damaged ui table and non-boolean options", function()
            local db = DB.init({ ui = "broken" })
            assert.same({ mapOverlay = true, zoneWarnings = true }, db.ui)
            db = DB.init({ ui = { mapOverlay = "no", zoneWarnings = false } })
            assert.is_true(db.ui.mapOverlay)
            assert.is_false(db.ui.zoneWarnings)
        end)
    end)

    describe("outboxIds", function()
        it("returns the waiting check ids as a set", function()
            local db = DB.init(nil)
            DB.addCheck(db, "S1:Wow", 11, "Player-1", 1)
            DB.addCheck(db, "S1:Wow", 12, "Player-1", 2)
            assert.same({ [11] = true, [12] = true }, DB.outboxIds(db, "S1:Wow"))
            assert.same({}, DB.outboxIds(db, "other"))
        end)
    end)
end)
