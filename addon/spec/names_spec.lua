local Env = require("helpers.addon_env")

describe("Names and Notify", function()
    local ns, game

    local function itemId(category, native) return ns.Ids.itemId(category, native) end
    local function locationId(category, native) return ns.Ids.locationId(category, native) end

    before_each(function()
        ns, game = Env.new()
    end)

    describe("zones and professions", function()
        it("uses the game's localised name when the API answers", function()
            _G.C_Map = { GetMapInfo = function(id) return { name = "Wald von Elwynn", mapID = id } end }
            _G.C_TradeSkillUI = {
                GetProfessionInfoBySkillLineID = function() return { professionName = "Alchemie" } end,
            }
            assert.equals("Wald von Elwynn", ns.Names.zone(1429))
            assert.equals("Alchemie", ns.Names.profession(171))
        end)

        it("falls back to the generated English name without the API, on empty answers and on errors", function()
            assert.equals("Elwynn Forest", ns.Names.zone(1429))
            assert.equals("Alchemy", ns.Names.profession(171))
            _G.C_Map = { GetMapInfo = function() return { name = "" } end }
            _G.C_TradeSkillUI = { GetProfessionInfoBySkillLineID = function() error("restricted") end }
            assert.equals("Elwynn Forest", ns.Names.zone(1429))
            assert.equals("Alchemy", ns.Names.profession(171))
        end)

        it("falls back to a numbered label for ids the data does not know", function()
            assert.equals(ns.L.ZONE_FMT:format(999999), ns.Names.zone(999999))
            assert.equals(ns.L.PROFESSION_FMT:format(999999), ns.Names.profession(999999))
        end)
    end)

    describe("quests", function()
        it("uses the quest log title when known, else the numbered label", function()
            assert.equals("Quest 783", ns.Names.quest(783))
            _G.C_QuestLog = { GetTitleForQuestID = function(id) return id == 783 and "A Threat Within" or nil end }
            assert.equals("A Threat Within", ns.Names.quest(783))
            assert.equals("Quest 5", ns.Names.quest(5))
        end)
    end)

    describe("locations", function()
        it("names quest, level and profession locations", function()
            assert.equals("Quest 783", ns.Names.location(locationId(ns.Ids.LocCat.QUEST, 783)))
            assert.equals("Reach Level 12", ns.Names.location(locationId(ns.Ids.LocCat.LEVEL, 12)))
            local native = ns.Ids.professionSkillNative(171, 75)
            assert.equals("Alchemy 75", ns.Names.location(locationId(ns.Ids.LocCat.PROFESSION_SKILL, native)))
        end)

        it("shows other ids as plain numbers", function()
            assert.equals("12", ns.Names.location(12))
            assert.equals("nope", ns.Names.location("nope"))
        end)
    end)

    describe("items", function()
        it("names zone, progressive profession, filler and unknown items", function()
            assert.equals("Zone: Westfall", ns.Names.item(itemId(ns.Ids.ItemCat.ZONE, 1436)))
            assert.equals("Progressive Alchemy (tier 2)", ns.Names.item(itemId(ns.Ids.ItemCat.PROFESSION_TIER, 171), 2))
            assert.equals("Traveler's Tale", ns.Names.item(itemId(ns.Ids.ItemCat.FILLER, 1)))
            assert.equals(ns.L.ITEM_UNKNOWN:format("77"), ns.Names.item(itemId(ns.Ids.ItemCat.FILLER, 77)))
            assert.equals(ns.L.ITEM_UNKNOWN:format("7"), ns.Names.item(7))
        end)

        it("localises the filler item", function()
            game.locale = "deDE"
            assert.equals("Geschichte eines Reisenden", ns.Names.item(itemId(ns.Ids.ItemCat.FILLER, 1)))
        end)

        it("counts the tier of progressive items over the whole list and shows only the asked range", function()
            local alchemy = itemId(ns.Ids.ItemCat.PROFESSION_TIER, 171)
            local received = {
                { id = alchemy, sender = "Anna", loc = 1 },
                { id = itemId(ns.Ids.ItemCat.ZONE, 1436), sender = "Ben", loc = 2 },
                { id = alchemy, sender = "Cleo", loc = 3 },
                { id = alchemy, loc = 4 },
            }
            assert.same({
                "Zone: Westfall (from Ben)",
                "Progressive Alchemy (tier 2) (from Cleo)",
            }, ns.Names.itemLines(received, 2, 3))
            assert.equals("Progressive Alchemy (tier 3) (from ?)", ns.Names.itemLines(received, 4, 99)[1])
        end)
    end)

    describe("Notify", function()
        it("prefixes every line with the gold [AP] tag", function()
            ns.Notify.print("hello")
            assert.equals("|cffd4a017[AP]|r hello", game.chat[1])
        end)

        it("formats localised texts with their arguments", function()
            ns.Notify.say("UNSYNCED", 3)
            game.locale = "deDE"
            ns.Notify.say("UNSYNCED", 3)
            assert.equals(ns.locales.enUS.UNSYNCED:format(3), Env.chatText(game)[1])
            assert.equals(ns.locales.deDE.UNSYNCED:format(3), Env.chatText(game)[2])
        end)

        it("shows the unsynced reminder only when checks are waiting", function()
            ns.Notify.unsynced(0)
            assert.same({}, game.chat)
            ns.Notify.unsynced(2)
            assert.equals("2 checks waiting - /reload or log out to send them", Env.chatText(game)[1])
        end)

        it("lists new items, at most five lines, and points to /wfap items for the rest", function()
            local items = {}
            for index = 1, 8 do
                items[index] = { id = itemId(ns.Ids.ItemCat.ZONE, 1429), sender = "P" .. index, loc = index }
            end
            ns.Notify.newItems({ items = items }, 1)
            local chat = Env.chatText(game)
            assert.equals(ns.L.NEW_ITEMS:format(7), chat[1])
            assert.equals(5 + 2, #chat)
            assert.equals("Zone: Elwynn Forest (from P2)", chat[2])
            assert.equals(ns.L.MORE_ITEMS:format(2), chat[7])
        end)

        it("says nothing when no item is new", function()
            ns.Notify.newItems({ items = { { id = 1 } } }, 1)
            assert.same({}, game.chat)
        end)
    end)
end)
