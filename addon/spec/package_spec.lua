local Env = require("helpers.addon_env")

local function readFile(path)
    local handle = assert(io.open(path, "rb"))
    local text = handle:read("*a")
    handle:close()
    return text
end

local function exists(path)
    local handle = io.open(path, "rb")
    if handle then
        handle:close()
    end
    return handle ~= nil
end

describe("Addon package", function()
    local mainToc = Env.ADDON_DIR .. "WoWForeverAP.toc"
    local inboxToc = Env.INBOX_ADDON_DIR .. "WoWForeverAP_Inbox.toc"

    it("lists only files that exist, and every Lua file of the addon", function()
        local listed = {}
        for _, file in ipairs(Env.tocFiles(mainToc)) do
            assert.is_true(exists(Env.ADDON_DIR .. file), file)
            listed[file] = true
        end
        local find = io.popen('cd "' .. Env.ADDON_DIR .. '" && find . -name "*.lua" | sed "s|^\\./||" | sort')
        for file in find:lines() do
            assert.is_true(listed[file], "not in the TOC: " .. file)
        end
        find:close()
    end)

    it("loads Generated.lua before the files that read it", function()
        local order = {}
        for index, file in ipairs(Env.tocFiles(mainToc)) do
            order[file] = index
        end
        assert.is_true(order["Data/Generated.lua"] < order["Core/Names.lua"])
        assert.is_true(order["Core/Ids.lua"] < order["Detect/Quests.lua"])
        assert.is_true(order["Main.lua"] == #Env.tocFiles(mainToc))
    end)

    it("declares interface versions, version placeholder, saved variable and inbox dependency", function()
        local toc = readFile(mainToc)
        assert.matches("## Interface: 16001\n", toc, 1, true)
        assert.matches("## Version: @version@", toc, 1, true)
        assert.matches("## SavedVariables: WoWForeverAP_DB", toc, 1, true)
        assert.matches("## Dependencies: WoWForeverAP_Inbox", toc, 1, true)
        assert.matches("## AddonCompartmentFunc: WoWForeverAP_OnCompartmentClick", toc, 1, true)
        local inbox = readFile(inboxToc)
        assert.matches("## Interface: 16001\n", inbox, 1, true)
        assert.matches("## Version: @version@", inbox, 1, true)
    end)

    it("ships a placeholder inbox the addon accepts", function()
        local ns = Env.new()
        dofile(Env.INBOX_ADDON_DIR .. "Inbox.lua")
        assert.is_true(ns.Inbox.validate(ns.Inbox.current()))
        assert.same({}, ns.Inbox.slotKeys(ns.Inbox.current()))
    end)

    it("loads every file in TOC order without errors and registers the slash command", function()
        Env.new()
        assert.equals("/wfap", SLASH_WFAP1)
        assert.is_function(SlashCmdList["WFAP"])
        assert.is_function(WoWForeverAP_OnCompartmentClick)
    end)

    describe("generated data", function()
        local Data

        before_each(function()
            Data = Env.new().Data
        end)

        it("has the level goal and non-empty tables", function()
            assert.equals(60, Data.levelGoal)
            for _, name in ipairs({ "zones", "quests", "professions", "tiers", "fillers" }) do
                assert.is_true(next(Data[name]) ~= nil, name)
            end
        end)

        it("places every quest in a known zone", function()
            for questId, zoneId in pairs(Data.quests) do
                assert.is_not_nil(Data.zones[zoneId], "quest " .. questId)
            end
        end)

        it("keeps zone level ranges ordered", function()
            for zoneId, zone in pairs(Data.zones) do
                assert.is_true(zone.min <= zone.max, tostring(zoneId))
            end
        end)
    end)
end)
