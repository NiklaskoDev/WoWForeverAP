local Env = require("helpers.addon_env")

describe("Commands", function()
    local ns, game, db

    local function questId(quest) return ns.Ids.locationId(ns.Ids.LocCat.QUEST, quest) end

    local function chat() return Env.chatText(game) end

    before_each(function()
        ns, game = Env.new()
        db = ns.DB.init(nil)
        ns.db, ns.ready = db, true
        ns.DB.touchCharacter(db, game.guid, "Arthas", "Alliance", "PALADIN")
    end)

    describe("parse", function()
        it("splits the first word, lower-cased, from the rest", function()
            local word, rest = ns.Commands.parse("  LINK   2  ")
            assert.equals("link", word)
            assert.equals("2", rest)
            word, rest = ns.Commands.parse("capture on")
            assert.equals("capture", word)
            assert.equals("on", rest)
        end)

        it("accepts an empty or missing message", function()
            assert.equals("", (ns.Commands.parse("")))
            assert.equals("", (ns.Commands.parse(nil)))
        end)
    end)

    describe("resolveSlot", function()
        local keys = { "a:One", "b:Two" }

        it("picks the only slot without an argument", function()
            assert.equals("a:One", ns.Commands.resolveSlot({ "a:One" }, ""))
        end)

        it("needs a choice when several slots exist and no argument is given", function()
            local key, problem = ns.Commands.resolveSlot(keys, "")
            assert.is_nil(key)
            assert.equals("choose", problem)
        end)

        it("picks by number and rejects numbers outside the list", function()
            assert.equals("b:Two", ns.Commands.resolveSlot(keys, "2"))
            for _, bad in ipairs({ "0", "3", "x", "1.5", "-1" }) do
                local key, problem = ns.Commands.resolveSlot(keys, bad)
                assert.is_nil(key, bad)
                assert.equals("bad", problem, bad)
            end
        end)

        it("reports that no slot exists", function()
            local key, problem = ns.Commands.resolveSlot({}, "")
            assert.is_nil(key)
            assert.equals("none", problem)
        end)
    end)

    describe("startLines", function()
        local function slotWith(options)
            return { options = options }
        end

        it("shows faction, start zone, goal level and the professions split by kind", function()
            local lines = ns.Commands.startLines(Env.inbox().slots["S1:Wow"])
            assert.same({
                ns.L.START_FACTION:format("Alliance"), ns.L.START_ZONE:format("Elwynn Forest"),
                ns.L.START_GOAL:format(60), ns.L.START_PRIMARY:format("Alchemy, Mining"),
                ns.L.START_SECONDARY:format(ns.L.START_NONE),
            }, lines)
        end)

        it("lists secondary professions apart and uses the localised names", function()
            _G.C_Map = { GetMapInfo = function() return { name = "Wald von Elwynn" } end }
            local lines = ns.Commands.startLines(slotWith({
                faction = "horde", startZone = 1429, goalLevel = 30, professions = { 185, 171, 356 } }))
            assert.equals(ns.L.START_FACTION:format("Horde"), lines[1])
            assert.equals(ns.L.START_ZONE:format("Wald von Elwynn"), lines[2])
            assert.equals(ns.L.START_PRIMARY:format("Alchemy"), lines[4])
            assert.equals(ns.L.START_SECONDARY:format("Cooking, Fishing"), lines[5])
        end)

        it("lists a profession the data does not know as a primary one, and copes with a bare slot", function()
            local lines = ns.Commands.startLines(slotWith({ professions = { 999999 } }))
            assert.equals(ns.L.START_PRIMARY:format(ns.L.PROFESSION_FMT:format(999999)), lines[4])
            assert.equals(5, #ns.Commands.startLines({}))
        end)
    end)

    describe("/wfap", function()
        it("shows the help for unknown commands and for help", function()
            ns.Commands.run("frobnicate")
            ns.Commands.run("help")
            assert.equals(ns.L.HELP_HEADER, chat()[1])
            assert.equals(ns.L.HELP_HEADER, chat()[12]) -- the header plus ten command lines come first
            local expected = { "HELP_PANEL", "HELP_STATUS", "HELP_START", "HELP_LINK", "HELP_UNLINK", "HELP_ITEMS",
                               "HELP_RULES", "HELP_CARE", "HELP_OPTIONS", "HELP_CAPTURE" }
            for index, key in ipairs(expected) do
                assert.equals(ns.L[key], chat()[index + 1], key)
            end
        end)

        it("opens the window for no command, and again closes it", function()
            local calls = 0
            ns.Panel.toggle = function() calls = calls + 1 end
            ns.Commands.run("")
            ns.Commands.run("   ")
            assert.equals(2, calls)
            assert.same({}, chat())
        end)

        it("opens the options with /wfap options and says so when the client has none", function()
            ns.Commands.run("options")
            assert.same({ ns.L.OPTIONS_UNAVAILABLE }, chat())
        end)

        it("is registered as the slash command and the compartment click toggles the window", function()
            assert.equals("/wfap", SLASH_WFAP1)
            SlashCmdList["WFAP"]("help")
            assert.equals(ns.L.HELP_HEADER, chat()[1])
            local toggled = 0
            ns.Panel.toggle = function() toggled = toggled + 1 end
            WoWForeverAP_OnCompartmentClick("WoWForeverAP", "LeftButton")
            assert.equals(1, toggled)
        end)

        it("status of an unlinked character names the slots in the inbox", function()
            _G.WoWForeverAP_Inbox = Env.inbox()
            ns.Commands.run("status")
            assert.same({ ns.L.NOT_LINKED, ns.L.STATUS_SLOTS:format(1) }, chat())
        end)

        it("status of a linked character shows slot, items, open and unsynced checks", function()
            _G.WoWForeverAP_Inbox = Env.inbox({
                locations = { [questId(1)] = true, [questId(2)] = true, [questId(3)] = true, [questId(4)] = true },
                checked = { [questId(1)] = true },
                items = { { id = 1 }, { id = 2 } },
            })
            db.characters[game.guid].slotKey = "S1:Wow"
            ns.DB.addCheck(db, "S1:Wow", questId(2), game.guid, 1)
            ns.Commands.run("status")
            assert.same({
                ns.L.STATUS_LINKED:format("S1:Wow"), ns.L.STATUS_ITEMS:format(2),
                ns.L.STATUS_OPEN:format(2), ns.L.STATUS_UNSYNCED:format(1),
            }, chat())
        end)

        it("status says when the character's slot is missing in the inbox", function()
            db.characters[game.guid].slotKey = "S9:Gone"
            ns.Commands.run("status")
            assert.same({ ns.L.SLOT_MISSING:format("S9:Gone") }, chat())
        end)

        it("start of a linked character shows the lines of its slot only", function()
            _G.WoWForeverAP_Inbox = Env.inbox()
            WoWForeverAP_Inbox.slots["S2:Other"] = { options = { faction = "horde" } }
            db.characters[game.guid].slotKey = "S1:Wow"
            ns.Commands.run("start")
            assert.same(ns.Commands.startLines(WoWForeverAP_Inbox.slots["S1:Wow"]), chat())
            assert.equals(5, #chat())
        end)

        it("start of an unlinked character lists every slot as a numbered block", function()
            _G.WoWForeverAP_Inbox = Env.inbox()
            WoWForeverAP_Inbox.slots["S2:Other"] = {
                options = { faction = "horde", startZone = 14, goalLevel = 30, professions = { 185 } } }
            ns.Commands.run("start")
            local expected = { ns.L.START_SLOT_HEADER:format(1, "S1:Wow") }
            for _, line in ipairs(ns.Commands.startLines(WoWForeverAP_Inbox.slots["S1:Wow"])) do
                expected[#expected + 1] = line
            end
            expected[#expected + 1] = ns.L.START_SLOT_HEADER:format(2, "S2:Other")
            for _, line in ipairs(ns.Commands.startLines(WoWForeverAP_Inbox.slots["S2:Other"])) do
                expected[#expected + 1] = line
            end
            assert.same(expected, chat())
            assert.equals(12, #chat())
        end)

        it("start escapes a pipe in the slot name", function()
            _G.WoWForeverAP_Inbox = Env.inbox()
            WoWForeverAP_Inbox.slots["S1:Wo|cffff0000w"] = WoWForeverAP_Inbox.slots["S1:Wow"]
            WoWForeverAP_Inbox.slots["S1:Wow"] = nil
            ns.Commands.run("start")
            assert.equals(ns.L.START_SLOT_HEADER:format(1, "S1:Wo||cffff0000w"), chat()[1])
        end)

        it("start without slots says so; a linked character with a missing slot gets the missing-slot line", function()
            ns.Commands.run("start")
            assert.same({ ns.L.LINK_NO_SLOTS }, chat())
            game.chat = {}
            db.characters[game.guid].slotKey = "S9:Gone"
            ns.Commands.run("start")
            assert.same({ ns.L.SLOT_MISSING:format("S9:Gone") }, chat())
        end)

        it("link without argument links the only slot", function()
            _G.WoWForeverAP_Inbox = Env.inbox()
            ns.Commands.run("link")
            assert.equals("S1:Wow", db.characters[game.guid].slotKey)
            assert.equals(ns.L.LINK_OK:format("Arthas", "S1:Wow"), chat()[1])
        end)

        it("link lists the numbered slots when several exist and links by number", function()
            _G.WoWForeverAP_Inbox = Env.inbox()
            WoWForeverAP_Inbox.slots["S2:Other"] = {}
            ns.Commands.run("link")
            assert.same({ ns.L.LINK_CHOOSE, ns.L.LINK_SLOT_LINE:format(1, "S1:Wow"),
                          ns.L.LINK_SLOT_LINE:format(2, "S2:Other") }, chat())
            assert.is_nil(db.characters[game.guid].slotKey)
            ns.Commands.run("link 1")
            assert.equals("S1:Wow", db.characters[game.guid].slotKey)
        end)

        it("link reports a bad number and an empty inbox", function()
            _G.WoWForeverAP_Inbox = Env.inbox()
            ns.Commands.run("link 7")
            assert.equals(ns.L.LINK_BAD_INDEX, chat()[1])
            _G.WoWForeverAP_Inbox = nil
            game.chat = {}
            ns.Commands.run("link")
            assert.same({ ns.L.LINK_NO_SLOTS }, chat())
        end)

        it("unlink removes the link, and complains when there is none", function()
            ns.Commands.run("unlink")
            assert.equals(ns.L.NOT_LINKED, chat()[1])
            db.characters[game.guid].slotKey = "S1:Wow"
            ns.Commands.run("unlink")
            assert.equals(ns.L.UNLINK_OK, chat()[2])
            assert.is_nil(db.characters[game.guid].slotKey)
        end)

        it("items lists received items and marks them as seen", function()
            _G.WoWForeverAP_Inbox = Env.inbox({
                items = { { id = ns.Ids.itemId(ns.Ids.ItemCat.ZONE, 1436), sender = "Ben", loc = 1 } },
            })
            db.characters[game.guid].slotKey = "S1:Wow"
            ns.Commands.run("items")
            assert.same({ ns.L.ITEMS_HEADER:format(1), "Zone: Westfall (from Ben)" }, chat())
            assert.equals(1, db.characters[game.guid].seenItemCount)
        end)

        it("items says so when nothing was received and when the character is not linked", function()
            ns.Commands.run("items")
            assert.equals(ns.L.NOT_LINKED, chat()[1])
            _G.WoWForeverAP_Inbox = Env.inbox()
            db.characters[game.guid].slotKey = "S1:Wow"
            ns.Commands.run("items")
            assert.equals(ns.L.ITEMS_EMPTY, chat()[2])
        end)

        it("capture switches the developer logging on and off and explains bad input", function()
            ns.Commands.run("capture on")
            assert.is_true(ns.Capture.isEnabled(db))
            assert.equals(ns.L.CAPTURE_ON, chat()[1])
            ns.Commands.run("capture off")
            assert.is_false(ns.Capture.isEnabled(db))
            assert.equals(ns.L.CAPTURE_OFF, chat()[2])
            ns.Commands.run("capture maybe")
            assert.equals(ns.L.CAPTURE_USAGE, chat()[3])
        end)

        it("does nothing harmful before the addon is ready", function()
            ns.ready = false
            ns.Commands.run("status")
            ns.Commands.run("unlink")
            ns.Commands.run("capture on")
            assert.is_nil(db.capture)
        end)
    end)
end)
