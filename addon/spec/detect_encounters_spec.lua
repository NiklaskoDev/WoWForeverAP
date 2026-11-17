local Env = require("helpers.addon_env")
local Linked = require("helpers.linked")

describe("Boss kills", function()
    local ns, game, db

    local function bossId(encounter) return ns.Ids.locationId(ns.Ids.LocCat.BOSS, encounter) end

    --- ENCOUNTER_END(encounterID, encounterName, difficultyID, groupSize, success)
    local function ended(encounter, success)
        ns.Events.dispatch("ENCOUNTER_END", encounter, "Edwin VanCleef", 1, 5, success)
    end

    before_each(function()
        local Ids = Env.new().Ids
        ns, game, db = Linked.new({ Ids.locationId(Ids.LocCat.BOSS, 9001), Ids.locationId(Ids.LocCat.BOSS, 9002) })
    end)

    it("records a kill of a listed encounter, with chat feedback", function()
        ended(9001, 1)
        assert.same({ bossId(9001) }, Linked.outbox(db))
        assert.equals(ns.L.CHECK_RECORDED:format(ns.L.BOSS_FMT:format(9001)), Env.chatText(game)[1])
        assert.equals(ns.L.UNSYNCED:format(1), Env.chatText(game)[2])
    end)

    it("names the boss from the generated data when it is known", function()
        ns.Data.bosses[9001] = { name = "Boss A", instance = "Test Mines", zone = 1436 }
        ended(9001, 1)
        assert.equals(ns.L.CHECK_RECORDED:format("Test Mines: Boss A"), Env.chatText(game)[1])
    end)

    it("ignores an encounter that did not end in a kill", function()
        ended(9001, 0)
        ended(9001, nil)
        ended(9001, 2)
        ended(9001, "1")
        assert.same({}, Linked.outbox(db))
        assert.same({}, game.chat)
    end)

    it("ignores an encounter the seed does not list, and a payload without a numeric id", function()
        ended(9999, 1)
        ended(nil, 1)
        ended("9001", 1)
        ended({}, 1)
        assert.same({}, Linked.outbox(db))
    end)

    it("ignores an encounter id outside the id scheme", function()
        ended(-1, 1)
        ended(ns.Ids.CATEGORY_SIZE, 1)
        assert.same({}, Linked.outbox(db))
        assert.same({}, game.errors)
    end)

    it("ignores an encounter the server already checked and records the same one only once", function()
        WoWForeverAP_Inbox.slots["S1:Wow"].checked[bossId(9002)] = true
        ended(9002, 1)
        assert.same({}, Linked.outbox(db))
        ended(9001, 1)
        ended(9001, 1)
        assert.same({ bossId(9001) }, Linked.outbox(db))
    end)

    it("does nothing for an unlinked character or before the addon is ready", function()
        db.characters[game.guid].slotKey = nil
        ended(9001, 1)
        db.characters[game.guid].slotKey = "S1:Wow"
        ns.ready = false
        ended(9001, 1)
        assert.same({}, Linked.outbox(db))
    end)

    it("is registered for ENCOUNTER_END, and a client that does not know the event just skips it", function()
        assert.is_true(game.frames[1].events.ENCOUNTER_END)
        game.frames[1].events.ENCOUNTER_END = nil
        _G.C_EventUtils = { IsEventValid = function() return false end }
        assert.has_no.errors(function()
            assert(loadfile(Env.ADDON_DIR .. "Detect/Encounters.lua"))("WoWForeverAP", ns)
        end)
        assert.is_nil(game.frames[1].events.ENCOUNTER_END)
    end)
end)
