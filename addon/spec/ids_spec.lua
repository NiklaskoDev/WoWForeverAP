local Env = require("helpers.addon_env")
local fixture = dofile(Env.SPEC_DIR .. "fixtures/ids.lua")

describe("Ids", function()
    local Ids

    before_each(function()
        local ns = Env.new({ "Core/Namespace.lua", "Core/Ids.lua" })
        Ids = ns.Ids
    end)

    it("uses the same constants as ids.py", function()
        assert.equals(fixture.constants.base, Ids.BASE)
        assert.equals(fixture.constants.categorySize, Ids.CATEGORY_SIZE)
    end)

    it("gives the same ids as Python for every category and sample native", function()
        assert.is_true(#fixture.cases > 0)
        for _, case in ipairs(fixture.cases) do
            local build = case.kind == "location" and Ids.locationId or Ids.itemId
            assert.equals(case.id, build(case.category, case.native), case.kind .. " " .. case.category)
        end
    end)

    it("builds the profession skill native like Python", function()
        local sample = fixture.constants.professionSkill
        assert.equals(sample.native, Ids.professionSkillNative(sample.skillLineId, sample.skill))
    end)

    it("decodes an id back into category and native", function()
        for _, case in ipairs(fixture.cases) do
            local category, native = Ids.decode(case.id)
            assert.equals(case.category, category)
            assert.equals(case.native, native)
        end
    end)

    it("rejects a native id of -1, of the category size, and a fraction", function()
        assert.has_error(function() Ids.locationId(Ids.LocCat.QUEST, -1) end)
        assert.has_error(function() Ids.locationId(Ids.LocCat.QUEST, Ids.CATEGORY_SIZE) end)
        assert.has_error(function() Ids.itemId(Ids.ItemCat.ZONE, 1.5) end)
        assert.equals(Ids.BASE + Ids.CATEGORY_SIZE + Ids.CATEGORY_SIZE - 1,
            Ids.locationId(Ids.LocCat.QUEST, Ids.CATEGORY_SIZE - 1))
    end)

    it("rejects unknown categories and keeps the location and item category tables apart", function()
        assert.has_error(function() Ids.locationId(99, 1) end)
        assert.has_error(function() Ids.locationId(0, 1) end)
        assert.has_error(function() Ids.locationId(9, 1) end) -- first reserved location category
        assert.has_error(function() Ids.itemId(6, 1) end) -- a location category (reputation) but no item category
        assert.is_number(Ids.locationId(Ids.LocCat.REPUTATION, 1))
    end)

    it("rejects ids below BASE and skills outside 0..999", function()
        assert.has_error(function() Ids.decode(Ids.BASE - 1) end)
        assert.has_error(function() Ids.professionSkillNative(171, 1000) end)
        assert.has_error(function() Ids.professionSkillNative(171, -1) end)
    end)
end)
