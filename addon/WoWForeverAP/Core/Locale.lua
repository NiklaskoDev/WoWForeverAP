-- Localisation: `ns.L[key]` gives the string of the client's locale, then enUS, then the key itself.
-- Locale files (Locales/*.lua) only fill `ns.locales[<code>]`; lookup is dynamic, so load order does not matter.
local _, ns = ...

local DEFAULT_LOCALE = "enUS"

ns.locales = ns.locales or {}

local Locale = {}
ns.Locale = Locale

local override

--- The locale in use: the client's, unless a test or a command forces another one.
function Locale.active()
    return override or GetLocale()
end

--- Force a locale code (nil restores the client's locale).
function Locale.setActive(code)
    override = code
end

local function lookup(code, key)
    local strings = ns.locales[code]
    return strings and strings[key]
end

ns.L = setmetatable({}, {
    __index = function(_, key)
        local value = lookup(Locale.active(), key)
        if value == nil then
            value = lookup(DEFAULT_LOCALE, key)
        end
        if value == nil then
            return key
        end
        return value
    end,
})
