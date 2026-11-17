local Env = require("helpers.addon_env")

describe("UISettings", function()
    local ns, game, db, calls

    --- A fake of the game's Settings API that records what the addon registers.
    local function installSettings()
        calls = { checkboxes = {}, opened = {} }
        _G.Settings = {
            VarType = { Boolean = "boolean" },
            RegisterVerticalLayoutCategory = function(name)
                calls.categoryName = name
                return { GetID = function() return 77 end }
            end,
            RegisterProxySetting = function(_, variable, varType, name, default, getValue, setValue)
                return { variable = variable, varType = varType, name = name, default = default,
                         get = getValue, set = setValue }
            end,
            CreateCheckbox = function(_, setting, tooltip)
                calls.checkboxes[#calls.checkboxes + 1] = { setting = setting, tooltip = tooltip }
            end,
            RegisterAddOnCategory = function() calls.registered = true end,
            OpenToCategory = function(id) calls.opened[#calls.opened + 1] = id end,
        }
    end

    before_each(function()
        ns, game = Env.new()
        db = ns.DB.init(nil)
        ns.db, ns.ready = db, true
        installSettings()
    end)

    it("registers one checkbox per option under the addon's name", function()
        assert.is_true(ns.UISettings.register())
        assert.equals("WoWForeverAP", calls.categoryName)
        assert.is_true(calls.registered)
        assert.equals(2, #calls.checkboxes)
        local first, second = calls.checkboxes[1], calls.checkboxes[2]
        assert.equals(ns.L.OPT_MAP_OVERLAY, first.setting.name)
        assert.equals(ns.L.OPT_MAP_OVERLAY_TIP, first.tooltip)
        assert.equals(ns.L.OPT_WARNINGS, second.setting.name)
        assert.equals("boolean", first.setting.varType)
        assert.is_true(first.setting.default and second.setting.default)
    end)

    it("reads and writes the options in the saved variables", function()
        ns.UISettings.register()
        local overlay = calls.checkboxes[1].setting
        assert.is_true(overlay.get())
        overlay.set(false)
        assert.is_false(db.ui.mapOverlay)
        assert.is_false(overlay.get())
        calls.checkboxes[2].setting.set(false)
        assert.is_false(db.ui.zoneWarnings)
    end)

    it("redraws the map overlay when that option changes, and only then", function()
        local refreshed = 0
        ns.MapOverlay = { refresh = function() refreshed = refreshed + 1 end }
        ns.UISettings.register()
        calls.checkboxes[1].setting.set(false)
        calls.checkboxes[2].setting.set(false)
        assert.equals(1, refreshed)
    end)

    it("registers once, even when asked again", function()
        ns.UISettings.register()
        assert.is_true(ns.UISettings.register())
        assert.equals(2, #calls.checkboxes)
    end)

    it("registers at login", function()
        ns.Events.dispatch("PLAYER_LOGIN")
        assert.is_true(calls.registered)
    end)

    it("opens the options at the addon's category", function()
        ns.UISettings.register()
        assert.is_true(ns.UISettings.open())
        assert.same({ 77 }, calls.opened)
    end)

    it("does nothing without the Settings API and says so for /wfap options", function()
        _G.Settings = nil
        assert.is_false(ns.UISettings.register())
        assert.is_false(ns.UISettings.open())
        ns.Commands.run("options")
        assert.same({ ns.L.OPTIONS_UNAVAILABLE }, Env.chatText(game))
        assert.same({}, game.errors)
    end)

    it("does nothing for a Settings table missing one of the functions it needs", function()
        _G.Settings.CreateCheckbox = nil
        assert.is_false(ns.UISettings.register())
    end)

    it("survives an API that raises, and tries again later", function()
        _G.Settings.RegisterProxySetting = function() error("changed in a patch") end
        assert.is_false(ns.UISettings.register())
        assert.is_false(ns.UISettings.open())
        installSettings()
        assert.is_true(ns.UISettings.register())
    end)

    it("does nothing while the saved variables are unusable", function()
        ns.db = nil
        assert.is_false(ns.UISettings.register())
    end)
end)
