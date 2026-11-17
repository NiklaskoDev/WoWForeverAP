local Env = require("helpers.addon_env")

describe("Checks", function()
    local ns, Checks

    local ELWYNN, DUROTAR, ALTERAC, DUN_MOROGH, WESTFALL = 1429, 1411, 1416, 1426, 1436
    local ALCHEMY, MINING = 171, 186

    local function zoneItem(uiMapId) return ns.Ids.itemId(ns.Ids.ItemCat.ZONE, uiMapId) end
    local function tierItem(skillLine) return ns.Ids.itemId(ns.Ids.ItemCat.PROFESSION_TIER, skillLine) end
    local function questLocation(quest) return ns.Ids.locationId(ns.Ids.LocCat.QUEST, quest) end
    local function levelLocation(level) return ns.Ids.locationId(ns.Ids.LocCat.LEVEL, level) end
    local function skillLocation(skillLine, skill)
        return ns.Ids.locationId(ns.Ids.LocCat.PROFESSION_SKILL, ns.Ids.professionSkillNative(skillLine, skill))
    end

    --- The inbox slot of an Alliance seed that starts in Elwynn Forest, with `items` as list of item ids.
    local function slot(items, extra)
        local received = {}
        for _, id in ipairs(items or {}) do
            received[#received + 1] = { id = id, sender = "Ben", loc = 1 }
        end
        local overrides = { items = received }
        for key, value in pairs(extra or {}) do
            overrides[key] = value
        end
        return Env.inbox(overrides).slots["S1:Wow"]
    end

    before_each(function()
        ns = Env.new()
        Checks = ns.Checks
    end)

    describe("zoneState", function()
        it("calls the start zone the start zone, even without an unlock item", function()
            assert.equals("start", Checks.zoneState(slot(), ELWYNN))
        end)

        it("is unlocked once the zone item arrived and locked before", function()
            assert.equals("locked", Checks.zoneState(slot(), DUN_MOROGH))
            assert.equals("unlocked", Checks.zoneState(slot({ zoneItem(DUN_MOROGH) }), DUN_MOROGH))
            assert.equals("locked", Checks.zoneState(slot({ zoneItem(WESTFALL) }), DUN_MOROGH))
        end)

        it("treats zones open to both factions like any other zone", function()
            assert.equals("locked", Checks.zoneState(slot(), ALTERAC))
            assert.equals("unlocked", Checks.zoneState(slot({ zoneItem(ALTERAC) }), ALTERAC))
        end)

        it("marks zones of the other faction unavailable, even when an item for it exists", function()
            assert.equals("unavailable", Checks.zoneState(slot(), DUROTAR))
            assert.equals("unavailable", Checks.zoneState(slot({ zoneItem(DUROTAR) }), DUROTAR))
        end)

        it("compares the faction case-insensitively", function()
            local horde = slot({}, { options = { faction = "HORDE", startZone = DUROTAR, contentRelease = 1 } })
            assert.equals("start", Checks.zoneState(horde, DUROTAR))
            assert.equals("unavailable", Checks.zoneState(horde, ELWYNN))
            assert.equals("locked", Checks.zoneState(horde, 1413)) -- The Barrens
        end)

        it("marks zones of a later content release unavailable", function()
            ns.Data.zones[9001] = { faction = "both", min = 1, max = 5, name = "Later", release = 2 }
            assert.equals("unavailable", Checks.zoneState(slot(), 9001))
            local newer = slot({}, { options = { faction = "alliance", startZone = ELWYNN, contentRelease = 2 } })
            assert.equals("locked", Checks.zoneState(newer, 9001))
        end)

        it("returns nothing for a map the data does not list", function()
            assert.is_nil(Checks.zoneState(slot(), 1453)) -- a city
            assert.is_nil(Checks.zoneState(slot(), 0))
        end)
    end)

    describe("allowedSkill", function()
        it("is 0 while no tier item arrived: the profession is locked", function()
            assert.equals(0, Checks.allowedSkill(slot(), ALCHEMY))
        end)

        it("is the top skill of the highest unlocked tier", function()
            assert.equals(75, Checks.allowedSkill(slot({ tierItem(ALCHEMY) }), ALCHEMY))
            assert.equals(150, Checks.allowedSkill(slot({ tierItem(ALCHEMY), tierItem(ALCHEMY) }), ALCHEMY))
            assert.equals(0, Checks.allowedSkill(slot({ tierItem(MINING) }), ALCHEMY))
        end)

        it("never exceeds the highest tier of the content release", function()
            local items = {}
            for _ = 1, 9 do
                items[#items + 1] = tierItem(ALCHEMY)
            end
            assert.equals(300, Checks.allowedSkill(slot(items), ALCHEMY))
            ns.Data.tiers[#ns.Data.tiers + 1] = { maxSkill = 375, name = "Master", release = 2, requiredLevel = 50 }
            assert.equals(300, Checks.allowedSkill(slot(items), ALCHEMY)) -- release 2 is not in this seed
        end)

        it("is nil for a profession the seed does not include", function()
            assert.is_nil(Checks.allowedSkill(slot(), 333))
            assert.is_nil(Checks.allowedSkill(slot({ tierItem(333) }), 333))
        end)
    end)

    describe("openByZone", function()
        local function slotWithQuests()
            return slot({ zoneItem(DUN_MOROGH) }, {
                locations = {
                    [questLocation(783)] = true, [questLocation(7)] = true, -- Elwynn Forest
                    [questLocation(170)] = true, -- Dun Morogh
                    [questLocation(363)] = true, -- Tirisfal Glades: other faction
                    [levelLocation(5)] = true,
                },
                checked = {},
            })
        end

        it("groups open quests by zone, sorted by state, then level range", function()
            local groups = Checks.openByZone(slotWithQuests())
            local summary = {}
            for _, group in ipairs(groups) do
                summary[#summary + 1] = { group.uiMapId, group.state, group.quests }
            end
            assert.same({
                { ELWYNN, "start", { 7, 783 } },
                { DUN_MOROGH, "unlocked", { 170 } },
                { 1420, "unavailable", { 363 } },
            }, summary)
        end)

        it("excludes checked quests and quests waiting in the outbox", function()
            local current = slotWithQuests()
            current.checked[questLocation(7)] = true
            local groups = Checks.openByZone(current, { [questLocation(170)] = true })
            assert.equals(2, #groups)
            assert.same({ 783 }, groups[1].quests)
            assert.same({ 363 }, groups[2].quests)
        end)

        it("puts locked zones after the unlocked ones", function()
            local current = slot({}, { locations = { [questLocation(170)] = true, [questLocation(783)] = true } })
            local groups = Checks.openByZone(current)
            assert.equals(ELWYNN, groups[1].uiMapId)
            assert.equals(DUN_MOROGH, groups[2].uiMapId)
            assert.equals("locked", groups[2].state)
        end)

        it("puts quests the data cannot place into a last group without a state", function()
            local current = slot({}, { locations = { [questLocation(999999)] = true, [questLocation(783)] = true } })
            local groups = Checks.openByZone(current)
            assert.equals(2, #groups)
            assert.equals(Checks.UNKNOWN_ZONE, groups[2].uiMapId)
            assert.is_nil(groups[2].state)
            assert.same({ 999999 }, groups[2].quests)
        end)

        it("is empty for a slot without locations, with garbage ids and with everything checked", function()
            assert.same({}, Checks.openByZone(slot()))
            assert.same({}, Checks.openByZone({}))
            assert.same({}, Checks.openByZone(slot({}, { locations = { [5] = true, text = true } })))
            local current = slotWithQuests()
            for locationId in pairs(current.locations) do
                current.checked[locationId] = true
            end
            assert.same({}, Checks.openByZone(current))
        end)
    end)

    describe("openCharacter", function()
        it("lists open level and profession milestones, ascending, per profession", function()
            local current = slot({}, {
                locations = {
                    [levelLocation(10)] = true, [levelLocation(5)] = true,
                    [skillLocation(ALCHEMY, 50)] = true, [skillLocation(ALCHEMY, 25)] = true,
                    [skillLocation(MINING, 25)] = true, [questLocation(7)] = true,
                },
                checked = { [levelLocation(5)] = true },
            })
            assert.same({
                levels = { 10 },
                professions = { [ALCHEMY] = { 25, 50 }, [MINING] = { 25 } },
            }, Checks.openCharacter(current))
        end)

        it("skips milestones waiting in the outbox", function()
            local current = slot({}, { locations = { [levelLocation(5)] = true, [levelLocation(6)] = true } })
            assert.same({ levels = { 6 }, professions = {} },
                Checks.openCharacter(current, { [levelLocation(5)] = true }))
        end)

        it("is empty for an empty slot", function()
            assert.same({ levels = {}, professions = {} }, Checks.openCharacter({}))
        end)
    end)
end)
