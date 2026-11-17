local Env = require("helpers.addon_env")
local Linked = require("helpers.linked")

describe("PvP", function()
    local ns, game, db

    local HK_100, HK_250, WSG, ARATHI = 1, 2, 10, 11 -- pvp ids of the generated data
    local WSG_MAP, ARATHI_MAP = 489, 529
    local HORDE, ALLIANCE = 0, 1

    local function pvpId(id) return ns.Ids.locationId(ns.Ids.LocCat.PVP, id) end

    local function seed()
        local Ids = Env.new().Ids
        local ids = {}
        for _, id in ipairs({ HK_100, HK_250, WSG, ARATHI }) do
            ids[#ids + 1] = Ids.locationId(Ids.LocCat.PVP, id)
        end
        return ids
    end

    local function slotOf() return ns.Inbox.slot(ns.Inbox.current(), "S1:Wow") end

    local function lifetimeKills(kills)
        _G.GetPVPLifetimeStats = function() return kills, 0 end
    end

    --- The player stands in the instance with the given id (GetInstanceInfo's eighth return).
    local function inInstance(instanceId)
        _G.GetInstanceInfo = function() return "Warsong Gulch", "pvp", 0, "", 0, 0, false, instanceId, 0 end
    end

    before_each(function()
        ns, game, db = Linked.new(seed(), { hk = 40, bgWins = {} })
    end)

    describe("honorable kills", function()
        it("reads the lifetime total, the first return of GetPVPLifetimeStats", function()
            lifetimeKills(321)
            assert.equals(321, ns.PvP.honorableKills())
        end)

        it("answers nil when the API is missing, fails or answers something else", function()
            assert.is_nil(ns.PvP.honorableKills())
            _G.GetPVPLifetimeStats = function() error("restricted") end
            assert.is_nil(ns.PvP.honorableKills())
            _G.GetPVPLifetimeStats = function() return "many" end
            assert.is_nil(ns.PvP.honorableKills())
        end)

        it("reaches a milestone at exactly its kill count", function()
            assert.same({}, ns.PvP.killMilestones(slotOf(), 99))
            assert.same({ pvpId(HK_100) }, ns.PvP.killMilestones(slotOf(), 100))
            assert.same({ pvpId(HK_100) }, ns.PvP.killMilestones(slotOf(), 249))
            assert.same({ pvpId(HK_100), pvpId(HK_250) }, ns.PvP.killMilestones(slotOf(), 250))
        end)

        it("counts the kills from the link baseline, not from zero", function()
            lifetimeKills(139) -- 99 since the link
            ns.Events.dispatch("PLAYER_PVP_KILLS_CHANGED", "player")
            assert.same({}, Linked.outbox(db))
            lifetimeKills(140) -- 100 since the link
            ns.Events.dispatch("PLAYER_PVP_KILLS_CHANGED", "player")
            assert.same({ pvpId(HK_100) }, Linked.outbox(db))
            assert.equals(ns.L.CHECK_RECORDED:format("100 honorable kills"), Env.chatText(game)[1])
        end)

        it("does not count the kills of a character that already had many when it linked", function()
            db.characters[game.guid].baselines = { hk = 5000 }
            lifetimeKills(5000)
            ns.Events.dispatch("PLAYER_PVP_KILLS_CHANGED", "player")
            assert.same({}, Linked.outbox(db))
        end)

        it("records every milestone passed and each only once", function()
            lifetimeKills(40 + 300)
            ns.Events.dispatch("PLAYER_PVP_KILLS_CHANGED", "player")
            ns.Events.dispatch("PLAYER_PVP_KILLS_CHANGED", "player")
            assert.same({ pvpId(HK_100), pvpId(HK_250) }, Linked.outbox(db))
        end)

        it("skips milestones the server already checked", function()
            WoWForeverAP_Inbox.slots["S1:Wow"].checked[pvpId(HK_100)] = true
            lifetimeKills(40 + 100)
            ns.Events.dispatch("PLAYER_PVP_KILLS_CHANGED", "player")
            assert.same({}, Linked.outbox(db))
        end)

        it("does nothing without a baseline, without the API, unlinked or before the addon is ready", function()
            lifetimeKills(1000)
            db.characters[game.guid].baselines = {}
            ns.Events.dispatch("PLAYER_PVP_KILLS_CHANGED", "player")
            db.characters[game.guid].baselines = nil
            ns.Events.dispatch("PLAYER_PVP_KILLS_CHANGED", "player")
            db.characters[game.guid].baselines = { hk = 0 }
            _G.GetPVPLifetimeStats = nil
            assert.has_no.errors(function() ns.Events.dispatch("PLAYER_PVP_KILLS_CHANGED", "player") end)
            lifetimeKills(1000)
            db.characters[game.guid].slotKey = nil
            ns.Events.dispatch("PLAYER_PVP_KILLS_CHANGED", "player")
            db.characters[game.guid].slotKey = "S1:Wow"
            ns.ready = false
            ns.Events.dispatch("PLAYER_PVP_KILLS_CHANGED", "player")
            assert.same({}, Linked.outbox(db))
            assert.same({}, game.errors)
        end)
    end)

    describe("battleground wins", function()
        it("reads the battleground from the instance id of GetInstanceInfo", function()
            assert.is_nil(ns.PvP.instanceId())
            inInstance(WSG_MAP)
            assert.equals(WSG_MAP, ns.PvP.instanceId())
            _G.GetInstanceInfo = function() error("restricted") end
            assert.is_nil(ns.PvP.instanceId())
        end)

        it("records a win of the player's faction in a listed battleground and tallies it", function()
            inInstance(WSG_MAP)
            ns.Events.dispatch("PVP_MATCH_COMPLETE", ALLIANCE, 600)
            assert.same({ pvpId(WSG) }, Linked.outbox(db))
            assert.same({ [WSG_MAP] = 1 }, db.characters[game.guid].baselines.bgWins)
            assert.equals(ns.L.CHECK_RECORDED:format("Win Warsong Gulch"), Env.chatText(game)[1])
        end)

        it("does not count a loss, a draw or a win of the other faction", function()
            inInstance(WSG_MAP)
            ns.Events.dispatch("PVP_MATCH_COMPLETE", HORDE, 600)
            ns.Events.dispatch("PVP_MATCH_COMPLETE", nil, 600)
            ns.Events.dispatch("PVP_MATCH_COMPLETE", 255, 600)
            assert.same({}, Linked.outbox(db))
            game.faction = "Horde"
            ns.Events.dispatch("PVP_MATCH_COMPLETE", ALLIANCE, 600)
            assert.same({}, Linked.outbox(db))
            ns.Events.dispatch("PVP_MATCH_COMPLETE", HORDE, 600)
            assert.same({ pvpId(WSG) }, Linked.outbox(db))
        end)

        it("ignores a win outside a battleground of the seed", function()
            inInstance(30) -- Alterac Valley is not in this seed
            ns.Events.dispatch("PVP_MATCH_COMPLETE", ALLIANCE, 600)
            assert.same({}, Linked.outbox(db))
            _G.GetInstanceInfo = nil
            ns.Events.dispatch("PVP_MATCH_COMPLETE", ALLIANCE, 600)
            assert.same({}, Linked.outbox(db))
            assert.same({}, game.errors)
        end)

        it("records the battleground of the win, not another one", function()
            inInstance(ARATHI_MAP)
            ns.Events.dispatch("PVP_MATCH_COMPLETE", ALLIANCE, 600)
            assert.same({ pvpId(ARATHI) }, Linked.outbox(db))
        end)

        it("counts a match once even when both the match event and the status event report it", function()
            inInstance(WSG_MAP)
            _G.GetBattlefieldWinner = function() return ALLIANCE end
            ns.Events.dispatch("PVP_MATCH_COMPLETE", ALLIANCE, 600)
            ns.Events.dispatch("UPDATE_BATTLEFIELD_STATUS", 1)
            ns.Events.dispatch("UPDATE_BATTLEFIELD_STATUS", 1)
            assert.same({ [WSG_MAP] = 1 }, db.characters[game.guid].baselines.bgWins)
            ns.Events.dispatch("PLAYER_ENTERING_WORLD") -- the next match starts a new count
            ns.Events.dispatch("PVP_MATCH_COMPLETE", ALLIANCE, 600)
            assert.same({ [WSG_MAP] = 2 }, db.characters[game.guid].baselines.bgWins)
            assert.same({ pvpId(WSG) }, Linked.outbox(db))
        end)

        it("falls back to GetBattlefieldWinner on UPDATE_BATTLEFIELD_STATUS", function()
            inInstance(WSG_MAP)
            _G.GetBattlefieldWinner = function() return nil end -- match still running
            ns.Events.dispatch("UPDATE_BATTLEFIELD_STATUS", 1)
            assert.same({}, Linked.outbox(db))
            _G.GetBattlefieldWinner = function() return ALLIANCE end
            ns.Events.dispatch("UPDATE_BATTLEFIELD_STATUS", 1)
            assert.same({ pvpId(WSG) }, Linked.outbox(db))
        end)

        it("does not count a running match: no winner yet is not a win", function()
            inInstance(WSG_MAP)
            _G.GetBattlefieldWinner = function() return nil end
            ns.Events.dispatch("UPDATE_BATTLEFIELD_STATUS", 1)
            ns.Events.dispatch("PVP_MATCH_COMPLETE", nil, 0)
            assert.same({}, Linked.outbox(db))
            assert.same({}, db.characters[game.guid].baselines.bgWins)
        end)

        it("does not count a win for a Neutral or unknown faction, whatever the winner is", function()
            inInstance(WSG_MAP)
            _G.GetBattlefieldWinner = function() return nil end
            for _, faction in ipairs({ "Neutral", "Pandaren", false }) do
                game.faction = faction
                ns.Events.dispatch("UPDATE_BATTLEFIELD_STATUS", 1)
                ns.Events.dispatch("PVP_MATCH_COMPLETE", HORDE, 600)
                ns.Events.dispatch("PVP_MATCH_COMPLETE", ALLIANCE, 600)
            end
            game.faction = nil
            ns.Events.dispatch("PVP_MATCH_COMPLETE", nil, 600)
            assert.same({}, Linked.outbox(db))
            assert.same({}, db.characters[game.guid].baselines.bgWins)
            assert.same({}, game.errors)
        end)

        it("raises no error when GetBattlefieldWinner is missing or fails", function()
            inInstance(WSG_MAP)
            assert.has_no.errors(function() ns.Events.dispatch("UPDATE_BATTLEFIELD_STATUS", 1) end)
            _G.GetBattlefieldWinner = function() error("restricted") end
            assert.has_no.errors(function() ns.Events.dispatch("UPDATE_BATTLEFIELD_STATUS", 1) end)
            assert.same({}, Linked.outbox(db))
            assert.same({}, game.errors)
        end)

        it("creates the win tally for a character without stored baselines", function()
            db.characters[game.guid].baselines = nil
            inInstance(WSG_MAP)
            ns.Events.dispatch("PVP_MATCH_COMPLETE", ALLIANCE, 600)
            assert.same({ [WSG_MAP] = 1 }, db.characters[game.guid].baselines.bgWins)
        end)

        it("does nothing for an unlinked character or before the addon is ready", function()
            inInstance(WSG_MAP)
            db.characters[game.guid].slotKey = nil
            ns.Events.dispatch("PVP_MATCH_COMPLETE", ALLIANCE, 600)
            db.characters[game.guid].slotKey = "S1:Wow"
            ns.ready = false
            ns.Events.dispatch("PVP_MATCH_COMPLETE", ALLIANCE, 600)
            assert.same({}, Linked.outbox(db))
        end)

        it("skips a win the server already checked", function()
            WoWForeverAP_Inbox.slots["S1:Wow"].checked[pvpId(WSG)] = true
            inInstance(WSG_MAP)
            ns.Events.dispatch("PVP_MATCH_COMPLETE", ALLIANCE, 600)
            assert.same({}, Linked.outbox(db))
        end)
    end)

    describe("events", function()
        it("registers the kill, match and status events", function()
            local events = game.frames[1].events
            assert.is_true(events.PLAYER_PVP_KILLS_CHANGED)
            assert.is_true(events.PVP_MATCH_COMPLETE)
            assert.is_true(events.UPDATE_BATTLEFIELD_STATUS)
        end)

        it("skips events the client does not know and keeps the others", function()
            local events = game.frames[1].events
            events.PVP_MATCH_COMPLETE, events.UPDATE_BATTLEFIELD_STATUS = nil, nil
            _G.C_EventUtils = { IsEventValid = function(event) return event ~= "PVP_MATCH_COMPLETE" end }
            assert.has_no.errors(function()
                assert(loadfile(Env.ADDON_DIR .. "Detect/PvP.lua"))("WoWForeverAP", ns)
            end)
            assert.is_nil(events.PVP_MATCH_COMPLETE)
            assert.is_true(events.UPDATE_BATTLEFIELD_STATUS)
        end)
    end)
end)
