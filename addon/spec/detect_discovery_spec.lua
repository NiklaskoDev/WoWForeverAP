local Env = require("helpers.addon_env")
local Linked = require("helpers.linked")

describe("Area discovery", function()
    local ns, game, db

    local CRYSTAL_LAKE, FARGODEEP, MOONBROOK = 18, 57, 20
    local ZONE_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }

    local function areaId(area) return ns.Ids.locationId(ns.Ids.LocCat.AREA_DISCOVERY, area) end

    --- Fakes the map APIs: the player stands on map 1429 at `position`, and `explored` is what the client reports.
    local position
    local function standing(explored)
        position = { GetXY = function() return 0.4, 0.6 end }
        _G.C_Map = {
            GetBestMapForUnit = function(unit) return unit == "player" and 1429 or nil end,
            GetPlayerMapPosition = function(uiMapId, unit)
                return uiMapId == 1429 and unit == "player" and position or nil
            end,
        }
        _G.C_MapExplorationInfo = {
            GetExploredAreaIDsAtPosition = function(uiMapId, given)
                assert.equals(1429, uiMapId)
                assert.equals(position, given) -- the position goes through unchanged
                return explored
            end,
        }
    end

    before_each(function()
        local Ids = Env.new().Ids
        ns, game, db = Linked.new({ Ids.locationId(Ids.LocCat.AREA_DISCOVERY, CRYSTAL_LAKE),
            Ids.locationId(Ids.LocCat.AREA_DISCOVERY, FARGODEEP) })
    end)

    describe("exploredAreaIds", function()
        it("returns the explored areas ascending and the map they were read on", function()
            standing({ FARGODEEP, CRYSTAL_LAKE })
            local areas, uiMapId = ns.Discovery.exploredAreaIds()
            assert.same({ CRYSTAL_LAKE, FARGODEEP }, areas)
            assert.equals(1429, uiMapId)
        end)

        it("keeps numbers only and accepts an empty or odd answer", function()
            standing({ 5, "x", false, 3 })
            assert.same({ 3, 5 }, (ns.Discovery.exploredAreaIds()))
            standing(nil)
            assert.same({}, (ns.Discovery.exploredAreaIds()))
            standing("not a table")
            assert.same({}, (ns.Discovery.exploredAreaIds()))
        end)

        it("gives an empty list when an API is missing, fails or has no answer", function()
            assert.same({}, (ns.Discovery.exploredAreaIds())) -- no map API at all
            standing({ CRYSTAL_LAKE })
            _G.C_MapExplorationInfo = nil
            assert.same({}, (ns.Discovery.exploredAreaIds()))
            standing({ CRYSTAL_LAKE })
            _G.C_MapExplorationInfo.GetExploredAreaIDsAtPosition = function() error("restricted") end
            assert.same({}, (ns.Discovery.exploredAreaIds()))
            standing({ CRYSTAL_LAKE })
            _G.C_Map.GetPlayerMapPosition = nil
            assert.same({}, (ns.Discovery.exploredAreaIds()))
            standing({ CRYSTAL_LAKE })
            _G.C_Map.GetBestMapForUnit = function() return nil end
            assert.same({}, (ns.Discovery.exploredAreaIds()))
            standing({ CRYSTAL_LAKE })
            _G.C_Map.GetPlayerMapPosition = function() return nil end
            assert.same({}, (ns.Discovery.exploredAreaIds()))
        end)
    end)

    describe("milestones", function()
        it("keeps the explored areas the seed lists", function()
            local slot = ns.Inbox.slot(ns.Inbox.current(), "S1:Wow")
            assert.same({ areaId(CRYSTAL_LAKE) }, ns.Discovery.milestones(slot, { CRYSTAL_LAKE, MOONBROOK }))
            assert.same({}, ns.Discovery.milestones(slot, { MOONBROOK, -1 }))
            assert.same({}, ns.Discovery.milestones(slot, {}))
        end)
    end)

    describe("on a zone event", function()
        it("records the listed areas at the player's position, on each of the three events", function()
            for index, event in ipairs(ZONE_EVENTS) do
                standing({ index == 1 and CRYSTAL_LAKE or FARGODEEP })
                ns.Events.dispatch(event)
            end
            assert.same({ areaId(CRYSTAL_LAKE), areaId(FARGODEEP) }, Linked.outbox(db))
            assert.equals(ns.L.CHECK_RECORDED:format("Discover Crystal Lake"), Env.chatText(game)[1])
        end)

        it("ignores an area the seed does not list", function()
            standing({ MOONBROOK })
            ns.Events.dispatch("ZONE_CHANGED")
            assert.same({}, Linked.outbox(db))
            assert.same({}, game.chat)
        end)

        it("ignores an area the server already checked and records an area only once", function()
            WoWForeverAP_Inbox.slots["S1:Wow"].checked[areaId(FARGODEEP)] = true
            standing({ CRYSTAL_LAKE, FARGODEEP })
            ns.Events.dispatch("ZONE_CHANGED")
            ns.Events.dispatch("ZONE_CHANGED_INDOORS")
            assert.same({ areaId(CRYSTAL_LAKE) }, Linked.outbox(db))
        end)

        it("does nothing for an unlinked character or before the addon is ready", function()
            standing({ CRYSTAL_LAKE })
            db.characters[game.guid].slotKey = nil
            ns.Events.dispatch("ZONE_CHANGED")
            db.characters[game.guid].slotKey = "S1:Wow"
            ns.ready = false
            ns.Events.dispatch("ZONE_CHANGED")
            assert.same({}, Linked.outbox(db))
        end)

        it("raises no error without the exploration API", function()
            assert.has_no.errors(function() ns.Events.dispatch("ZONE_CHANGED_NEW_AREA") end)
            assert.same({}, game.errors)
            assert.same({}, Linked.outbox(db))
        end)
    end)
end)
