-- Design tokens of the addon's windows (plan 003): one accent colour, state colours, a four-size type scale and a
-- spacing scale. Blizzard's own templates and font objects carry everything else, so the addon looks like the game.
-- Pure: no game API.
local _, ns = ...

local Style = {}
ns.Style = Style

local function color(hex, alpha)
    local red, green, blue = hex:match("^(%x%x)(%x%x)(%x%x)$")
    return {
        r = tonumber(red, 16) / 255, g = tonumber(green, 16) / 255, b = tonumber(blue, 16) / 255,
        a = alpha or 1, hex = hex:lower(),
    }
end

Style.ACCENT_HEX = "d4a017" -- chat prefix, window headers

Style.COLORS = {
    accent = color("D4A017"),
    locked = color("8C2A2A", 0.45), -- map fill of a locked zone: red = "you will get it"; one layer, so it reads alone
    unavailable = color("141414", 0.65), -- map fill of a zone outside the seed: colourless dark = "not in this game"
    unavailableBanner = color("141414"), -- background of the "Not in your seed" banner (alpha: BANNER_ALPHA)
    checked = color("9D9D9D"), -- text of something already done
    text = color("FFFFFF"), -- text of an open row (GameFontHighlight's own colour)
}

-- The four sizes in use; every text in the windows picks one of these font objects.
Style.FONTS = {
    title = "GameFontNormalLarge",
    header = "GameFontNormal",
    row = "GameFontHighlight",
    meta = "GameFontHighlightSmall",
}

Style.BANNER_ALPHA = 0.85 -- the banner on a zone map is more opaque than the map tint, so its text reads

Style.SPACING = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 }
Style.ROW_HEIGHT = 20
Style.WINDOW = { width = 420, height = 520 }

--- Locale keys of the text label every zone state carries, so no state is shown by colour alone.
Style.STATE_LABEL_KEYS = {
    start = "STATE_START",
    unlocked = "STATE_UNLOCKED",
    locked = "STATE_LOCKED",
    unavailable = "STATE_UNAVAILABLE",
}

--- Map tint of a zone state: a colour for locked and unavailable zones, nothing for the others.
function Style.stateTint(state)
    if state == "locked" then
        return Style.COLORS.locked
    elseif state == "unavailable" then
        return Style.COLORS.unavailable
    end
    return nil
end

--- Wraps `text` in a colour escape.
function Style.colorize(text, tone)
    return ("|cff%s%s|r"):format(tone.hex, text)
end

--- Makes text from another player safe to show: "|" starts a colour, link or texture escape in the game's text
--- widgets, so each one is doubled and renders as itself.
function Style.escape(text)
    return (tostring(text):gsub("|", "||"))
end
