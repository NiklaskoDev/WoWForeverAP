local Env = require("helpers.addon_env")

describe("Economy", function()
    local ns, game, db

    local SLOT = "S1:Wow"

    local function chat() return Env.chatText(game) end

    local function carePackage() return ns.Data.carePackageItemId end

    local function economy() return WoWForeverAP_Inbox.slots[SLOT].options.economy end

    --- A linked character and an inbox in which the slot received `received` care packages.
    local function link(received)
        local items = {}
        for _ = 1, received or 0 do
            items[#items + 1] = { id = carePackage(), sender = "Ben", loc = 1 }
        end
        _G.WoWForeverAP_Inbox = Env.inbox({ items = items })
        db.characters[game.guid].slotKey = SLOT
    end

    local function interact(name)
        ns.Events.dispatch("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType[name])
    end

    before_each(function()
        ns, game = Env.new()
        db = ns.DB.init(nil)
        ns.db, ns.ready = db, true
        ns.DB.touchCharacter(db, game.guid, "Arthas", "Alliance", "PALADIN")
    end)

    describe("data", function()
        it("knows the id of the care package item", function()
            assert.equals(ns.Ids.itemId(ns.Ids.ItemCat.CARE_PACKAGE, 1), ns.Data.carePackageItemId)
            assert.equals(5140000001, ns.Data.carePackageItemId)
        end)

        it("names received care packages instead of calling them unknown", function()
            assert.equals(ns.L.ITEM_CARE_PACKAGE, ns.Names.item(carePackage()))
            assert.equals("Care Package", ns.L.ITEM_CARE_PACKAGE)
        end)
    end)

    describe("rules", function()
        it("reads the economy table of the slot and treats a missing one as nothing forbidden", function()
            link(0)
            assert.is_true(ns.Economy.rules(WoWForeverAP_Inbox.slots[SLOT]).auctionHouse)
            assert.is_nil(ns.Economy.rules({ options = {} }))
            assert.is_false(ns.Economy.isForbidden(nil, "mail"))
            assert.is_false(ns.Economy.isForbidden({}, "mail"))
        end)

        it("forbids only what the seed switched off", function()
            local rules = { auctionHouse = true, mail = false }
            assert.is_true(ns.Economy.isForbidden(rules, "mail"))
            assert.is_false(ns.Economy.isForbidden(rules, "auctionHouse"))
        end)

        it("maps interaction types to rules through the enum names", function()
            local expected = {
                Auctioneer = "auctionHouse", MailInfo = "mail", TradePartner = "trading",
                GuildBanker = "sharedBanks", AccountBanker = "sharedBanks",
            }
            for name, ruleKey in pairs(expected) do
                assert.equals(ruleKey, ns.Economy.ruleForInteraction(Enum.PlayerInteractionType[name]), name)
            end
            assert.is_nil(ns.Economy.ruleForInteraction(Enum.PlayerInteractionType.Merchant))
            assert.is_nil(ns.Economy.ruleForInteraction(Enum.PlayerInteractionType.Banker))
            assert.is_nil(ns.Economy.ruleForInteraction(nil))
        end)

        it("maps nothing when the client has no interaction enum", function()
            _G.Enum = nil
            assert.is_nil(ns.Economy.ruleForInteraction(21))
        end)
    end)

    describe("interaction warnings", function()
        it("warns for each forbidden window and for no allowed one", function()
            link(0)
            economy().auctionHouse, economy().trading, economy().mail = true, true, false
            economy().sharedBanks = false
            for name, forbidden in pairs({ Auctioneer = false, TradePartner = false, MailInfo = true,
                                           GuildBanker = true, AccountBanker = true, Merchant = false }) do
                game.chat, game.uiErrors = {}, {}
                interact(name)
                assert.equals(forbidden and 1 or 0, #game.uiErrors, name)
                assert.equals(forbidden and 1 or 0, #chat(), name)
            end
        end)

        it("names the forbidden rule and shows it on screen and in chat", function()
            link(0)
            economy().auctionHouse = false
            interact("Auctioneer")
            local text = ns.L.ECONOMY_WARNING:format(ns.L.RULE_AUCTION_HOUSE)
            assert.equals(text, game.uiErrors[1].text)
            assert.same({ 1, 0.1, 0.1, 1 }, game.uiErrors[1].color)
            assert.same({ text }, chat())
        end)

        it("treats the guild bank and the account bank as one rule", function()
            link(0)
            economy().sharedBanks = true
            interact("GuildBanker")
            interact("AccountBanker")
            assert.same({}, game.uiErrors)
            economy().sharedBanks = false
            interact("GuildBanker")
            interact("AccountBanker")
            assert.equals(2, #game.uiErrors)
            assert.equals(ns.L.ECONOMY_WARNING:format(ns.L.RULE_SHARED_BANKS), game.uiErrors[2].text)
        end)

        it("adds the care package hint for mail only while packages are left", function()
            link(2)
            interact("MailInfo")
            assert.equals(ns.L.ECONOMY_WARNING:format(ns.L.RULE_MAIL), game.uiErrors[1].text) -- no hint on screen
            local warning = ns.L.ECONOMY_WARNING:format(ns.L.RULE_MAIL)
            assert.equals(warning .. " " .. ns.L.CARE_MAIL_HINT:format(2), chat()[1])
            ns.DB.addCarePackageUse(db, SLOT)
            ns.DB.addCarePackageUse(db, SLOT)
            game.chat = {}
            interact("MailInfo")
            assert.same({ ns.L.ECONOMY_WARNING:format(ns.L.RULE_MAIL) }, chat())
        end)

        it("does not add the care package hint to other rules", function()
            link(3)
            economy().trading = false
            interact("TradePartner")
            assert.same({ ns.L.ECONOMY_WARNING:format(ns.L.RULE_TRADING) }, chat())
        end)

        it("stays silent for characters that are not linked, before login and without a slot", function()
            _G.WoWForeverAP_Inbox = Env.inbox()
            interact("MailInfo") -- not linked
            db.characters[game.guid].slotKey = "S9:Gone"
            interact("MailInfo") -- slot missing in the inbox
            db.characters[game.guid].slotKey = SLOT
            ns.ready = false
            interact("MailInfo")
            assert.same({}, game.uiErrors)
            assert.same({}, chat())
        end)

        it("stays silent when the seed has no economy table", function()
            link(0)
            WoWForeverAP_Inbox.slots[SLOT].options.economy = nil
            interact("MailInfo")
            assert.same({}, chat())
        end)

        it("still prints to chat when the game has no UIErrorsFrame", function()
            link(0)
            _G.UIErrorsFrame = nil
            interact("MailInfo")
            assert.equals(1, #chat())
        end)

        it("shows a localised warning", function()
            link(0)
            ns.Locale.setActive("deDE")
            interact("MailInfo")
            assert.equals(ns.locales.deDE.ECONOMY_WARNING:format(ns.locales.deDE.RULE_MAIL), game.uiErrors[1].text)
        end)
    end)

    describe("event registration", function()
        it("uses the interaction manager event when the enum and the event exist", function()
            assert.same({ "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }, ns.Economy.register())
            _G.C_EventUtils = { IsEventValid = function() return true end }
            assert.is_true(ns.Economy.hasInteractionManager())
        end)

        it("falls back to the window events when the enum is missing", function()
            _G.Enum = nil
            assert.is_false(ns.Economy.hasInteractionManager())
            assert.same({ "AUCTION_HOUSE_SHOW", "GUILDBANKFRAME_OPENED", "MAIL_SHOW", "TRADE_SHOW" },
                ns.Economy.register())
        end)

        it("falls back when the client does not know the interaction event", function()
            _G.C_EventUtils = { IsEventValid = function() return false end }
            assert.is_false(ns.Economy.hasInteractionManager())
            assert.equals(4, #ns.Economy.register())
        end)

        it("skips a window event the client refuses to register", function()
            _G.Enum = nil
            local register = ns.Events.register
            ns.Events.register = function(event, handler)
                if event == "GUILDBANKFRAME_OPENED" then
                    error("unknown event")
                end
                register(event, handler)
            end
            assert.same({ "AUCTION_HOUSE_SHOW", "MAIL_SHOW", "TRADE_SHOW" }, ns.Economy.register())
        end)

        it("warns from the fallback events too", function()
            link(0)
            economy().auctionHouse = false
            _G.Enum = nil
            ns.Economy.register()
            ns.Events.dispatch("AUCTION_HOUSE_SHOW")
            ns.Events.dispatch("TRADE_SHOW") -- trading is allowed
            assert.same({ ns.L.ECONOMY_WARNING:format(ns.L.RULE_AUCTION_HOUSE) }, chat())
        end)
    end)

    describe("care packages", function()
        it("available is received minus used", function()
            link(3)
            local slot = WoWForeverAP_Inbox.slots[SLOT]
            assert.equals(3, ns.Economy.carePackagesAvailable(db, SLOT, slot))
            ns.DB.addCarePackageUse(db, SLOT)
            assert.equals(2, ns.Economy.carePackagesAvailable(db, SLOT, slot))
        end)

        it("never goes below zero, even if more were used than received", function()
            link(1)
            local slot = WoWForeverAP_Inbox.slots[SLOT]
            db.slots[SLOT] = { carePackagesUsed = 4 }
            assert.equals(0, ns.Economy.carePackagesAvailable(db, SLOT, slot))
            link(0)
            assert.equals(0, ns.Economy.carePackagesAvailable(db, SLOT, WoWForeverAP_Inbox.slots[SLOT]))
        end)

        it("only counts care packages, not other items", function()
            link(1)
            local slot = WoWForeverAP_Inbox.slots[SLOT]
            slot.items[#slot.items + 1] = { id = ns.Ids.itemId(ns.Ids.ItemCat.FILLER, 1), sender = "Ben", loc = 2 }
            assert.equals(1, ns.Economy.carePackagesReceived(slot))
        end)

        it("use spends one and reports how many are left", function()
            link(2)
            local slot = WoWForeverAP_Inbox.slots[SLOT]
            local ok, left = ns.Economy.useCarePackage(db, SLOT, slot)
            assert.is_true(ok)
            assert.equals(1, left)
            assert.equals(1, ns.DB.carePackagesUsed(db, SLOT))
        end)

        it("use with none available refuses and changes nothing", function()
            link(0)
            local ok = ns.Economy.useCarePackage(db, SLOT, WoWForeverAP_Inbox.slots[SLOT])
            assert.is_false(ok)
            assert.equals(0, ns.DB.carePackagesUsed(db, SLOT))
            link(1)
            ns.Economy.useCarePackage(db, SLOT, WoWForeverAP_Inbox.slots[SLOT])
            ok = ns.Economy.useCarePackage(db, SLOT, WoWForeverAP_Inbox.slots[SLOT])
            assert.is_false(ok)
            assert.equals(1, ns.DB.carePackagesUsed(db, SLOT))
        end)

        it("treats a damaged counter as zero", function()
            for _, bad in ipairs({ "x", -3, true }) do
                db.slots[SLOT] = { carePackagesUsed = bad }
                assert.equals(0, ns.DB.carePackagesUsed(db, SLOT))
            end
            assert.equals(0, ns.DB.carePackagesUsed(db, "S2:None"))
        end)

        it("keeps the counter per slot and in the SavedVariables slot table", function()
            ns.DB.addCarePackageUse(db, SLOT)
            ns.DB.addCarePackageUse(db, SLOT)
            assert.equals(2, db.slots[SLOT].carePackagesUsed)
            assert.equals(0, ns.DB.carePackagesUsed(db, "S2:Other"))
        end)

        it("does not disturb the outbox", function()
            ns.DB.addCheck(db, SLOT, 5, game.guid, 1)
            ns.DB.addCarePackageUse(db, SLOT)
            assert.is_true(ns.DB.hasCheck(db, SLOT, 5))
            assert.equals(1, #db.slots[SLOT].outbox)
        end)
    end)

    describe("/wfap rules", function()
        it("lists every rule and the care package terms", function()
            link(0)
            ns.Commands.run("rules")
            assert.same({
                ns.L.RULES_HEADER,
                ns.L.RULES_LINE:format(ns.L.RULE_AUCTION_HOUSE, ns.L.RULES_ALLOWED),
                ns.L.RULES_LINE:format(ns.L.RULE_TRADING, ns.L.RULES_ALLOWED),
                ns.L.RULES_LINE:format(ns.L.RULE_MAIL, ns.L.RULES_FORBIDDEN),
                ns.L.RULES_LINE:format(ns.L.RULE_SHARED_BANKS, ns.L.RULES_FORBIDDEN),
                ns.L.RULES_LINE:format(ns.L.RULE_MAIN_BOOSTS, ns.L.RULES_FORBIDDEN),
                ns.L.RULES_CARE:format(50, 5),
            }, chat())
        end)

        it("needs a linked character and a slot in the inbox", function()
            ns.Commands.run("rules")
            db.characters[game.guid].slotKey = "S9:Gone"
            ns.Commands.run("rules")
            assert.same({ ns.L.NOT_LINKED, ns.L.SLOT_MISSING:format("S9:Gone") }, chat())
        end)

        it("says so when the slot has no economy table", function()
            link(0)
            WoWForeverAP_Inbox.slots[SLOT].options.economy = nil
            ns.Commands.run("rules")
            assert.same({ ns.L.RULES_MISSING }, chat())
        end)
    end)

    describe("/wfap care", function()
        it("shows available, received and used", function()
            link(3)
            ns.DB.addCarePackageUse(db, SLOT)
            ns.Commands.run("care")
            assert.same({ ns.L.CARE_STATUS:format(2, 3, 1) }, chat())
        end)

        it("use asks first and spends nothing until the popup is accepted", function()
            link(2)
            ns.Commands.run("care use")
            assert.equals(1, #game.popups)
            assert.equals("WOWFOREVERAP_CARE", game.popups[1].which)
            assert.equals(ns.L.CARE_AMOUNT:format(50, 5), game.popups[1].arg1)
            assert.equals(SLOT, game.popups[1].data.slotKey)
            assert.equals(0, ns.DB.carePackagesUsed(db, SLOT))
            StaticPopupDialogs["WOWFOREVERAP_CARE"].OnAccept(nil, game.popups[1].data)
            assert.equals(1, ns.DB.carePackagesUsed(db, SLOT))
            assert.same({ ns.L.CARE_USED:format(1) }, chat())
        end)

        it("use with none available refuses without a popup", function()
            link(0)
            ns.Commands.run("care use")
            assert.same({}, game.popups)
            assert.same({ ns.L.CARE_NONE }, chat())
            assert.equals(0, ns.DB.carePackagesUsed(db, SLOT))
        end)

        it("accepting twice cannot spend more than was received", function()
            link(1)
            ns.Commands.run("care use")
            local data = game.popups[1].data
            StaticPopupDialogs["WOWFOREVERAP_CARE"].OnAccept(nil, data)
            StaticPopupDialogs["WOWFOREVERAP_CARE"].OnAccept(nil, data)
            assert.equals(1, ns.DB.carePackagesUsed(db, SLOT))
            assert.equals(ns.L.CARE_NONE, chat()[2])
        end)

        it("accepting a popup for a slot that left the inbox does nothing", function()
            link(1)
            ns.Commands.run("care use")
            _G.WoWForeverAP_Inbox = nil
            StaticPopupDialogs["WOWFOREVERAP_CARE"].OnAccept(nil, game.popups[1].data)
            assert.equals(0, ns.DB.carePackagesUsed(db, SLOT))
        end)

        it("needs a linked character", function()
            ns.Commands.run("care")
            ns.Commands.run("care use")
            assert.same({ ns.L.NOT_LINKED, ns.L.NOT_LINKED }, chat())
            assert.same({}, game.popups)
        end)

        it("treats an unknown argument as the status request", function()
            link(1)
            ns.Commands.run("care later")
            assert.same({ ns.L.CARE_STATUS:format(1, 1, 0) }, chat())
        end)
    end)

    describe("received care packages", function()
        it("show up by name in the new-item announcement", function()
            link(1)
            local slot = WoWForeverAP_Inbox.slots[SLOT]
            ns.Notify.newItems(slot, 0)
            assert.equals(ns.L.NEW_ITEMS:format(1), chat()[1])
            assert.equals(ns.L.ITEM_LINE:format("Care Package", "Ben"), chat()[2])
        end)
    end)
end)
