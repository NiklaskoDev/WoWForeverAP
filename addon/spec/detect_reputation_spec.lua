local Env = require("helpers.addon_env")
local Linked = require("helpers.linked")

describe("Reputation", function()
    local ns, game, db

    local STORMWIND, IRONFORGE = 72, 47
    local FRIENDLY, HONORED, REVERED, EXALTED = 5, 6, 7, 8

    local function repId(faction, standing)
        return ns.Ids.locationId(ns.Ids.LocCat.REPUTATION, faction * 10 + standing)
    end

    local function seed()
        local Ids = Env.new().Ids
        local ids = {}
        for _, standing in ipairs({ FRIENDLY, HONORED, REVERED, EXALTED }) do
            ids[#ids + 1] = Ids.locationId(Ids.LocCat.REPUTATION, STORMWIND * 10 + standing)
        end
        ids[#ids + 1] = Ids.locationId(Ids.LocCat.REPUTATION, IRONFORGE * 10 + FRIENDLY)
        return ids
    end

    --- The client's standing of every faction, `{ [factionID] = reaction }`; a missing faction answers nil.
    local function standings(map)
        _G.C_Reputation = {
            GetFactionDataByID = function(factionId)
                return map[factionId] and { factionID = factionId, name = "Faction" .. factionId,
                    reaction = map[factionId] } or nil
            end,
        }
    end

    local function slotOf() return ns.Inbox.slot(ns.Inbox.current(), "S1:Wow") end

    before_each(function()
        ns, game, db = Linked.new(seed(), { rep = {} })
    end)

    describe("currentStanding", function()
        it("reads the reaction of the faction", function()
            standings({ [STORMWIND] = HONORED })
            assert.equals(HONORED, ns.Reputation.currentStanding(STORMWIND))
        end)

        it("answers nil when the API is missing, fails, or does not know the faction or the shape", function()
            assert.is_nil(ns.Reputation.currentStanding(STORMWIND))
            standings({})
            assert.is_nil(ns.Reputation.currentStanding(STORMWIND))
            _G.C_Reputation = { GetFactionDataByID = function() error("restricted") end }
            assert.is_nil(ns.Reputation.currentStanding(STORMWIND))
            _G.C_Reputation = { GetFactionDataByID = function() return { reaction = "6" } end }
            assert.is_nil(ns.Reputation.currentStanding(STORMWIND))
        end)
    end)

    describe("decode", function()
        it("splits a reputation location into faction and standing", function()
            local factionId, standing = ns.Reputation.decode(repId(STORMWIND, REVERED))
            assert.equals(STORMWIND, factionId)
            assert.equals(REVERED, standing)
        end)

        it("returns nothing for other locations and for garbage", function()
            assert.is_nil(ns.Reputation.decode(ns.Ids.locationId(ns.Ids.LocCat.QUEST, 783)))
            assert.is_nil(ns.Reputation.decode("x"))
            assert.is_nil(ns.Reputation.decode(5))
        end)
    end)

    describe("standings (the link baseline)", function()
        it("holds the current standing of every faction the seed lists, and leaves out unknown ones", function()
            standings({ [STORMWIND] = HONORED })
            assert.same({ [STORMWIND] = HONORED }, ns.Reputation.standings(slotOf()))
            standings({ [STORMWIND] = HONORED, [IRONFORGE] = 4 })
            assert.same({ [STORMWIND] = HONORED, [IRONFORGE] = 4 }, ns.Reputation.standings(slotOf()))
        end)

        it("is empty without the API or without reputation locations", function()
            assert.same({}, ns.Reputation.standings(slotOf()))
            assert.same({}, ns.Reputation.standings({}))
        end)
    end)

    describe("baseline", function()
        it("holds the standing of every listed faction and false for one the client does not report", function()
            standings({ [STORMWIND] = HONORED })
            assert.same({ [STORMWIND] = HONORED, [IRONFORGE] = false }, ns.Reputation.baseline(slotOf()))
        end)

        it("is false for every listed faction without the API, and empty without reputation locations", function()
            assert.same({ [STORMWIND] = false, [IRONFORGE] = false }, ns.Reputation.baseline(slotOf()))
            assert.same({}, ns.Reputation.baseline({}))
        end)
    end)

    describe("milestones", function()
        it("awards nothing for a faction whose baseline is unknown", function()
            assert.same({}, ns.Reputation.milestones(slotOf(), { [STORMWIND] = false }, { [STORMWIND] = EXALTED }))
        end)

        it("counts the standings reached above the baseline, ascending", function()
            local found = ns.Reputation.milestones(slotOf(), { [STORMWIND] = 4 }, { [STORMWIND] = REVERED })
            assert.same({ repId(STORMWIND, FRIENDLY), repId(STORMWIND, HONORED), repId(STORMWIND, REVERED) }, found)
        end)

        it("ignores a standing equal to or below the baseline", function()
            local found = ns.Reputation.milestones(slotOf(), { [STORMWIND] = HONORED }, { [STORMWIND] = REVERED })
            assert.same({ repId(STORMWIND, REVERED) }, found)
            assert.same({}, ns.Reputation.milestones(slotOf(), { [STORMWIND] = HONORED }, { [STORMWIND] = HONORED }))
            assert.same({}, ns.Reputation.milestones(slotOf(), { [STORMWIND] = EXALTED }, { [STORMWIND] = EXALTED }))
        end)

        it("ignores a standing that is not reached yet, or a faction the client does not report", function()
            assert.same({}, ns.Reputation.milestones(slotOf(), {}, { [STORMWIND] = 4 }))
            assert.same({}, ns.Reputation.milestones(slotOf(), {}, {}))
            assert.same({ repId(IRONFORGE, FRIENDLY) },
                ns.Reputation.milestones(slotOf(), {}, { [IRONFORGE] = FRIENDLY }))
        end)

        it("treats a faction without a baseline as Neutral", function()
            local found = ns.Reputation.milestones(slotOf(), {}, { [STORMWIND] = FRIENDLY })
            assert.same({ repId(STORMWIND, FRIENDLY) }, found)
        end)
    end)

    describe("on UPDATE_FACTION", function()
        it("records the standings gained after the link, with chat feedback", function()
            standings({ [STORMWIND] = FRIENDLY, [IRONFORGE] = 4 })
            ns.Events.dispatch("UPDATE_FACTION")
            assert.same({ repId(STORMWIND, FRIENDLY) }, Linked.outbox(db))
            assert.equals(ns.L.CHECK_RECORDED:format("Faction72: Friendly"), Env.chatText(game)[1])
        end)

        it("does not count what the character had when it linked", function()
            db.characters[game.guid].baselines = { rep = { [STORMWIND] = HONORED, [IRONFORGE] = FRIENDLY } }
            standings({ [STORMWIND] = HONORED, [IRONFORGE] = FRIENDLY })
            ns.Events.dispatch("UPDATE_FACTION")
            assert.same({}, Linked.outbox(db))
            standings({ [STORMWIND] = REVERED, [IRONFORGE] = FRIENDLY })
            ns.Events.dispatch("UPDATE_FACTION")
            assert.same({ repId(STORMWIND, REVERED) }, Linked.outbox(db))
        end)

        it("records every standing passed at once and each one only once", function()
            standings({ [STORMWIND] = EXALTED })
            ns.Events.dispatch("UPDATE_FACTION")
            ns.Events.dispatch("UPDATE_FACTION")
            assert.equals(4, #Linked.outbox(db))
        end)

        it("skips what the server already checked", function()
            WoWForeverAP_Inbox.slots["S1:Wow"].checked[repId(STORMWIND, FRIENDLY)] = true
            standings({ [STORMWIND] = FRIENDLY })
            ns.Events.dispatch("UPDATE_FACTION")
            assert.same({}, Linked.outbox(db))
        end)

        it("gives an Exalted character nothing when the API was missing at link time", function()
            db.characters[game.guid].baselines = { rep = ns.Reputation.baseline(slotOf()) } -- no API: all false
            standings({ [STORMWIND] = EXALTED, [IRONFORGE] = 4 })
            ns.Events.dispatch("UPDATE_FACTION")
            assert.same({}, Linked.outbox(db))
            assert.equals(EXALTED, db.characters[game.guid].baselines.rep[STORMWIND]) -- now the baseline
            assert.equals(4, db.characters[game.guid].baselines.rep[IRONFORGE])
            ns.Events.dispatch("UPDATE_FACTION")
            assert.same({}, Linked.outbox(db))
        end)

        it("keeps an unknown baseline unknown while the API still fails, then counts only later gains", function()
            db.characters[game.guid].baselines = { rep = { [STORMWIND] = false, [IRONFORGE] = false } }
            ns.Events.dispatch("UPDATE_FACTION") -- API missing
            assert.same({ [STORMWIND] = false, [IRONFORGE] = false }, db.characters[game.guid].baselines.rep)
            standings({ [STORMWIND] = HONORED }) -- first read: baseline Honored, nothing awarded
            ns.Events.dispatch("UPDATE_FACTION")
            assert.same({}, Linked.outbox(db))
            assert.equals(HONORED, db.characters[game.guid].baselines.rep[STORMWIND])
            assert.is_false(db.characters[game.guid].baselines.rep[IRONFORGE]) -- still not reported
            standings({ [STORMWIND] = REVERED })
            ns.Events.dispatch("UPDATE_FACTION")
            assert.same({ repId(STORMWIND, REVERED) }, Linked.outbox(db))
        end)

        it("works for a character without stored baselines (all Neutral)", function()
            db.characters[game.guid].baselines = nil
            standings({ [STORMWIND] = FRIENDLY })
            ns.Events.dispatch("UPDATE_FACTION")
            assert.same({ repId(STORMWIND, FRIENDLY) }, Linked.outbox(db))
        end)

        it("does nothing without the API, for an unlinked character or before the addon is ready", function()
            assert.has_no.errors(function() ns.Events.dispatch("UPDATE_FACTION") end)
            standings({ [STORMWIND] = FRIENDLY })
            db.characters[game.guid].slotKey = nil
            ns.Events.dispatch("UPDATE_FACTION")
            db.characters[game.guid].slotKey = "S1:Wow"
            ns.ready = false
            ns.Events.dispatch("UPDATE_FACTION")
            assert.same({}, Linked.outbox(db))
            assert.same({}, game.errors)
        end)
    end)
end)
