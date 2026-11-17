local Env = require("helpers.addon_env")

describe("Style", function()
    local ns, Style

    before_each(function()
        ns = Env.new()
        Style = ns.Style
    end)

    it("has one accent colour, shared by the chat prefix", function()
        assert.equals("d4a017", Style.ACCENT_HEX)
        assert.equals("d4a017", Style.COLORS.accent.hex)
        assert.matches("|cff" .. Style.ACCENT_HEX, ns.Notify.PREFIX, 1, true)
    end)

    it("defines the state colours of the plan", function()
        local locked, unavailable = Style.COLORS.locked, Style.COLORS.unavailable
        assert.equals("8c2a2a", locked.hex)
        assert.equals(0.35, locked.a)
        assert.is_true(math.abs(locked.r - 0x8C / 255) < 1e-9)
        assert.equals("000000", unavailable.hex)
        assert.equals(0.55, unavailable.a)
        assert.equals("9d9d9d", Style.COLORS.checked.hex)
    end)

    it("tints locked and unavailable zones and leaves the others alone", function()
        assert.equals(Style.COLORS.locked, Style.stateTint("locked"))
        assert.equals(Style.COLORS.unavailable, Style.stateTint("unavailable"))
        assert.is_nil(Style.stateTint("unlocked"))
        assert.is_nil(Style.stateTint("start"))
        assert.is_nil(Style.stateTint(nil))
    end)

    it("gives every zone state a text label, so colour is never the only signal", function()
        for state in pairs(ns.Checks.STATE_RANK) do
            local key = Style.STATE_LABEL_KEYS[state]
            assert.is_string(key, state)
            assert.not_equals(key, ns.L[key], state) -- the key exists in the locale
        end
    end)

    it("uses four font objects, the 4/8/12/16/24 spacing scale, 20 px rows and a 420 x 520 window", function()
        assert.same({ title = "GameFontNormalLarge", header = "GameFontNormal", row = "GameFontHighlight",
                      meta = "GameFontHighlightSmall" }, Style.FONTS)
        assert.same({ xs = 4, sm = 8, md = 12, lg = 16, xl = 24 }, Style.SPACING)
        assert.equals(20, Style.ROW_HEIGHT)
        assert.same({ width = 420, height = 520 }, Style.WINDOW)
    end)

    it("wraps text in a colour escape", function()
        assert.equals("|cffd4a017Hi|r", Style.colorize("Hi", Style.COLORS.accent))
    end)

    it("doubles every pipe so text from other players cannot start an escape", function()
        assert.equals("a||cffff0000b||r", Style.escape("a|cffff0000b|r"))
        assert.equals("||||", Style.escape("||"))
        assert.equals("plain", Style.escape("plain"))
        assert.equals("5", Style.escape(5))
    end)
end)
