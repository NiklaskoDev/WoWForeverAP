-- The addon's options in the game's Settings window (Options > AddOns > WoWForeverAP).
-- APIs (checked against the 12.x UI source): Settings.RegisterVerticalLayoutCategory, Settings.RegisterProxySetting,
-- Settings.CreateCheckbox, Settings.RegisterAddOnCategory, Settings.OpenToCategory, Settings.VarType.Boolean.
-- Without them the options simply stay at their defaults (everything on) and /wfap options says so.
local _, ns = ...

local UISettings = {}
ns.UISettings = UISettings -- not named Settings: that is the game's own table

--- The boolean options, in display order: key in `WoWForeverAP_DB.ui`, label and tooltip locale keys.
UISettings.OPTIONS = {
    { key = "mapOverlay", label = "OPT_MAP_OVERLAY", tooltip = "OPT_MAP_OVERLAY_TIP" },
    { key = "zoneWarnings", label = "OPT_WARNINGS", tooltip = "OPT_WARNINGS_TIP" },
}

local category

local function apiPresent()
    return type(Settings) == "table" and type(Settings.VarType) == "table"
        and type(Settings.RegisterVerticalLayoutCategory) == "function"
        and type(Settings.RegisterProxySetting) == "function"
        and type(Settings.CreateCheckbox) == "function"
        and type(Settings.RegisterAddOnCategory) == "function"
        and type(Settings.OpenToCategory) == "function"
end

--- Sets an option and tells what depends on it to redraw.
function UISettings.set(key, value)
    ns.db.ui[key] = value
    if key == "mapOverlay" and ns.MapOverlay then
        ns.MapOverlay.refresh()
    end
end

local function addCheckbox(layoutCategory, option)
    local function getValue()
        return ns.db.ui[option.key]
    end
    local function setValue(value)
        UISettings.set(option.key, value)
    end
    local setting = Settings.RegisterProxySetting(layoutCategory, "WoWForeverAP_" .. option.key,
        Settings.VarType.Boolean, ns.L[option.label], ns.DB.UI_DEFAULTS[option.key], getValue, setValue)
    Settings.CreateCheckbox(layoutCategory, setting, ns.L[option.tooltip])
end

--- Registers the options category. Returns true when it is there; false when the API is missing or refused.
function UISettings.register()
    if category then
        return true
    end
    if not (ns.db and ns.db.ui and apiPresent()) then
        return false
    end
    local ok = pcall(function()
        local created = Settings.RegisterVerticalLayoutCategory(ns.name)
        for _, option in ipairs(UISettings.OPTIONS) do
            addCheckbox(created, option)
        end
        Settings.RegisterAddOnCategory(created)
        category = created
    end)
    return ok and category ~= nil
end

--- Opens the options window at this addon; false when there is no options category.
function UISettings.open()
    if not category then
        return false
    end
    local id = ns.tryCall(category.GetID, category)
    local ok = pcall(Settings.OpenToCategory, id or category)
    return ok
end

ns.Events.register("PLAYER_LOGIN", UISettings.register)
