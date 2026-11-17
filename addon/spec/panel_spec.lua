local Env = require("helpers.addon_env")

describe("Panel", function()
    local ns, game, db

    local SLOT = "S1:Wow"
    local DUN_MOROGH = 1426

    local function chat() return Env.chatText(game) end
    local function zoneItem(uiMapId) return ns.Ids.itemId(ns.Ids.ItemCat.ZONE, uiMapId) end
    local function tierItem(skillLine) return ns.Ids.itemId(ns.Ids.ItemCat.PROFESSION_TIER, skillLine) end
    local function questLocation(quest) return ns.Ids.locationId(ns.Ids.LocCat.QUEST, quest) end
    local function levelLocation(level) return ns.Ids.locationId(ns.Ids.LocCat.LEVEL, level) end
    local function bossLocation(encounter) return ns.Ids.locationId(ns.Ids.LocCat.BOSS, encounter) end
    local function areaLocation(area) return ns.Ids.locationId(ns.Ids.LocCat.AREA_DISCOVERY, area) end
    local function repLocation(faction, standing)
        return ns.Ids.locationId(ns.Ids.LocCat.REPUTATION, faction * 10 + standing)
    end
    local function pvpLocation(pvpId) return ns.Ids.locationId(ns.Ids.LocCat.PVP, pvpId) end

    local function texts(rows)
        local list = {}
        for _, entry in ipairs(rows) do
            list[#list + 1] = entry.text
        end
        return list
    end

    --- Links the character; `overrides` are inbox slot fields (items, locations, hints, ...).
    local function link(overrides)
        _G.WoWForeverAP_Inbox = Env.inbox(overrides)
        WoWForeverAP_Inbox.written = 1000 - 12 * 60
        db.characters[game.guid].slotKey = SLOT
    end

    local function items(ids)
        local received = {}
        for _, id in ipairs(ids) do
            received[#received + 1] = { id = id, sender = "Ben", loc = 1 }
        end
        return received
    end

    local function rows(tab) return ns.Panel.rows(tab, ns.Panel.snapshot()) end

    before_each(function()
        ns, game = Env.new()
        db = ns.DB.init(nil)
        ns.db, ns.ready = db, true
        ns.DB.touchCharacter(db, game.guid, "Arthas", "Alliance", "PALADIN")
    end)

    describe("state and message", function()
        it("is unlinked until the character has a slot, and missing when the inbox lacks it", function()
            assert.equals("unlinked", ns.Panel.state(ns.Panel.snapshot()))
            link({})
            assert.equals("linked", ns.Panel.state(ns.Panel.snapshot()))
            db.characters[game.guid].slotKey = "other:Slot"
            assert.equals("missing", ns.Panel.state(ns.Panel.snapshot()))
            assert.same({ ns.L.SLOT_MISSING:format("other:Slot") }, ns.Panel.message(ns.Panel.snapshot()).lines)
        end)

        it("tells to start the client when the inbox holds no slot", function()
            local message = ns.Panel.message(ns.Panel.snapshot())
            assert.same({ ns.L.PANEL_NO_INBOX }, message.lines)
            assert.is_nil(message.linkSlotKey)
        end)

        it("offers the link button when exactly one slot exists", function()
            _G.WoWForeverAP_Inbox = Env.inbox()
            local message = ns.Panel.message(ns.Panel.snapshot())
            assert.same({ ns.L.PANEL_UNLINKED }, message.lines)
            assert.equals(SLOT, message.linkSlotKey)
        end)

        it("lists the slots and offers no button when several exist", function()
            _G.WoWForeverAP_Inbox = Env.inbox()
            WoWForeverAP_Inbox.slots["S2:Alt"] = {}
            local message = ns.Panel.message(ns.Panel.snapshot())
            assert.same({ ns.L.PANEL_CHOOSE, "1: S1:Wow", "2: S2:Alt" }, message.lines)
            assert.is_nil(message.linkSlotKey)
        end)
    end)

    describe("header", function()
        it("shows the slot, the waiting checks and the age of the data", function()
            link({})
            db.slots[SLOT] = { outbox = { { kind = "check", id = 5, char = game.guid, t = 1 } } }
            local line1, line2 = ns.Panel.headerLines(ns.Panel.snapshot())
            assert.equals("Slot S1:Wow", line1)
            assert.equals("1 checks waiting for /reload - data from 12 min ago", line2)
        end)

        it("leaves out the waiting checks when there are none and says when the age is unknown", function()
            link({})
            WoWForeverAP_Inbox.written = nil
            local _, line2 = ns.Panel.headerLines(ns.Panel.snapshot())
            assert.equals(ns.L.PANEL_AGE_UNKNOWN, line2)
        end)

        it("does not count checks the server already knows", function()
            link({ checked = { [5] = true } })
            db.slots[SLOT] = { outbox = { { kind = "check", id = 5, char = game.guid, t = 1 } } }
            local _, line2 = ns.Panel.headerLines(ns.Panel.snapshot())
            assert.is_nil(line2:find("waiting", 1, true))
        end)

        it("escapes a slot key that carries a text escape", function()
            link({})
            db.characters[game.guid].slotKey = "S1:Wow"
            local slots = WoWForeverAP_Inbox.slots
            slots["S1:|cffff0000Red|r"], slots[SLOT] = slots[SLOT], nil
            db.characters[game.guid].slotKey = "S1:|cffff0000Red|r"
            assert.equals("Slot S1:||cffff0000Red||r", (ns.Panel.headerLines(ns.Panel.snapshot())))
        end)
    end)

    describe("ageText", function()
        it("uses the largest fitting unit", function()
            local cases = {
                { -5, ns.L.AGE_LESS_THAN_MINUTE }, { 0, ns.L.AGE_LESS_THAN_MINUTE },
                { 59, ns.L.AGE_LESS_THAN_MINUTE }, { 60, "1 min" }, { 3599, "59 min" }, { 3600, "1 h" },
                { 86399, "23 h" }, { 86400, "1 d" }, { 3 * 86400 + 5, "3 d" },
            }
            for _, case in ipairs(cases) do
                assert.equals(case[2], ns.Panel.ageText(case[1]), case[1])
            end
        end)
    end)

    describe("Checks tab", function()
        it("lists open quests per zone, unlocked zones before locked ones, then milestones", function()
            link({
                items = items({ zoneItem(DUN_MOROGH) }),
                locations = {
                    [questLocation(783)] = true, [questLocation(7)] = true, [questLocation(170)] = true,
                    [questLocation(747)] = true, -- Mulgore, the other faction
                    [levelLocation(5)] = true, [levelLocation(6)] = true,
                },
            })
            local listed = texts(rows("checks"))
            assert.same({
                "Elwynn Forest - start zone (2 open)", "Quest 7", "Quest 783",
                "Dun Morogh - unlocked (1 open)", "Quest 170",
                "Mulgore - not in your seed (1 open)", "Quest 747",
                "Character", "Levels: 5, 6",
            }, listed)
        end)

        it("shows the state as text and marks headers and indented rows", function()
            link({ locations = { [questLocation(170)] = true } })
            local result = rows("checks")
            assert.equals("header", result[1].kind)
            assert.equals("Dun Morogh - locked (1 open)", result[1].text)
            assert.equals("row", result[2].kind)
            assert.is_true(result[2].indent)
        end)

        it("uses the quest log's localised title", function()
            _G.C_QuestLog = { GetTitleForQuestID = function() return "Der Wolf" end }
            link({ locations = { [questLocation(7)] = true } })
            assert.equals("Der Wolf", rows("checks")[2].text)
        end)

        it("skips checks that are checked or waiting in the outbox", function()
            link({
                locations = { [questLocation(7)] = true, [questLocation(15)] = true, [questLocation(18)] = true },
                checked = { [questLocation(7)] = true },
            })
            db.slots[SLOT] = { outbox = { { kind = "check", id = questLocation(15), char = game.guid, t = 1 } } }
            assert.same({ "Elwynn Forest - start zone (1 open)", "Quest 18" }, texts(rows("checks")))
        end)

        it("names the next step when nothing is open", function()
            link({})
            local result = rows("checks")
            assert.equals(1, #result)
            assert.equals("empty", result[1].kind)
            assert.equals("No open checks. Play, then /reload to sync.", result[1].text)
        end)

        it("shortens long milestone lists and gives the whole list in the tooltip", function()
            local locations = {}
            for level = 2, 30 do
                locations[levelLocation(level)] = true
            end
            locations[ns.Ids.locationId(ns.Ids.LocCat.PROFESSION_SKILL, ns.Ids.professionSkillNative(171, 25))] = true
            link({ locations = locations })
            local result = rows("checks")
            assert.equals("Levels: 2, 3, 4, 5, 6, 7, 8, 9 (+21 more)", result[2].text)
            assert.matches("^2, 3, 4, ", result[2].tooltip[1])
            assert.matches("30$", result[2].tooltip[1])
            assert.equals("Alchemy: 25", result[3].text)
        end)

        it("escapes quest titles from the game", function()
            _G.C_QuestLog = { GetTitleForQuestID = function() return "|cffff0000Red|r" end }
            link({ locations = { [questLocation(7)] = true } })
            assert.equals("||cffff0000Red||r", rows("checks")[2].text)
        end)

        it("lists bosses one per row and areas as one compact row under their zone, counted as open", function()
            ns.Data.bosses[9001] = { name = "Boss A", instance = "Test Mines", zone = 1436 }
            link({ items = items({ zoneItem(1436) }), locations = {
                [questLocation(783)] = true, [bossLocation(9001)] = true,
                [areaLocation(18)] = true, [areaLocation(57)] = true,
            } })
            assert.same({
                "Elwynn Forest - start zone (3 open)", "Quest 783", "Areas: Crystal Lake, Fargodeep Mine",
                "Westfall - unlocked (1 open)", "Test Mines: Boss A",
            }, texts(rows("checks")))
        end)

        it("shortens a long area list and gives every name in the tooltip", function()
            local locations = {}
            for areaId, area in pairs(ns.Data.areas) do
                if area.zone == 1429 then
                    locations[areaLocation(areaId)] = true
                end
            end
            link({ locations = locations })
            local result = rows("checks")
            assert.matches("^Elwynn Forest %- start zone %(%d+ open%)$", result[1].text)
            assert.matches("^Areas: .+ %(%+%d+ more%)$", result[2].text)
            assert.matches("Crystal Lake", result[2].tooltip[1])
        end)

        it("uses the game's localised area names and escapes them", function()
            _G.C_Map = { GetAreaInfo = function() return "|cffff0000Rot|r" end }
            link({ locations = { [areaLocation(18)] = true } })
            assert.equals("Areas: ||cffff0000Rot||r", rows("checks")[2].text)
        end)

        it("lists reputation per faction and PvP under the character header", function()
            link({ locations = {
                [repLocation(72, 6)] = true, [repLocation(72, 5)] = true, [repLocation(47, 8)] = true,
                [pvpLocation(1)] = true, [pvpLocation(10)] = true,
                [levelLocation(5)] = true,
            } })
            assert.same({
                "Character", "Levels: 5", "Ironforge: Exalted", "Stormwind: Friendly, Honored",
                "PvP: 100 honorable kills, Win Warsong Gulch",
            }, texts(rows("checks")))
        end)

        it("localises standings and uses the game's faction names", function()
            ns.Locale.setActive("deDE")
            _G.C_Reputation = { GetFactionDataByID = function(id) return { name = "Fraktion" .. id } end }
            link({ locations = { [repLocation(72, 8)] = true } })
            assert.equals("Fraktion72: Ehrfürchtig", rows("checks")[2].text)
        end)

        it("puts quests the data cannot place under a last header", function()
            link({ locations = { [questLocation(999999)] = true } })
            assert.same({ ns.L.CHECKS_UNKNOWN_ZONE, "Quest 999999" }, texts(rows("checks")))
        end)
    end)

    describe("Items tab", function()
        it("lists the received items in order with their sender", function()
            link({ items = items({ zoneItem(DUN_MOROGH), tierItem(171), tierItem(171) }) })
            assert.same({
                "Zone: Dun Morogh (from Ben)", "Progressive Alchemy (tier 1) (from Ben)",
                "Progressive Alchemy (tier 2) (from Ben)",
            }, texts(rows("items")))
        end)

        it("names the empty state", function()
            link({})
            assert.same({ ns.L.ITEMS_EMPTY }, texts(rows("items")))
            assert.equals("empty", rows("items")[1].kind)
        end)

        it("shows a sender name with text escapes as plain text", function()
            link({ items = { { id = zoneItem(DUN_MOROGH), sender = "|TInterface\\Icons\\x:0|tEvil", loc = 1 } } })
            assert.equals("Zone: Dun Morogh (from ||TInterface\\Icons\\x:0||tEvil)", rows("items")[1].text)
        end)

        it("lists many items without limit", function()
            local ids = {}
            for _ = 1, 150 do
                ids[#ids + 1] = zoneItem(DUN_MOROGH)
            end
            link({ items = items(ids) })
            assert.equals(150, #rows("items"))
        end)
    end)

    describe("Hints tab", function()
        local function hint(overrides)
            local entry = { item = "Sword", itemId = 900, location = "Chest", finder = "Ben", receiver = "Me",
                            found = false, ourItem = true }
            for key, value in pairs(overrides or {}) do
                entry[key] = value
            end
            return entry
        end

        it("lists hints for the player first, then the others, each under a header", function()
            link({ hints = { hint({ item = "Axe", ourItem = false, finder = "Me", receiver = "Ben" }), hint() } })
            assert.same({
                ns.L.HINTS_OURS, "Sword at Chest (Ben)",
                ns.L.HINTS_OTHERS, "Axe at Chest (Ben)",
            }, texts(rows("hints")))
        end)

        it("greys out found hints and says so in text", function()
            link({ hints = { hint({ found = true }), hint({ item = "Bow" }) } })
            local result = rows("hints")
            assert.equals("Sword at Chest (Ben) - found", result[2].text)
            assert.equals(ns.Style.COLORS.checked, result[2].color)
            assert.is_nil(result[3].color)
        end)

        it("gives the finder and the receiver in the tooltip", function()
            link({ hints = { hint() } })
            assert.same({ "Sword at Chest (Ben)", "Found by: Ben", "For: Me" }, rows("hints")[2].tooltip)
        end)

        it("names the empty state", function()
            link({})
            assert.same({ ns.L.HINTS_EMPTY }, texts(rows("hints")))
            link({ hints = {} })
            assert.same({ ns.L.HINTS_EMPTY }, texts(rows("hints")))
        end)

        it("shows hostile strings as plain text and never uses them as a format", function()
            local hostile = "|cffff0000%s %d|r|Hitem:1|h[x]|h"
            link({ hints = { hint({ item = hostile, location = hostile, finder = hostile, receiver = hostile }) } })
            local result = rows("hints")
            local function lonePipes(text) return (text:gsub("||", "")):find("|", 1, true) end
            assert.is_nil(lonePipes(result[2].text)) -- every "|" is doubled, so none starts an escape
            assert.is_true(result[2].text:find("||cffff0000%s %d||r||Hitem:1||h[x]||h", 1, true) ~= nil)
            for _, line in ipairs(result[2].tooltip) do
                assert.is_nil(lonePipes(line))
            end
        end)

        it("skips entries that are not hints", function()
            link({ hints = { "text", 5, { item = "x" }, hint() } })
            assert.same({ ns.L.HINTS_OURS, "Sword at Chest (Ben)" }, texts(rows("hints")))
        end)
    end)

    describe("Rules tab", function()
        it("shows the honor rules and the economy rules of the slot", function()
            link({ items = items({ ns.Data.carePackageItemId }) })
            db.slots[SLOT] = { carePackagesUsed = 0 }
            local listed = texts(rows("rules"))
            assert.equals(ns.L.RULES_HONOR_HEADER, listed[1])
            assert.equals(ns.L.RULES_HONOR_ZONES, listed[2])
            assert.equals(ns.L.RULES_ECONOMY_HEADER, listed[5])
            assert.equals("Auction House: allowed", listed[6])
            assert.equals("Mail: not allowed", listed[8])
            assert.equals(ns.L.RULES_CARE:format(50, 5), listed[11])
            assert.equals(ns.L.CARE_STATUS:format(1, 1, 0), listed[12])
        end)

        it("says so for a slot from an older apworld without economy rules", function()
            link({})
            WoWForeverAP_Inbox.slots[SLOT].options.economy = nil
            local listed = texts(rows("rules"))
            assert.equals(ns.L.RULES_MISSING, listed[#listed])
        end)

        it("gives the full rule text in the tooltip", function()
            link({})
            assert.same({ ns.L.RULES_HONOR_ZONES }, rows("rules")[2].tooltip)
        end)
    end)

    describe("window", function()
        local function shownRows()
            local provider = ns.Panel.create().List.dataProvider
            return provider and provider.rows
        end

        it("builds on the Blizzard button frame, hides the portrait and closes with Esc", function()
            link({})
            ns.Panel.toggle()
            local frame = ns.Panel.create()
            assert.equals("ButtonFrameTemplate", frame.template)
            assert.equals("WoWForeverAPPanel", frame.name)
            assert.is_true(frame.portraitHidden)
            assert.same({ "WoWForeverAPPanel" }, UISpecialFrames)
            assert.equals(4, frame.numTabs)
            assert.equals(1, frame.selectedTab)
        end)

        it("opens and closes with toggle and builds only once", function()
            link({})
            ns.Panel.toggle()
            assert.is_true(ns.Panel.create():IsShown())
            ns.Panel.toggle()
            assert.is_false(ns.Panel.create():IsShown())
            ns.Panel.toggle()
            assert.same({ "WoWForeverAPPanel" }, UISpecialFrames)
        end)

        it("shows the checks of a linked character and switches tabs", function()
            link({ items = items({ zoneItem(DUN_MOROGH) }), locations = { [questLocation(7)] = true } })
            ns.Panel.toggle()
            assert.same({ "Elwynn Forest - start zone (1 open)", "Quest 7" }, texts(shownRows()))
            ns.Panel.create().TabButtons[2].scripts.OnClick()
            assert.same({ "Zone: Dun Morogh (from Ben)" }, texts(shownRows()))
            assert.equals(2, ns.Panel.create().selectedTab)
            ns.Panel.create().TabButtons[4].scripts.OnClick()
            assert.equals(ns.L.RULES_HONOR_HEADER, shownRows()[1].text)
            local frame = ns.Panel.create()
            assert.equals("Slot S1:Wow", frame.Line1:GetText())
            assert.equals("data from 12 min ago", frame.Line2:GetText())
            assert.is_true(frame.List:IsShown())
            assert.is_false(frame.Message:IsShown())
        end)

        it("shows the link explanation and the link button when the character is not linked", function()
            _G.WoWForeverAP_Inbox = Env.inbox()
            ns.Panel.toggle()
            local frame = ns.Panel.create()
            assert.equals(ns.L.PANEL_UNLINKED, frame.Message:GetText())
            assert.is_true(frame.LinkButton:IsShown())
            assert.is_false(frame.List:IsShown())
            for _, tab in ipairs(frame.TabButtons) do
                assert.is_false(tab:IsShown())
            end
        end)

        it("links the character from the button and then shows the list", function()
            _G.WoWForeverAP_Inbox = Env.inbox({ locations = { [questLocation(7)] = true } })
            ns.Panel.toggle()
            local frame = ns.Panel.create()
            frame.LinkButton.scripts.OnClick()
            assert.equals(SLOT, db.characters[game.guid].slotKey)
            assert.same({ "Elwynn Forest - start zone (1 open)", "Quest 7" }, texts(shownRows()))
            assert.is_false(frame.LinkButton:IsShown())
        end)

        it("shows no button without a slot or with several slots", function()
            ns.Panel.toggle()
            local frame = ns.Panel.create()
            assert.equals(ns.L.PANEL_NO_INBOX, frame.Message:GetText())
            assert.is_false(frame.LinkButton:IsShown())
            _G.WoWForeverAP_Inbox = Env.inbox()
            WoWForeverAP_Inbox.slots["S2:Alt"] = {}
            ns.Panel.toggle()
            ns.Panel.toggle()
            assert.is_false(frame.LinkButton:IsShown())
            assert.matches("^Several slots", frame.Message:GetText())
        end)

        it("saves the position after a drag and restores it in the next session", function()
            link({})
            ns.Panel.toggle()
            local frame = ns.Panel.create()
            frame.points = { { "TOPLEFT", UIParent, "TOPLEFT", 40, -60 } }
            frame.scripts.OnDragStop(frame)
            assert.same({ "TOPLEFT", "TOPLEFT", 40, -60 }, db.ui.panelPoint)
            local ns2 = Env.new()
            ns2.db, ns2.ready = db, true
            local reopened = ns2.Panel.create()
            assert.same({ "TOPLEFT", UIParent, "TOPLEFT", 40, -60 }, reopened.points[1])
        end)

        it("ignores a damaged saved position", function()
            for _, bad in ipairs({ "x", { "TOPLEFT" }, { 1, 2, 3, 4 }, { "A", "B", "c", 1 } }) do
                db.ui.panelPoint = bad
                local fresh = Env.new()
                fresh.db, fresh.ready = db, true
                assert.same({ "CENTER" }, fresh.Panel.create().points[1])
            end
        end)

        it("tells the player in chat when the client lacks a template", function()
            game.missingTemplates.ButtonFrameTemplate = true
            ns.Panel.toggle()
            assert.same({ ns.L.PANEL_UNAVAILABLE }, chat())
            game.missingTemplates.ButtonFrameTemplate = nil
            ns.Panel.toggle()
            assert.is_true(ns.Panel.create():IsShown()) -- a later try works once the template exists
        end)

        it("tells the player when the saved data is from a newer addon", function()
            ns.ready, ns.dbError = false, "DB_NEWER"
            ns.Panel.toggle()
            assert.same({ ns.L.DB_NEWER }, chat())
        end)

        it("does nothing in refresh while closed", function()
            assert.has_no.errors(function() ns.Panel.refresh() end)
        end)
    end)

    describe("rows in the list", function()
        local function listRow(data)
            local button = ns.Panel.create():CreateFontString() -- any frame fake works as the row's button
            button.CreateFontString = ns.Panel.create().CreateFontString
            ns.Panel.create().List.view.initializer(button, data)
            return button
        end

        before_each(function()
            link({})
            ns.Panel.toggle()
        end)

        it("uses one 20 px row height, Blizzard's button element and the four font objects", function()
            local view = ns.Panel.create().List.view
            assert.equals(ns.Style.ROW_HEIGHT, view.extent)
            assert.equals("Button", view.kind)
            local fonts = {}
            for _, kind in ipairs({ "header", "row", "empty" }) do
                fonts[kind] = listRow({ kind = kind, text = "x" }).label.font
            end
            assert.same({ header = "GameFontNormal", row = "GameFontHighlight", empty = "GameFontHighlightSmall" },
                fonts)
        end)

        it("colours headers with the accent, found hints grey and other rows white", function()
            local accent = listRow({ kind = "header", text = "h" }).label.textColor
            assert.is_true(math.abs(accent[1] - 0xD4 / 255) < 1e-6 and math.abs(accent[2] - 0xA0 / 255) < 1e-6
                and math.abs(accent[3] - 0x17 / 255) < 1e-6)
            local grey = listRow({ kind = "row", text = "r", color = ns.Style.COLORS.checked }).label.textColor
            assert.is_true(math.abs(grey[1] - 0x9D / 255) < 1e-6)
            assert.same({ 1, 1, 1 }, listRow({ kind = "row", text = "r" }).label.textColor)
        end)

        it("indents sub rows and shows a tooltip on hover, also for truncated text", function()
            local button = listRow({ kind = "row", text = "Long name", indent = true, tooltip = { "a", "b" } })
            assert.equals(ns.Style.SPACING.lg, button.label.points[1][4])
            button.scripts.OnEnter(button)
            assert.same({ "a", "b" }, game.tooltip.lines)
            assert.is_true(game.tooltip.shown)
            button.scripts.OnLeave(button)
            assert.is_false(game.tooltip.shown)

            game.tooltip.lines = {}
            local plain = listRow({ kind = "row", text = "Short" })
            plain.scripts.OnEnter(plain)
            assert.same({}, game.tooltip.lines) -- fits: no tooltip
            local long = listRow({ kind = "row", text = "A very long name" })
            long.label.truncated = true
            long.scripts.OnEnter(long)
            assert.same({ "A very long name" }, game.tooltip.lines)
        end)
    end)
end)
