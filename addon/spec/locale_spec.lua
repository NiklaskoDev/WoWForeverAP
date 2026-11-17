local Env = require("helpers.addon_env")

--- Conversion letters of the format specifiers of a string, in order ("%d new %s" -> "ds").
local function specifiers(text)
    local letters = {}
    for letter in text:gsub("%%%%", ""):gmatch("%%[%-%d%.]*(%a)") do
        letters[#letters + 1] = letter
    end
    return table.concat(letters)
end

describe("Locale", function()
    local ns, game

    before_each(function()
        ns, game = Env.new()
    end)

    it("uses the client's locale when the key exists there", function()
        game.locale = "deDE"
        assert.equals(ns.locales.deDE.LINK_YES, ns.L.LINK_YES)
        assert.not_equals(ns.locales.enUS.LINK_YES, ns.L.LINK_YES)
    end)

    it("falls back to enUS for a key missing in deDE", function()
        game.locale = "deDE"
        ns.locales.deDE.HELP_HEADER = nil
        assert.equals(ns.locales.enUS.HELP_HEADER, ns.L.HELP_HEADER)
    end)

    it("falls back to enUS for a locale without a file", function()
        game.locale = "frFR"
        assert.equals(ns.locales.enUS.LINK_YES, ns.L.LINK_YES)
    end)

    it("returns the key itself when no locale has it", function()
        assert.equals("NO_SUCH_KEY", ns.L.NO_SUCH_KEY)
    end)

    it("can be forced to another locale and back", function()
        ns.Locale.setActive("deDE")
        assert.equals(ns.locales.deDE.LINK_YES, ns.L.LINK_YES)
        ns.Locale.setActive(nil)
        assert.equals(ns.locales.enUS.LINK_YES, ns.L.LINK_YES)
    end)

    it("has every deDE key in enUS", function()
        for key in pairs(ns.locales.deDE) do
            assert.is_not_nil(ns.locales.enUS[key], "deDE key without an enUS string: " .. key)
        end
    end)

    it("translates every enUS key into deDE", function()
        for key in pairs(ns.locales.enUS) do
            assert.is_not_nil(ns.locales.deDE[key], "enUS key without a deDE string: " .. key)
        end
    end)

    it("keeps the same format specifiers in both languages, so :format never fails", function()
        for key, english in pairs(ns.locales.enUS) do
            assert.equals(specifiers(english), specifiers(ns.locales.deDE[key]), key)
        end
    end)
end)
