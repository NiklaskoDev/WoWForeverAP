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

    describe("/wfap", function()
        it("shows the help for no command and for unknown commands", function()
            ns.Commands.run("")
            ns.Commands.run("frobnicate")
            assert.equals(ns.L.HELP_HEADER, chat()[1])
            assert.equals(ns.L.HELP_HEADER, chat()[9]) -- the header plus seven command lines come first
            assert.equals(ns.L.HELP_STATUS, chat()[2])
            assert.equals(ns.L.HELP_RULES, chat()[6])
            assert.equals(ns.L.HELP_CARE, chat()[7])
        end)

        it("is registered as the slash command and the compartment click shows the status", function()
            assert.equals("/wfap", SLASH_WFAP1)
            SlashCmdList["WFAP"]("help")
            assert.equals(ns.L.HELP_HEADER, chat()[1])
            WoWForeverAP_OnCompartmentClick("WoWForeverAP", "LeftButton")
            assert.equals(ns.L.NOT_LINKED, chat()[9])
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
