local Env = require("helpers.addon_env")

describe("Main", function()
    local ns, game

    local function chat() return Env.chatText(game) end

    local function itemId(native) return ns.Ids.itemId(ns.Ids.ItemCat.ZONE, native) end

    local function addonLoaded()
        ns.Events.dispatch("ADDON_LOADED", "WoWForeverAP")
    end

    local function login()
        ns.Events.dispatch("PLAYER_LOGIN")
    end

    before_each(function()
        ns, game = Env.new()
    end)

    describe("ADDON_LOADED", function()
        it("creates the SavedVariables table on the first run", function()
            addonLoaded()
            assert.equals(1, WoWForeverAP_DB.schema)
            assert.equals(WoWForeverAP_DB, ns.db)
        end)

        it("keeps the loaded SavedVariables and ignores other addons", function()
            _G.WoWForeverAP_DB = { schema = 1, characters = { x = {} }, slots = {} }
            ns.Events.dispatch("ADDON_LOADED", "SomeOtherAddon")
            assert.is_nil(ns.db)
            addonLoaded()
            assert.equals(WoWForeverAP_DB, ns.db)
            assert.is_not_nil(ns.db.characters.x)
        end)
    end)

    describe("PLAYER_LOGIN", function()
        it("records the character and becomes ready", function()
            addonLoaded()
            login()
            assert.is_true(ns.ready)
            local character = ns.db.characters[game.guid]
            assert.equals("Arthas", character.name)
            assert.equals("Alliance", character.faction)
            assert.equals("PALADIN", character.classFile)
        end)

        it("asks to link an unlinked character when the inbox has one slot", function()
            _G.WoWForeverAP_Inbox = Env.inbox()
            addonLoaded()
            login()
            assert.equals(1, #game.popups)
        end)

        it("stays inactive and explains when the saved data is from a newer version", function()
            _G.WoWForeverAP_DB = { schema = 99 }
            addonLoaded()
            login()
            assert.is_nil(ns.ready)
            assert.same({ ns.L.DB_NEWER }, chat())
            assert.equals(99, WoWForeverAP_DB.schema)
        end)

        it("for a linked character prunes confirmed checks and announces new items and unsynced checks", function()
            local confirmed = ns.Ids.locationId(ns.Ids.LocCat.QUEST, 1)
            local waiting = ns.Ids.locationId(ns.Ids.LocCat.QUEST, 2)
            _G.WoWForeverAP_Inbox = Env.inbox({
                locations = { [confirmed] = true, [waiting] = true }, checked = { [confirmed] = true },
                items = { { id = itemId(1436), sender = "Ben", loc = 1 },
                          { id = itemId(1429), sender = "Cleo", loc = 2 } },
            })
            _G.GetProfessions = function() end
            _G.GetProfessionInfo = function() end
            _G.WoWForeverAP_DB = { schema = 1, characters = { [game.guid] = {
                slotKey = "S1:Wow", seenItemCount = 1, linkedLevel = 1, skillAtLink = {} } }, slots = { ["S1:Wow"] = {
                outbox = { { kind = "check", id = confirmed, char = game.guid, t = 1 },
                           { kind = "check", id = waiting, char = game.guid, t = 2 } } } } }
            addonLoaded()
            login()
            assert.same({ waiting }, { ns.db.slots["S1:Wow"].outbox[1].id })
            assert.equals(1, #ns.db.slots["S1:Wow"].outbox)
            assert.equals(2, ns.db.characters[game.guid].seenItemCount)
            assert.same({ ns.L.NEW_ITEMS:format(1), "Zone: Elwynn Forest (from Cleo)", ns.L.UNSYNCED:format(1) },
                chat())
            assert.equals(0, #game.popups)
        end)

        it("tells a linked character when its slot is not in the inbox", function()
            _G.WoWForeverAP_DB = { schema = 1, characters = { [game.guid] = { slotKey = "S9:Gone" } }, slots = {} }
            addonLoaded()
            login()
            assert.same({ ns.L.SLOT_MISSING:format("S9:Gone") }, chat())
        end)

        it("catches up reputation and honorable kills gained while the addon was not running", function()
            local friendly = ns.Ids.locationId(ns.Ids.LocCat.REPUTATION, 725)
            local kills = ns.Ids.locationId(ns.Ids.LocCat.PVP, 1)
            _G.WoWForeverAP_Inbox = Env.inbox({ locations = { [friendly] = true, [kills] = true } })
            _G.WoWForeverAP_DB = { schema = 1, characters = { [game.guid] = {
                slotKey = "S1:Wow", seenItemCount = 0, linkedLevel = 1, skillAtLink = {},
                baselines = { rep = { [72] = 4 }, hk = 10, bgWins = {} } } }, slots = {} }
            _G.C_Reputation = { GetFactionDataByID = function() return { reaction = 5 } end }
            _G.GetPVPLifetimeStats = function() return 150 end
            addonLoaded()
            login()
            local outbox = ns.db.slots["S1:Wow"].outbox
            assert.same({ friendly, kills }, { outbox[1].id, outbox[2].id })
        end)

        it("catches up profession skill gained while the addon was not running", function()
            local milestone = ns.Ids.locationId(ns.Ids.LocCat.PROFESSION_SKILL, ns.Ids.professionSkillNative(171, 25))
            _G.WoWForeverAP_Inbox = Env.inbox({ locations = { [milestone] = true } })
            _G.WoWForeverAP_DB = { schema = 1, characters = { [game.guid] = {
                slotKey = "S1:Wow", seenItemCount = 0, linkedLevel = 1, skillAtLink = { [171] = 0 } } }, slots = {} }
            _G.GetProfessions = function() return 1 end
            _G.GetProfessionInfo = function() return "Alchemy", "icon", 30, 75, 0, 0, 171 end
            addonLoaded()
            login()
            assert.equals(milestone, ns.db.slots["S1:Wow"].outbox[1].id)
        end)
    end)
end)
