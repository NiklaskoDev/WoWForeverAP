local Env = require("helpers.addon_env")

describe("Warnings", function()
    local ns, game, db

    local SLOT = "S1:Wow"
    local ELWYNN, DUN_MOROGH, DUROTAR, CONTINENT = 1429, 1426, 1411, 1415
    local ALCHEMY, MINING, ENCHANTING = 171, 186, 333

    local function chat() return Env.chatText(game) end

    local function zoneItem(uiMapId) return ns.Ids.itemId(ns.Ids.ItemCat.ZONE, uiMapId) end
    local function tierItem(skillLine) return ns.Ids.itemId(ns.Ids.ItemCat.PROFESSION_TIER, skillLine) end

    --- Links the character to a slot that received `itemIds`; Elwynn Forest is the start zone, Alliance seed.
    local function link(itemIds, options)
        local items = {}
        for _, id in ipairs(itemIds or {}) do
            items[#items + 1] = { id = id, sender = "Ben", loc = 1 }
        end
        _G.WoWForeverAP_Inbox = Env.inbox({ items = items })
        for key, value in pairs(options or {}) do
            WoWForeverAP_Inbox.slots[SLOT].options[key] = value
        end
        db.characters[game.guid].slotKey = SLOT
    end

    --- Fake map API: `maps` maps a uiMapID to { mapType, parentMapID }; `game.mapId` is the player's best map.
    local function installMaps(maps)
        game.mapId = ELWYNN
        _G.C_Map = {
            GetBestMapForUnit = function() return game.mapId end,
            GetMapInfo = function(mapId)
                local map = maps[mapId]
                return map and { mapID = mapId, mapType = map[1], parentMapID = map[2] or 0 }
            end,
        }
    end

    local function enter(mapId, event)
        game.mapId = mapId
        ns.Events.dispatch(event or "ZONE_CHANGED_NEW_AREA")
    end

    before_each(function()
        ns, game = Env.new()
        db = ns.DB.init(nil)
        ns.db, ns.ready = db, true
        ns.DB.touchCharacter(db, game.guid, "Arthas", "Alliance", "PALADIN")
        local Zone, Micro = Enum.UIMapType.Zone, Enum.UIMapType.Micro
        installMaps({
            [CONTINENT] = { Enum.UIMapType.Continent },
            [ELWYNN] = { Zone, CONTINENT }, [DUN_MOROGH] = { Zone, CONTINENT }, [DUROTAR] = { Zone, CONTINENT },
            [5000] = { Micro, DUN_MOROGH }, [5001] = { Enum.UIMapType.Dungeon, DUN_MOROGH },
            [5002] = { Micro, 5003 }, [5003] = { Micro, 5002 }, [5004] = { Enum.UIMapType.Orphan },
        })
    end)

    it("registers the zone and skill events", function()
        assert.same({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED" },
            ns.Warnings.register())
        local registered = {}
        for _, frame in ipairs(game.frames) do
            for event in pairs(frame.events) do registered[event] = true end
        end
        assert.is_true(registered.ZONE_CHANGED_NEW_AREA and registered.PLAYER_ENTERING_WORLD
            and registered.SKILL_LINES_CHANGED)
    end)

    describe("zoneOf", function()
        it("returns a zone map itself and the parent zone of a sub-area", function()
            assert.equals(ELWYNN, ns.Warnings.zoneOf(ELWYNN))
            assert.equals(DUN_MOROGH, ns.Warnings.zoneOf(5000))
        end)

        it("returns nothing for continents, dungeons, orphans, unknown maps and a missing id", function()
            for _, mapId in ipairs({ CONTINENT, 5001, 5004, 99999 }) do
                assert.is_nil(ns.Warnings.zoneOf(mapId), mapId)
            end
            assert.is_nil(ns.Warnings.zoneOf(nil))
        end)

        it("gives up on a parent loop instead of hanging", function()
            assert.is_nil(ns.Warnings.zoneOf(5002))
        end)

        it("returns nothing when the map API is missing, fails or answers with restricted values", function()
            _G.C_Map = nil
            assert.is_nil(ns.Warnings.zoneOf(ELWYNN))
            _G.C_Map = { GetMapInfo = function() error("restricted") end }
            assert.is_nil(ns.Warnings.zoneOf(ELWYNN))
            _G.C_Map = { GetMapInfo = function() return { mapType = setmetatable({}, { __eq = error }) } end }
            assert.is_nil(ns.Warnings.zoneOf(ELWYNN))
            _G.Enum = nil
            installMaps({})
            assert.is_nil(ns.Warnings.zoneOf(ELWYNN))
        end)
    end)

    describe("zoneWarning", function()
        local function slotOf() return ns.Inbox.slot(ns.Inbox.current(), SLOT) end

        it("warns for a locked zone only", function()
            link({ zoneItem(1436) })
            assert.is_true(ns.Warnings.zoneWarning(slotOf(), DUN_MOROGH, nil))
            assert.is_false(ns.Warnings.zoneWarning(slotOf(), ELWYNN, nil)) -- start zone
            assert.is_false(ns.Warnings.zoneWarning(slotOf(), 1436, nil)) -- unlocked by item
            assert.is_false(ns.Warnings.zoneWarning(slotOf(), DUROTAR, nil)) -- other faction
            assert.is_false(ns.Warnings.zoneWarning(slotOf(), 1453, nil)) -- not in the data
            assert.is_false(ns.Warnings.zoneWarning(slotOf(), nil, nil))
        end)

        it("does not warn again while the player stays in the same zone", function()
            link()
            assert.is_false(ns.Warnings.zoneWarning(slotOf(), DUN_MOROGH, DUN_MOROGH))
        end)
    end)

    describe("entering a zone", function()
        before_each(function()
            link()
        end)

        it("warns once for a locked zone, in chat and on the raid warning frame", function()
            local shown = {}
            _G.RaidWarningUtil = { AddMessage = function(text, color) shown[#shown + 1] = { text, color } end }
            enter(DUN_MOROGH)
            enter(DUN_MOROGH)
            enter(DUN_MOROGH, "PLAYER_ENTERING_WORLD") -- a loading screen inside the same zone
            assert.equals(1, #shown)
            assert.equals(ns.L.ZONE_LOCKED:format("Dun Morogh"), shown[1][1])
            assert.is_true(shown[1][2].r > 0.9 and shown[1][2].g < 0.3)
            assert.same({ ns.L.ZONE_LOCKED:format("Dun Morogh") }, chat())
        end)

        it("warns again after the player left the zone", function()
            enter(DUN_MOROGH)
            enter(ELWYNN)
            enter(DUN_MOROGH)
            assert.equals(2, #chat())
        end)

        it("warns again after passing through a map that is no outdoor zone", function()
            enter(DUN_MOROGH)
            enter(5001) -- a dungeon
            enter(DUN_MOROGH)
            assert.equals(2, #chat())
        end)

        it("treats a sub-area of a locked zone as that zone", function()
            enter(5000)
            enter(DUN_MOROGH)
            assert.equals(1, #chat())
        end)

        it("never warns in an unlocked, start or other-faction zone, in a dungeon or on a continent", function()
            for _, mapId in ipairs({ ELWYNN, DUROTAR, 5001, CONTINENT, 99999 }) do
                enter(mapId)
                enter(mapId, "PLAYER_ENTERING_WORLD")
            end
            assert.same({}, chat())
            link({ zoneItem(DUN_MOROGH) })
            enter(DUN_MOROGH)
            assert.same({}, chat())
        end)

        it("is silent when the option is off, the character is not linked or the addon is not ready", function()
            db.ui.zoneWarnings = false
            enter(DUN_MOROGH)
            db.ui.zoneWarnings = true
            enter(ELWYNN)
            db.characters[game.guid].slotKey = nil
            enter(DUN_MOROGH)
            enter(ELWYNN)
            ns.ready = false
            enter(DUN_MOROGH)
            assert.same({}, chat())
        end)

        it("does not warn for a zone entered while warnings were off once they are switched on", function()
            db.ui.zoneWarnings = false
            enter(DUN_MOROGH)
            db.ui.zoneWarnings = true
            enter(DUN_MOROGH)
            assert.same({}, chat())
        end)

        it("survives a map API that fails", function()
            _G.C_Map = { GetBestMapForUnit = function() error("restricted") end }
            assert.has_no.errors(function() ns.Events.dispatch("ZONE_CHANGED_NEW_AREA") end)
            assert.same({}, game.errors)
            assert.same({}, chat())
        end)
    end)

    describe("alert", function()
        it("prefers the 12.x raid warning API", function()
            local texts = {}
            _G.RaidWarningUtil = { AddMessage = function(text) texts[#texts + 1] = text end }
            _G.RaidNotice_AddMessage = function() error("deprecated") end
            assert.equals("raidwarning", ns.Notify.alert("Hello"))
            assert.same({ "Hello" }, texts)
            assert.same({ "Hello" }, chat())
        end)

        it("falls back to the deprecated raid notice, then the error frame, then chat alone", function()
            local frame = {}
            _G.RaidWarningFrame = frame
            local noticed
            _G.RaidNotice_AddMessage = function(target, text) noticed = { target, text } end
            assert.equals("raidnotice", ns.Notify.alert("A"))
            assert.equals(frame, noticed[1])
            _G.RaidNotice_AddMessage, _G.RaidWarningFrame = nil, nil
            assert.equals("errorframe", ns.Notify.alert("B"))
            assert.equals("B", game.uiErrors[1].text)
            _G.UIErrorsFrame = nil
            assert.equals("chat", ns.Notify.alert("C"))
            assert.same({ "A", "B", "C" }, chat())
        end)

        it("still reaches chat when the raid warning frame throws", function()
            _G.RaidWarningUtil = { AddMessage = function() error("secret") end }
            assert.equals("errorframe", ns.Notify.alert("X"))
            assert.same({ "X" }, chat())
        end)
    end)

    describe("skillWarnings", function()
        local function fresh() return { learned = {}, rank = {} } end
        local function slotOf() return ns.Inbox.slot(ns.Inbox.current(), SLOT) end

        it("warns when a profession is learned while its tier item has not arrived, once", function()
            link()
            local warned = fresh()
            local first = ns.Warnings.skillWarnings(slotOf(), {}, { [ALCHEMY] = 1 }, warned)
            assert.same({ { key = "PROFESSION_LOCKED", skillLineId = ALCHEMY, rank = 1, allowed = 0 } }, first)
            assert.same({}, ns.Warnings.skillWarnings(slotOf(), {}, { [ALCHEMY] = 1 }, warned))
            assert.same({}, ns.Warnings.skillWarnings(slotOf(), {}, { [ALCHEMY] = 5 }, warned))
        end)

        it("warns once per rank above the unlocked tier", function()
            link({ tierItem(ALCHEMY) }) -- tier 1: up to skill 75
            local warned = fresh()
            assert.same({}, ns.Warnings.skillWarnings(slotOf(), {}, { [ALCHEMY] = 75 }, warned))
            local first = ns.Warnings.skillWarnings(slotOf(), {}, { [ALCHEMY] = 76 }, warned)
            assert.same({ { key = "PROFESSION_ABOVE_CAP", skillLineId = ALCHEMY, rank = 76, allowed = 75 } }, first)
            assert.same({}, ns.Warnings.skillWarnings(slotOf(), {}, { [ALCHEMY] = 76 }, warned))
            local next = ns.Warnings.skillWarnings(slotOf(), {}, { [ALCHEMY] = 77 }, warned)
            assert.equals(77, next[1].rank)
        end)

        it("does not warn after a second tier item raised the cap", function()
            link({ tierItem(ALCHEMY), tierItem(ALCHEMY) })
            assert.same({}, ns.Warnings.skillWarnings(slotOf(), {}, { [ALCHEMY] = 150 }, fresh()))
        end)

        it("ignores professions the seed does not include and non-number ranks", function()
            link()
            assert.same({}, ns.Warnings.skillWarnings(slotOf(), {}, { [ENCHANTING] = 1, [ALCHEMY] = "x" }, fresh()))
            link({}, { professions = { MINING } })
            assert.same({}, ns.Warnings.skillWarnings(slotOf(), {}, { [ALCHEMY] = 50 }, fresh()))
        end)

        it("does not hold skill from before linking against the character", function()
            link()
            local warned = fresh()
            assert.same({}, ns.Warnings.skillWarnings(slotOf(), { [ALCHEMY] = 100 }, { [ALCHEMY] = 100 }, warned))
            local above = ns.Warnings.skillWarnings(slotOf(), { [ALCHEMY] = 100 }, { [ALCHEMY] = 101 }, warned)
            assert.same({ { key = "PROFESSION_ABOVE_CAP", skillLineId = ALCHEMY, rank = 101, allowed = 100 } }, above)
        end)

        it("reports several professions in a stable order", function()
            link()
            local found = ns.Warnings.skillWarnings(slotOf(), {}, { [MINING] = 1, [ALCHEMY] = 1 }, fresh())
            assert.same({ ALCHEMY, MINING }, { found[1].skillLineId, found[2].skillLineId })
        end)
    end)

    describe("learning and training a profession", function()
        local function setRanks(ranks)
            _G.GetProfessions = function() return 1, 2 end
            local order = { 1, 2 }
            _G.GetProfessionInfo = function(index)
                local skillLine = ranks[order[index]]
                return "name", 0, skillLine[2], 300, 0, 0, skillLine[1]
            end
        end

        before_each(function()
            link({ tierItem(ALCHEMY) })
        end)

        it("warns on the event for a locked profession and for rank above the cap, once each", function()
            setRanks({ { MINING, 1 }, { ALCHEMY, 75 } })
            ns.Events.dispatch("SKILL_LINES_CHANGED")
            ns.Events.dispatch("SKILL_LINES_CHANGED")
            assert.same({ ns.L.PROFESSION_LOCKED:format("Mining") }, chat())
            setRanks({ { MINING, 1 }, { ALCHEMY, 76 } })
            ns.Events.dispatch("SKILL_LINES_CHANGED")
            ns.Events.dispatch("SKILL_LINES_CHANGED")
            assert.same({
                ns.L.PROFESSION_LOCKED:format("Mining"), ns.L.PROFESSION_ABOVE_CAP:format("Alchemy", 76, 75),
            }, chat())
        end)

        it("uses the saved skill from the moment of linking as the baseline", function()
            db.characters[game.guid].skillAtLink = { [MINING] = 40 }
            setRanks({ { MINING, 40 }, { ALCHEMY, 10 } })
            ns.Events.dispatch("SKILL_LINES_CHANGED")
            assert.same({}, chat())
        end)

        it("is silent when the option is off, the profession API is missing or the character is not linked", function()
            setRanks({ { MINING, 1 }, { ALCHEMY, 99 } })
            db.ui.zoneWarnings = false
            ns.Events.dispatch("SKILL_LINES_CHANGED")
            db.ui.zoneWarnings = true
            _G.GetProfessions, _G.GetProfessionInfo = nil, nil
            ns.Events.dispatch("SKILL_LINES_CHANGED")
            setRanks({ { MINING, 1 }, { ALCHEMY, 99 } })
            db.characters[game.guid].slotKey = nil
            ns.Events.dispatch("SKILL_LINES_CHANGED")
            for _, line in ipairs(chat()) do
                assert.is_nil(line:find("is locked", 1, true))
                assert.is_nil(line:find("above your unlocked tier", 1, true))
            end
        end)
    end)
end)
