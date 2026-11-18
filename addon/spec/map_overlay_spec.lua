local Env = require("helpers.addon_env")

describe("MapOverlay", function()
    local ns, game, db, map, arts

    local SLOT = "S1:Wow"
    local CONTINENT, ELWYNN, DUN_MOROGH, WESTFALL, DUROTAR, CITY = 1415, 1429, 1426, 1436, 1411, 1453
    local ZONE_TYPE

    local function zoneItem(uiMapId) return ns.Ids.itemId(ns.Ids.ItemCat.ZONE, uiMapId) end
    local function questLocation(quest) return ns.Ids.locationId(ns.Ids.LocCat.QUEST, quest) end

    local function link(overrides)
        _G.WoWForeverAP_Inbox = Env.inbox(overrides)
        db.characters[game.guid].slotKey = SLOT
    end

    -- Zone regions of the fake continent (left, right, top, bottom), disjoint like real zone shapes.
    local REGIONS

    local function freshRegions()
        return {
            [ELWYNN] = { 0.50, 0.60, 0.60, 0.70 }, [DUN_MOROGH] = { 0.40, 0.50, 0.50, 0.65 },
            [WESTFALL] = { 0.30, 0.40, 0.80, 0.90 }, [DUROTAR] = { 0.10, 0.20, 0.10, 0.20 },
            [CITY] = { 0.70, 0.80, 0.60, 0.70 },
        }
    end

    --- Fake map API: the zone lookup answers from REGIONS (the continent id outside them); `arts[uiMapId]` is the
    --- list of values GetMapHighlightInfoAtPosition returns inside that zone (nothing when absent).
    local function installMapApi()
        local types = {
            [CONTINENT] = Enum.UIMapType.Continent, [ELWYNN] = ZONE_TYPE, [DUN_MOROGH] = ZONE_TYPE,
            [WESTFALL] = ZONE_TYPE, [DUROTAR] = ZONE_TYPE, [CITY] = ZONE_TYPE,
        }
        local highlights = {}
        local function zoneOn(x, y)
            for id, rect in pairs(REGIONS) do
                if x >= rect[1] and x < rect[2] and y >= rect[3] and y < rect[4] then return id end
            end
            return CONTINENT
        end
        _G.C_Map = {
            GetMapInfo = function(mapId) return types[mapId] and { mapID = mapId, mapType = types[mapId] } end,
            GetMapInfoAtPosition = function(mapId, x, y)
                assert.equals(CONTINENT, mapId)
                return { mapID = zoneOn(x, y) }
            end,
            GetMapHighlightInfoAtPosition = function(mapId, x, y)
                assert.equals(CONTINENT, mapId)
                local art = highlights[zoneOn(x, y)]
                if art then return unpack(art, 1, 8) end
            end,
        }
        return highlights
    end

    --- Fake WorldMapFrame with a 1000 x 500 canvas, a cursor and the mixin the game provides.
    local function installWorldMap()
        local canvas = CreateFrame("Frame")
        canvas:SetSize(1000, 500)
        map = {
            mapId = CONTINENT, canvas = canvas, container = CreateFrame("Frame"), focus = true, cursor = { 0.5, 0.65 },
            providers = {}, updating = {},
        }
        function map:AddDataProvider(provider)
            self.providers[#self.providers + 1] = provider
            provider:OnAdded(self)
        end
        function map:GetCanvas() return self.canvas end
        function map:GetCanvasContainer() return self.container end
        function map:GetMapID() return self.mapId end
        function map:IsCanvasMouseFocus() return self.focus end
        function map:GetNormalizedCursorPosition() return self.cursor[1], self.cursor[2] end
        function map:RegisterDataProviderOnUpdate(provider) self.updating[#self.updating + 1] = provider end
        map.kind, map.shown = "map", true
        _G.WorldMapFrame = setmetatable(map, { __index = CreateFrame("Frame") })
        _G.MapCanvasDataProviderMixin = {
            OnAdded = function(self, owner) self.owningMap = owner end,
            GetMap = function(self) return self.owningMap end,
        }
        _G.CreateFromMixins = function(...)
            local merged = {}
            for _, mixin in ipairs({ ... }) do
                for key, value in pairs(mixin) do merged[key] = value end
            end
            return merged
        end
    end

    local function provider() return map.providers[1] end

    local function install()
        assert.is_true(ns.MapOverlay.install())
        return provider()
    end

    --- The shown textures of the overlay with their colour (strips) or vertex colour (art).
    local function shownTextures()
        local shown = {}
        for _, texture in ipairs(provider().textures or {}) do
            if texture.shown then shown[#shown + 1] = texture end
        end
        return shown
    end

    local function near(expected, actual) return math.abs(expected - actual) < 1e-6 end

    local function slotOf() return ns.Inbox.slot(ns.Inbox.current(), SLOT) end

    local function colorOf(tint) return { tint.r, tint.g, tint.b, tint.a } end

    before_each(function()
        ns, game = Env.new()
        ZONE_TYPE = Enum.UIMapType.Zone
        ns.MapShapes.reset()
        db = ns.DB.init(nil)
        ns.db, ns.ready = db, true
        ns.DB.touchCharacter(db, game.guid, "Arthas", "Alliance", "PALADIN")
        REGIONS = freshRegions()
        arts = installMapApi()
        installWorldMap()
        link({ items = { { id = zoneItem(WESTFALL), sender = "Ben", loc = 1 } },
               locations = { [questLocation(170)] = true, [questLocation(7)] = true, [questLocation(15)] = true } })
    end)

    describe("view", function()
        local function byId() return ns.MapOverlay.view(CONTINENT, slotOf()).zones end

        it("describes every data zone of a continent map with its state, tint, open checks and shape", function()
            local view = ns.MapOverlay.view(CONTINENT, slotOf())
            assert.equals("continent", view.kind)
            local zones = view.zones
            assert.is_nil(zones[CITY]) -- not in the data
            assert.equals("start", zones[ELWYNN].state)
            assert.is_nil(zones[ELWYNN].tint)
            assert.equals(2, zones[ELWYNN].open)
            assert.equals("locked", zones[DUN_MOROGH].state)
            assert.equals(ns.Style.COLORS.locked, zones[DUN_MOROGH].tint)
            assert.equals(1, zones[DUN_MOROGH].open)
            assert.equals("unlocked", zones[WESTFALL].state)
            assert.is_nil(zones[WESTFALL].tint)
            assert.equals(0, zones[WESTFALL].open)
            assert.equals("unavailable", zones[DUROTAR].state)
            assert.equals(ns.Style.COLORS.unavailable, zones[DUROTAR].tint)
            assert.equals(ns.MapShapes.forContinent(CONTINENT)[DUROTAR], zones[DUROTAR].shape)
        end)

        it("shows a zone above the goal level as not in the seed", function()
            slotOf().options.goalLevel = 5 -- Westfall starts at level 10
            local zones = byId()
            assert.equals("unavailable", zones[WESTFALL].state)
            assert.equals(ns.Style.COLORS.unavailable, zones[WESTFALL].tint)
            assert.equals("locked", zones[DUN_MOROGH].state)
        end)

        it("shows the banner on the map of a locked zone and of a zone outside the seed", function()
            assert.same({ kind = "zone", banner = ns.L.MAP_LOCKED_BANNER, tone = "locked" },
                ns.MapOverlay.view(DUN_MOROGH, slotOf()))
            assert.same({ kind = "zone", banner = ns.L.MAP_UNAVAILABLE_BANNER, tone = "unavailable" },
                ns.MapOverlay.view(DUROTAR, slotOf())) -- other faction
            assert.is_nil(ns.MapOverlay.view(ELWYNN, slotOf())) -- start zone
            assert.is_nil(ns.MapOverlay.view(WESTFALL, slotOf())) -- unlocked
        end)

        it("shows nothing for unknown maps, a continent without data zones or a missing API", function()
            assert.is_nil(ns.MapOverlay.view(99999, slotOf()))
            assert.is_nil(ns.MapOverlay.view(nil, slotOf()))
            for id in pairs(REGIONS) do REGIONS[id] = { 5, 6, 5, 6 } end
            assert.is_nil(ns.MapOverlay.view(CONTINENT, slotOf()))
            _G.C_Map = nil
            assert.is_nil(ns.MapOverlay.view(CONTINENT, slotOf()))
            _G.Enum = nil
            assert.is_nil(ns.MapOverlay.view(DUN_MOROGH, slotOf()))
        end)

        it("leaves out checks waiting in the outbox from the open count", function()
            local view = ns.MapOverlay.view(CONTINENT, slotOf(), { [questLocation(7)] = true })
            assert.equals(1, view.zones[ELWYNN].open)
        end)

        it("counts bosses and areas of a zone as open checks next to its quests", function()
            ns.Data.bosses[9001] = { name = "Boss A", instance = "Test Mines", zone = ELWYNN }
            local slot = slotOf()
            slot.locations[ns.Ids.locationId(ns.Ids.LocCat.BOSS, 9001)] = true
            slot.locations[ns.Ids.locationId(ns.Ids.LocCat.AREA_DISCOVERY, 18)] = true
            assert.equals(4, ns.MapOverlay.view(CONTINENT, slot).zones[ELWYNN].open)
        end)

        it("words the tooltip as zone name, state label and open checks", function()
            local zones = byId()
            assert.same({ "Dun Morogh", "locked", "1 open checks" }, ns.MapOverlay.tooltipLines(zones[DUN_MOROGH]))
            assert.same({ "Westfall", "unlocked", "No open checks" }, ns.MapOverlay.tooltipLines(zones[WESTFALL]))
            assert.same({ "Durotar", "not in your seed", "No open checks" }, ns.MapOverlay.tooltipLines(zones[DUROTAR]))
        end)
    end)

    describe("install", function()
        it("adds one data provider to the world map at login, and only once", function()
            ns.Events.dispatch("PLAYER_LOGIN")
            assert.equals(1, #map.providers)
            assert.is_true(ns.MapOverlay.install())
            assert.equals(1, #map.providers)
            assert.equals(1, #map.updating)
        end)

        it("does nothing when the client has no world map data provider code", function()
            _G.MapCanvasDataProviderMixin = nil
            assert.is_false(ns.MapOverlay.install())
            _G.WorldMapFrame = nil
            assert.is_false(ns.MapOverlay.install())
            assert.same({}, game.errors)
        end)

        it("survives AddDataProvider raising an error and tries again later", function()
            map.AddDataProvider = function() error("changed") end
            assert.is_false(ns.MapOverlay.install())
            map.AddDataProvider = nil
            installWorldMap()
            assert.is_true(ns.MapOverlay.install())
        end)

        it("refresh does nothing before the overlay is installed", function()
            assert.has_no.errors(function() ns.MapOverlay.refresh() end)
        end)
    end)

    describe("drawing zone shapes on a continent map", function()
        -- Dun Morogh (locked) and Durotar (unavailable) are the tinted zones; the others stay clear.
        local function strips(zoneId) return ns.MapShapes.forContinent(CONTINENT)[zoneId].runs end

        local function runCount() return #strips(DUN_MOROGH) + #strips(DUROTAR) end

        it("fills with strips where the game has no art: one texture per run, in the state's colour", function()
            install()
            provider():RefreshAllData()
            local shown = shownTextures()
            assert.equals(runCount(), #shown)
            local locked, dark = colorOf(ns.Style.COLORS.locked), colorOf(ns.Style.COLORS.unavailable)
            local counts = { red = 0, dark = 0 }
            for _, texture in ipairs(shown) do
                if texture.color[1] == locked[1] then
                    counts.red = counts.red + 1
                    assert.same(locked, texture.color)
                else
                    counts.dark = counts.dark + 1
                    assert.same(dark, texture.color)
                end
            end
            assert.same({ red = #strips(DUN_MOROGH), dark = #strips(DUROTAR) }, counts)
        end)

        it("places a strip from the run and the canvas size, and re-places it when the canvas changes", function()
            install()
            provider():RefreshAllData()
            local item = provider().items[1] -- zones are drawn in uiMapId order: Durotar first
            local run = strips(DUROTAR)[1]
            assert.equals("run", item.kind)
            local columns, rows = ns.MapShapes.COLUMNS, ns.MapShapes.ROWS
            local function check(width, height)
                local point = item.texture.points[1]
                assert.equals("TOPLEFT", point[1])
                assert.equals(provider().overlay, point[2])
                assert.is_true(near((run[2] - 1) / columns * width, point[4]))
                assert.is_true(near(-(run[1] - 1) / rows * height, point[5]))
                assert.is_true(near((run[3] - run[2] + 1) / columns * width, item.texture.width))
                assert.is_true(near(height / rows, item.texture.height))
            end
            check(1000, 500)
            map.canvas:SetSize(2000, 1000)
            provider():OnCanvasSizeChanged()
            check(2000, 1000)
        end)

        it("draws the zone's art as one desaturated, tinted texture (atlas)", function()
            arts[DUN_MOROGH] = { 0, "MapHighlight-DunMorogh", 1, 1, 0.2, 0.3, 0.1, 0.4 }
            install()
            provider():RefreshAllData()
            local item
            for _, candidate in ipairs(provider().items) do
                if candidate.kind == "atlas" then item = candidate end
            end
            local texture = item.texture
            assert.equals("MapHighlight-DunMorogh", texture.atlas)
            assert.is_true(texture.atlasSize)
            assert.equals("BLEND", texture.blendMode)
            assert.is_true(texture.desaturated)
            assert.same(colorOf(ns.Style.COLORS.locked), texture.vertexColor)
            assert.same({ 0, 1, 0, 1 }, texture.texCoord)
            assert.equals(runCount() - #strips(DUN_MOROGH) + 1, #shownTextures()) -- art replaces the strips
            -- centre of the art: ((0.1 + 0.5 * 0.2) - 0.5) * 1000, -((0.4 + 0.5 * 0.3) - 0.5) * 500
            local point = texture.points[1]
            assert.same({ "CENTER", provider().overlay, "CENTER" }, { point[1], point[2], point[3] })
            assert.is_true(near(-300, point[4]) and near(-25, point[5]))
        end)

        it("draws the zone's art as one desaturated, tinted texture (file) and re-places it", function()
            arts[DUROTAR] = { 12345, nil, 0.5, 0.75, 0.25, 0.5, 0.125, 0.25 }
            install()
            provider():RefreshAllData()
            local item = provider().items[1]
            local texture = item.texture
            assert.equals("file", item.kind)
            assert.equals(12345, texture.texture)
            assert.equals("BLEND", texture.blendMode)
            assert.is_true(texture.desaturated)
            assert.same(colorOf(ns.Style.COLORS.unavailable), texture.vertexColor)
            assert.same({ 0, 0.5, 0, 0.75 }, texture.texCoord)
            assert.same({ "TOPLEFT", provider().overlay, "TOPLEFT", 125, -125 }, texture.points[1])
            assert.same({ 250, 250 }, { texture.width, texture.height })
            map.canvas:SetSize(2000, 1000)
            provider():OnCanvasSizeChanged()
            assert.same({ "TOPLEFT", provider().overlay, "TOPLEFT", 250, -250 }, texture.points[1])
            assert.same({ 500, 500 }, { texture.width, texture.height })
        end)

        it("falls back to strips for art without a size and everywhere when the source is runs", function()
            arts[DUROTAR] = { 12345, nil, 1, 1, 0, 0, 0.1, 0.1 }
            arts[DUN_MOROGH] = { 0, "MapHighlight-DunMorogh", 1, 1, 0.2, 0.3, 0.1, 0.4 }
            install()
            provider():RefreshAllData()
            assert.equals(#strips(DUROTAR) + 1, #shownTextures())
            ns.Style.MAP_SHAPE_SOURCE = "runs"
            ns.MapOverlay.refresh()
            assert.equals(runCount(), #shownTextures())
            for _, texture in ipairs(shownTextures()) do -- recycled art textures are plain strips again
                assert.is_false(texture.desaturated)
                assert.same({ 1, 1, 1, 1 }, texture.vertexColor)
                assert.same({ 0, 1, 0, 1 }, texture.texCoord)
            end
        end)

        it("draws nothing for unlocked and start zones", function()
            arts[ELWYNN] = { 0, "MapHighlight-Elwynn", 1, 1, 0.2, 0.3, 0.1, 0.4 }
            arts[WESTFALL] = { 0, "MapHighlight-Westfall", 1, 1, 0.2, 0.3, 0.1, 0.4 }
            install()
            provider():RefreshAllData()
            for _, item in ipairs(provider().items) do
                assert.equals("run", item.kind)
            end
            assert.equals(runCount(), #shownTextures())
        end)

        it("reuses pooled textures and hides the surplus when fewer zones are tinted", function()
            install()
            provider():RefreshAllData()
            local pool = #provider().textures
            assert.equals(runCount(), pool)
            link({ items = { { id = zoneItem(WESTFALL), sender = "Ben", loc = 1 },
                             { id = zoneItem(DUN_MOROGH), sender = "Ben", loc = 2 } } }) -- Dun Morogh unlocked
            provider():RefreshAllData()
            assert.equals(pool, #provider().textures)
            assert.equals(#strips(DUROTAR), #shownTextures())
            for index = #strips(DUROTAR) + 1, pool do
                assert.is_false(provider().textures[index]:IsShown())
            end
        end)

        it("lets clicks through: the overlay frame never takes the mouse", function()
            install()
            provider():RefreshAllData()
            assert.is_not_true(provider().overlay.mouseEnabled)
            assert.is_nil(provider().overlay.scripts.OnMouseDown)
        end)

        it("clears the fill when the player turns the overlay off and brings it back", function()
            install()
            provider():RefreshAllData()
            db.ui.mapOverlay = false
            ns.MapOverlay.refresh()
            assert.is_nil(provider().zones)
            assert.same({}, shownTextures())
            db.ui.mapOverlay = true
            ns.MapOverlay.refresh()
            assert.equals(runCount(), #shownTextures())
        end)

        it("draws nothing for a character that is not linked", function()
            install()
            db.characters[game.guid].slotKey = nil
            provider():RefreshAllData()
            assert.is_nil(provider().overlay)
        end)

        it("draws nothing and raises nothing when the map API is missing", function()
            install()
            _G.C_Map = nil
            assert.has_no.errors(function() provider():RefreshAllData() end)
            assert.is_nil(provider().overlay)
            _G.C_Map = {}
            assert.has_no.errors(function() provider():RefreshAllData() end)
            _G.Enum = nil
            assert.has_no.errors(function() provider():RefreshAllData() end)
            assert.same({}, game.errors)
        end)

        it("redraws for the new map when the map changes", function()
            install()
            provider():RefreshAllData()
            map.mapId = DUN_MOROGH
            provider():RefreshAllData()
            assert.is_nil(provider().zones)
            assert.is_true(provider().banner:IsShown())
        end)
    end)

    describe("banner on a zone map", function()
        it("shows the locked banner with text on a locked zone and hides it elsewhere", function()
            install()
            map.mapId = DUN_MOROGH
            provider():RefreshAllData()
            local banner = provider().banner
            assert.is_true(banner:IsShown())
            assert.equals(ns.L.MAP_LOCKED_BANNER, banner.text:GetText())
            assert.equals(ns.Style.FONTS.title, banner.text.font)
            map.mapId = ELWYNN
            provider():RefreshAllData()
            assert.is_false(banner:IsShown())
        end)

        it("uses the locked colour with the banner opacity", function()
            install()
            map.mapId = DUN_MOROGH
            provider():RefreshAllData()
            local locked = ns.Style.COLORS.locked
            assert.same({ locked.r, locked.g, locked.b, ns.Style.BANNER_ALPHA }, provider().banner.background.color)
        end)

        it("shows a neutral banner with its own text on a zone outside the seed", function()
            install()
            map.mapId = DUROTAR
            provider():RefreshAllData()
            local banner = provider().banner
            local dark = ns.Style.COLORS.unavailableBanner
            assert.is_true(banner:IsShown())
            assert.equals("Not in your seed", banner.text:GetText())
            assert.same({ dark.r, dark.g, dark.b, ns.Style.BANNER_ALPHA }, banner.background.color)
        end)

        it("changes the banner colour with the zone, one banner frame for both", function()
            install()
            map.mapId = DUROTAR
            provider():RefreshAllData()
            local banner = provider().banner
            map.mapId = DUN_MOROGH
            provider():RefreshAllData()
            local locked = ns.Style.COLORS.locked
            assert.equals(banner, provider().banner)
            assert.same({ locked.r, locked.g, locked.b, ns.Style.BANNER_ALPHA }, banner.background.color)
            assert.equals(ns.L.MAP_LOCKED_BANNER, banner.text:GetText())
        end)

        it("shows no banner on an unlocked zone", function()
            install()
            map.mapId = WESTFALL
            provider():RefreshAllData()
            assert.is_nil(provider().banner)
        end)
    end)

    describe("tooltip", function()
        local function hover(x, y, focus)
            map.cursor, map.focus = { x, y }, focus ~= false
            provider():OnUpdate()
        end

        before_each(function()
            install()
            provider():RefreshAllData()
        end)

        it("shows name, state and open checks of the zone under the cursor and hides when it leaves", function()
            hover(0.45, 0.55)
            assert.is_true(game.tooltip.shown)
            assert.same({ "Dun Morogh", "locked", "1 open checks" }, game.tooltip.lines)
            assert.equals(provider().overlay, game.tooltip.owner)
            hover(0.9, 0.9)
            assert.is_false(game.tooltip.shown)
        end)

        it("follows the game's zone lookup, also for zones without a fill", function()
            hover(0.55, 0.65)
            assert.equals("Elwynn Forest", game.tooltip.lines[1])
            hover(0.35, 0.85)
            assert.same({ "Westfall", "unlocked", "No open checks" }, game.tooltip.lines)
        end)

        it("shows nothing over a city or the continent itself", function()
            hover(0.75, 0.65)
            assert.is_false(game.tooltip.shown)
        end)

        it("does not rebuild the tooltip while the cursor stays in the same zone", function()
            hover(0.45, 0.55)
            game.tooltip.lines[#game.tooltip.lines + 1] = "marker"
            hover(0.46, 0.56)
            assert.equals("marker", game.tooltip.lines[4])
        end)

        it("hides when the mouse is over a pin or off the map, and never touches another addon's tooltip", function()
            hover(0.45, 0.55)
            hover(0.45, 0.55, false)
            assert.is_false(game.tooltip.shown)
            game.tooltip.owner, game.tooltip.shown = "someone else", true
            hover(0.9, 0.9, false)
            assert.is_true(game.tooltip.shown)
        end)

        it("ignores a cursor position the API does not give as numbers", function()
            map.GetNormalizedCursorPosition = function() return nil end
            assert.has_no.errors(function() provider():OnUpdate() end)
            assert.is_false(game.tooltip.shown)
        end)

        it("hides when the map closes", function()
            hover(0.45, 0.55)
            provider():OnHide()
            assert.is_false(game.tooltip.shown)
        end)

        it("does nothing on maps without an overlay", function()
            map.mapId = ELWYNN
            provider():RefreshAllData()
            hover(0.45, 0.55)
            assert.is_false(game.tooltip.shown)
        end)
    end)
end)
