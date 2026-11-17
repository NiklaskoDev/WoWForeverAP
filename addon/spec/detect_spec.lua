local Env = require("helpers.addon_env")

describe("Detection", function()
    local ns, game, db

    local function levelId(level) return ns.Ids.locationId(ns.Ids.LocCat.LEVEL, level) end
    local function questId(quest) return ns.Ids.locationId(ns.Ids.LocCat.QUEST, quest) end
    local function skillId(line, skill)
        return ns.Ids.locationId(ns.Ids.LocCat.PROFESSION_SKILL, ns.Ids.professionSkillNative(line, skill))
    end

    local function outboxIds()
        local found = {}
        local slot = db.slots["S1:Wow"]
        for _, entry in ipairs(slot and slot.outbox or {}) do
            found[#found + 1] = entry.id
        end
        return found
    end

    --- A logged-in, linked character (linked at `linkedLevel`) and an inbox whose seed holds `locations`.
    local function linkedCharacter(locations, linkedLevel, skillAtLink)
        local set = {}
        for _, id in ipairs(locations) do
            set[id] = true
        end
        _G.WoWForeverAP_Inbox = Env.inbox({ locations = set })
        local character = ns.DB.touchCharacter(db, game.guid, "Arthas", "Alliance", "PALADIN")
        character.slotKey, character.linkedLevel, character.skillAtLink = "S1:Wow", linkedLevel or 1, skillAtLink or {}
    end

    before_each(function()
        ns, game = Env.new()
        db = ns.DB.init(nil)
        ns.db, ns.ready = db, true
    end)

    describe("tryRegister", function()
        it("registers an event and answers true, also when the client cannot tell whether it is valid", function()
            assert.is_true(ns.Events.tryRegister("SOME_EVENT", function() end))
            assert.is_true(game.frames[1].events.SOME_EVENT)
            _G.C_EventUtils = { IsEventValid = function() return true end }
            assert.is_true(ns.Events.tryRegister("OTHER_EVENT", function() end))
            assert.is_true(game.frames[1].events.OTHER_EVENT)
        end)

        it("skips an event the client calls invalid, and an event whose registration fails", function()
            _G.C_EventUtils = { IsEventValid = function() return false end }
            assert.is_false(ns.Events.tryRegister("SOME_EVENT", function() end))
            assert.is_nil(game.frames[1].events.SOME_EVENT)
            _G.C_EventUtils = nil
            game.frames[1].RegisterEvent = function() error("unknown event") end
            assert.is_false(ns.Events.tryRegister("BAD_EVENT", function() end))
        end)

        it("still calls the handler of a registered event", function()
            local got
            ns.Events.tryRegister("SOME_EVENT", function(value) got = value end)
            ns.Events.dispatch("SOME_EVENT", 42)
            assert.equals(42, got)
        end)
    end)

    describe("quests", function()
        it("records a turned-in quest that is in the seed, with chat feedback", function()
            linkedCharacter({ questId(783) })
            ns.Events.dispatch("QUEST_TURNED_IN", 783, 100, 50)
            assert.same({ questId(783) }, outboxIds())
            assert.equals(ns.L.CHECK_RECORDED:format(ns.L.QUEST_FMT:format(783)), Env.chatText(game)[1])
            assert.equals(ns.L.UNSYNCED:format(1), Env.chatText(game)[2])
        end)

        it("ignores a quest that is not in the seed", function()
            linkedCharacter({ questId(783) })
            ns.Events.dispatch("QUEST_TURNED_IN", 999, 0, 0)
            assert.same({}, outboxIds())
            assert.same({}, game.chat)
        end)

        it("ignores a quest the server already checked", function()
            linkedCharacter({ questId(783) })
            WoWForeverAP_Inbox.slots["S1:Wow"].checked[questId(783)] = true
            ns.Events.dispatch("QUEST_TURNED_IN", 783, 0, 0)
            assert.same({}, outboxIds())
        end)

        it("records the same quest only once", function()
            linkedCharacter({ questId(783) })
            ns.Events.dispatch("QUEST_TURNED_IN", 783, 0, 0)
            ns.Events.dispatch("QUEST_TURNED_IN", 783, 0, 0)
            assert.same({ questId(783) }, outboxIds())
            assert.equals(2, #game.chat) -- one check line and one reminder, nothing for the repeat
        end)

        it("does nothing for an unlinked character or before the addon is ready", function()
            linkedCharacter({ questId(783) })
            db.characters[game.guid].slotKey = nil
            ns.Events.dispatch("QUEST_TURNED_IN", 783, 0, 0)
            db.characters[game.guid].slotKey = "S1:Wow"
            ns.ready = false
            ns.Events.dispatch("QUEST_TURNED_IN", 783, 0, 0)
            assert.same({}, outboxIds())
        end)

        it("does nothing when the inbox lacks the character's slot", function()
            linkedCharacter({ questId(783) })
            db.characters[game.guid].slotKey = "S9:Gone"
            ns.Events.dispatch("QUEST_TURNED_IN", 783, 0, 0)
            assert.is_nil(db.slots["S9:Gone"])
        end)

        it("ignores quest ids outside the id scheme", function()
            linkedCharacter({})
            assert.is_nil(ns.Quests.locationId(-5))
            assert.is_nil(ns.Quests.locationId(ns.Ids.CATEGORY_SIZE))
            ns.Events.dispatch("QUEST_TURNED_IN", -5, 0, 0)
            assert.same({}, outboxIds())
        end)
    end)

    describe("levels", function()
        it("lists the milestones passed since linking: level 5 to 8 with step 1 gives 6, 7, 8", function()
            local slot = Env.inbox({ locations = { [levelId(5)] = true, [levelId(6)] = true, [levelId(7)] = true,
                                                   [levelId(8)] = true, [levelId(9)] = true } }).slots["S1:Wow"]
            assert.same({ 6, 7, 8 }, ns.Level.milestones(slot, 5, 8))
        end)

        it("skips levels without a check (step 5) and counts nothing at or below the link level", function()
            local slot = Env.inbox({ locations = { [levelId(6)] = true, [levelId(11)] = true } }).slots["S1:Wow"]
            assert.same({ 11 }, ns.Level.milestones(slot, 6, 12))
            assert.same({}, ns.Level.milestones(slot, 12, 12))
            assert.same({}, ns.Level.milestones(slot, 12, 8))
        end)

        it("records every milestone a level-up passes and ignores the rest", function()
            linkedCharacter({ levelId(6), levelId(7), levelId(8), levelId(9) }, 5)
            ns.Events.dispatch("PLAYER_LEVEL_UP", 8)
            assert.same({ levelId(6), levelId(7), levelId(8) }, outboxIds())
            assert.equals(ns.L.CHECK_RECORDED:format(ns.L.LEVEL_CHECK:format(6)), Env.chatText(game)[1])
        end)

        it("does not count levels reached before linking", function()
            linkedCharacter({ levelId(2), levelId(3), levelId(4) }, 3)
            ns.Events.dispatch("PLAYER_LEVEL_UP", 4)
            assert.same({ levelId(4) }, outboxIds())
        end)

        it("takes the goal level from the slot data and sets the goal once", function()
            linkedCharacter({}, 1)
            WoWForeverAP_Inbox.slots["S1:Wow"].options.goalLevel = 10
            ns.Events.dispatch("PLAYER_LEVEL_UP", 9)
            assert.is_nil(db.slots["S1:Wow"])
            ns.Events.dispatch("PLAYER_LEVEL_UP", 10)
            assert.same({ char = game.guid, t = game.now }, db.slots["S1:Wow"].goal)
            local lines = #game.chat
            ns.Events.dispatch("PLAYER_LEVEL_UP", 11)
            assert.equals(lines, #game.chat) -- the goal is announced once
        end)

        it("falls back to the generated goal level of 60", function()
            local slot = Env.inbox().slots["S1:Wow"]
            slot.options.goalLevel = nil
            assert.equals(60, ns.Level.goalLevel(slot))
        end)

        it("ignores level-ups of unlinked characters", function()
            linkedCharacter({ levelId(2) }, 1)
            db.characters[game.guid].slotKey = nil
            ns.Events.dispatch("PLAYER_LEVEL_UP", 60)
            assert.same({}, outboxIds())
            assert.same({}, db.slots)
        end)
    end)

    describe("professions", function()
        local function fakeApi(professions)
            -- professions: array of { skillLine, rank }; GetProfessions returns indexes, some nil
            _G.GetProfessions = function()
                local indexes = {}
                for index in ipairs(professions) do
                    indexes[index * 2 - 1] = index -- leave a nil between the entries, like an empty slot
                end
                return unpack(indexes, 1, 6)
            end
            _G.GetProfessionInfo = function(index)
                local entry = professions[index]
                return "Name" .. index, "icon", entry[2], 300, 0, 0, entry[1]
            end
        end

        it("reads ranks through GetProfessions and GetProfessionInfo, skipping empty slots", function()
            fakeApi({ { 171, 80 }, { 186, 30 } })
            assert.same({ [171] = 80, [186] = 30 }, ns.Professions.currentRanks())
        end)

        it("reads six return values at most", function()
            local calls = 0
            local ranks = ns.Professions.readRanks(function() return 1, 2, 3, 4, 5, 6, 7 end, function()
                calls = calls + 1
                return "n", "i", 10, 300, 0, 0, 100 + calls
            end)
            assert.equals(6, calls)
            assert.equals(6, (function() local n = 0 for _ in pairs(ranks) do n = n + 1 end return n end)())
        end)

        it("falls back to C_TradeSkillUI.GetProfessionInfoBySkillLineID for the data's professions", function()
            _G.C_TradeSkillUI = { GetProfessionInfoBySkillLineID = function(line)
                if line == 171 then return { skillLevel = 40 } end
                if line == 164 then error("restricted") end
                return { skillLevel = 0 }
            end }
            assert.same({ [171] = 40 }, ns.Professions.currentRanks())
        end)

        it("reports the missing API when neither exists", function()
            local ranks, missing = ns.Professions.currentRanks()
            assert.is_nil(ranks)
            assert.equals("GetProfessions", missing)
        end)

        it("lists the milestones above the link baseline for the slot's professions", function()
            local slot = Env.inbox({ locations = {
                [skillId(171, 25)] = true, [skillId(171, 50)] = true, [skillId(171, 75)] = true,
                [skillId(186, 25)] = true, [skillId(164, 25)] = true,
            } }).slots["S1:Wow"]
            local atLink = { [171] = 25, [186] = 0 }
            local found = ns.Professions.milestones(slot, atLink, { [171] = 60, [186] = 30, [164] = 99 })
            -- 171: 50 only (25 is the baseline, 75 not reached); 186: 25; 164 is not a profession of the slot
            assert.same({ skillId(171, 50), skillId(186, 25) }, found)
        end)

        it("records new milestones on SKILL_LINES_CHANGED and nothing twice", function()
            linkedCharacter({ skillId(171, 25), skillId(171, 50) }, 1, { [171] = 10 })
            fakeApi({ { 171, 30 } })
            ns.Events.dispatch("SKILL_LINES_CHANGED")
            assert.same({ skillId(171, 25) }, outboxIds())
            ns.Events.dispatch("SKILL_LINES_CHANGED")
            assert.same({ skillId(171, 25) }, outboxIds())
            fakeApi({ { 171, 55 } })
            ns.Events.dispatch("SKILL_LINES_CHANGED")
            assert.same({ skillId(171, 25), skillId(171, 50) }, outboxIds())
            assert.equals(ns.L.CHECK_RECORDED:format(ns.L.PROFESSION_CHECK:format("Alchemy", 25)),
                Env.chatText(game)[1])
        end)

        it("counts skill the character already had at linking as not earned", function()
            linkedCharacter({ skillId(171, 25), skillId(171, 50) }, 1, { [171] = 55 })
            fakeApi({ { 171, 55 } })
            ns.Events.dispatch("SKILL_LINES_CHANGED")
            assert.same({}, outboxIds())
        end)

        it("warns once when no profession API exists", function()
            linkedCharacter({ skillId(171, 25) })
            ns.Events.dispatch("SKILL_LINES_CHANGED")
            ns.Events.dispatch("SKILL_LINES_CHANGED")
            assert.same({ ns.L.API_MISSING:format("GetProfessions") }, Env.chatText(game))
        end)
    end)

    describe("event dispatch", function()
        it("registers the events the detection needs on one frame", function()
            local events = {}
            for _, frame in ipairs(game.frames) do
                for event in pairs(frame.events) do
                    events[event] = true
                end
            end
            for _, event in ipairs({ "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "PLAYER_LOGIN",
                                     "ADDON_LOADED" }) do
                assert.is_true(events[event], event)
            end
        end)

        it("passes game events from the frame to the handlers", function()
            linkedCharacter({ questId(783) })
            game.frames[1].scripts.OnEvent(game.frames[1], "QUEST_TURNED_IN", 783, 0, 0)
            assert.same({ questId(783) }, outboxIds())
        end)

        it("keeps running the other handlers when one fails and reports the error", function()
            local ran = false
            ns.Events.register("TEST_EVENT", function() error("boom") end)
            ns.Events.register("TEST_EVENT", function() ran = true end)
            ns.Events.dispatch("TEST_EVENT")
            assert.is_true(ran)
            assert.equals(1, #game.errors)
            assert.matches("boom", game.errors[1])
        end)
    end)
end)
