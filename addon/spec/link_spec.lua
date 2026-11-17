local Env = require("helpers.addon_env")

describe("Link", function()
    local ns, game, Link, db

    local function slotInbox(faction)
        local inbox = Env.inbox()
        inbox.slots["S1:Wow"].options.faction = faction or "alliance"
        return inbox
    end

    before_each(function()
        ns, game = Env.new()
        Link = ns.Link
        db = ns.DB.init(nil)
        ns.DB.touchCharacter(db, "Player-1", "Arthas", "Alliance", "PALADIN")
        ns.db, ns.ready = db, true
    end)

    describe("factionMatches", function()
        it("compares case-insensitively", function()
            assert.is_true(Link.factionMatches("Alliance", "alliance"))
            assert.is_false(Link.factionMatches("Horde", "alliance"))
            assert.is_false(Link.factionMatches(nil, "alliance"))
            assert.is_false(Link.factionMatches("Alliance", nil))
        end)
    end)

    describe("link", function()
        it("stores the baseline: level, skills, time; no warning at level 1", function()
            local ok, warnings = Link.link(db, "Player-1", "S1:Wow", slotInbox(), 1, { [171] = 0, [186] = 12 }, 555)
            assert.is_true(ok)
            assert.same({}, warnings)
            local character = db.characters["Player-1"]
            assert.equals("S1:Wow", character.slotKey)
            assert.equals(555, character.linkedAt)
            assert.equals(1, character.linkedLevel)
            assert.same({ [171] = 0, [186] = 12 }, character.skillAtLink)
            assert.equals(0, character.seenItemCount)
        end)

        it("warns that earlier progress does not count above level 1", function()
            local ok, warnings = Link.link(db, "Player-1", "S1:Wow", slotInbox(), 12, {}, 1)
            assert.is_true(ok)
            assert.same({ { "LINK_LEVEL_WARNING", 12 } }, warnings)
        end)

        it("refuses a faction mismatch and leaves the character unlinked", function()
            local ok, message = Link.link(db, "Player-1", "S1:Wow", slotInbox("horde"), 1, {}, 1)
            assert.is_false(ok)
            assert.same({ "LINK_FACTION_MISMATCH", "Alliance", "horde" }, message)
            assert.is_nil(db.characters["Player-1"].slotKey)
        end)

        it("refuses a slot that is not in the inbox and an unknown character", function()
            local ok, message = Link.link(db, "Player-1", "nope", slotInbox(), 1, {}, 1)
            assert.is_false(ok)
            assert.same({ "LINK_BAD_SLOT" }, message)
            ok = Link.link(db, "Player-404", "S1:Wow", slotInbox(), 1, {}, 1)
            assert.is_false(ok)
        end)

        it("refuses to link a character that is already linked", function()
            assert.is_true(Link.link(db, "Player-1", "S1:Wow", slotInbox(), 1, {}, 1))
            local ok, message = Link.link(db, "Player-1", "S1:Wow", slotInbox(), 1, {}, 2)
            assert.is_false(ok)
            assert.same({ "LINK_ALREADY", "S1:Wow" }, message)
            assert.equals(1, db.characters["Player-1"].linkedAt)
        end)

        it("clears a never-ask choice", function()
            db.characters["Player-1"].neverAsk = true
            assert.is_true(Link.link(db, "Player-1", "S1:Wow", slotInbox(), 1, {}, 1))
            assert.is_nil(db.characters["Player-1"].neverAsk)
        end)
    end)

    describe("unlink", function()
        it("removes the link data but keeps the slot's outbox", function()
            Link.link(db, "Player-1", "S1:Wow", slotInbox(), 1, {}, 1)
            ns.DB.addCheck(db, "S1:Wow", 5110000783, "Player-1", 2)
            assert.is_true(Link.unlink(db, "Player-1"))
            local character = db.characters["Player-1"]
            assert.is_nil(character.slotKey)
            assert.is_nil(character.linkedLevel)
            assert.is_nil(character.skillAtLink)
            assert.equals(1, #db.slots["S1:Wow"].outbox)
        end)

        it("returns false for a character that is not linked", function()
            assert.is_false(Link.unlink(db, "Player-1"))
            assert.is_false(Link.unlink(db, "Player-404"))
        end)
    end)

    describe("loginAction", function()
        local function twoSlots()
            local inbox = slotInbox()
            inbox.slots["S2:Other"] = {}
            return inbox
        end

        it("prompts when exactly one slot exists", function()
            local action, slotKey = Link.loginAction(db, "Player-1", slotInbox())
            assert.equals("prompt", action)
            assert.equals("S1:Wow", slotKey)
        end)

        it("hints when several slots exist", function()
            assert.equals("hint", (Link.loginAction(db, "Player-1", twoSlots())))
        end)

        it("does nothing without slots, for a linked character, and after never-ask", function()
            assert.is_nil(Link.loginAction(db, "Player-1", { schema = 1, slots = {} }))
            assert.is_nil(Link.loginAction(db, "Player-1", nil))
            db.characters["Player-1"].neverAsk = true
            assert.is_nil(Link.loginAction(db, "Player-1", slotInbox()))
            db.characters["Player-1"].neverAsk = nil
            db.characters["Player-1"].slotKey = "S1:Wow"
            assert.is_nil(Link.loginAction(db, "Player-1", slotInbox()))
            assert.is_nil(Link.loginAction(db, "Player-404", slotInbox()))
        end)
    end)

    describe("in the game", function()
        before_each(function()
            _G.WoWForeverAP_Inbox = slotInbox()
            game.level = 5
            ns.DB.touchCharacter(db, game.guid, "Arthas", "Alliance", "PALADIN")
        end)

        it("linkPlayer links the logged-in character and tells the player, with the level warning", function()
            assert.is_true(Link.linkPlayer("S1:Wow"))
            assert.equals("S1:Wow", db.characters[game.guid].slotKey)
            assert.equals(5, db.characters[game.guid].linkedLevel)
            local chat = Env.chatText(game)
            assert.equals(ns.L.LINK_OK:format("Arthas", "S1:Wow"), chat[1])
            assert.equals(ns.L.LINK_LEVEL_WARNING:format(5), chat[2])
        end)

        it("linkPlayer reports a refusal in chat", function()
            ns.DB.touchCharacter(db, game.guid, "Arthas", "Horde", "PALADIN")
            assert.is_false(Link.linkPlayer("S1:Wow"))
            assert.equals(ns.L.LINK_FACTION_MISMATCH:format("Horde", "alliance"), Env.chatText(game)[1])
            assert.is_nil(db.characters[game.guid].slotKey)
        end)

        it("shows the link popup at login for one slot and stays quiet after never-ask", function()
            Link.promptIfNeeded()
            assert.equals(1, #game.popups)
            assert.equals("WOWFOREVERAP_LINK", game.popups[1].which)
            assert.equals("Arthas", game.popups[1].arg1)
            assert.equals("S1:Wow", game.popups[1].arg2)
            assert.same({ slotKey = "S1:Wow" }, game.popups[1].data)
            local dialog = StaticPopupDialogs["WOWFOREVERAP_LINK"]
            dialog.OnAlt()
            Link.promptIfNeeded()
            assert.equals(1, #game.popups)
        end)

        it("accepting the popup links the character", function()
            StaticPopupDialogs["WOWFOREVERAP_LINK"].OnAccept(nil, { slotKey = "S1:Wow" })
            assert.equals("S1:Wow", db.characters[game.guid].slotKey)
            assert.equals(5, db.characters[game.guid].linkedLevel)
        end)

        it("tells the player to choose when several slots exist", function()
            WoWForeverAP_Inbox.slots["S2:Other"] = {}
            Link.promptIfNeeded()
            assert.equals(0, #game.popups)
            assert.equals(ns.L.LINK_HINT, Env.chatText(game)[1])
        end)

        it("localises the popup buttons", function()
            assert.equals(ns.locales.enUS.LINK_YES, StaticPopupDialogs["WOWFOREVERAP_LINK"].button1)
            assert.equals(ns.locales.enUS.LINK_NEVER, StaticPopupDialogs["WOWFOREVERAP_LINK"].button3)
        end)
    end)
end)
