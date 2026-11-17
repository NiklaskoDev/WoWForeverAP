local Env = require("helpers.addon_env")

describe("MapOverlay", function()
    local ns, game, db, map

    local SLOT = "S1:Wow"
    local CONTINENT, ELWYNN, DUN_MOROGH, WESTFALL, DUROTAR, CITY = 1415, 1429, 1426, 1436, 1411, 1453
    local ZONE_TYPE

    local function zoneItem(uiMapId) return ns.Ids.itemId(ns.Ids.ItemCat.ZONE, uiMapId) end
    local function questLocation(quest) return ns.Ids.locationId(ns.Ids.LocCat.QUEST, quest) end

    local function link(overrides)
        _G.WoWForeverAP_Inbox = Env.inbox(overrides)
        db.characters[game.guid].slotKey = SLOT
    end

    --- Fake map API: the continent has these child zones with these rectangles (left, right, top, bottom).
    local function installMapApi()
        local rects = {
            [ELWYNN] = { 0.50, 0.60, 0.60, 0.70 }, [DUN_MOROGH] = { 0.40, 0.55, 0.50, 0.65 },
            [WESTFALL] = { 0.30, 0.40, 0.80, 0.90 }, [DUROTAR] = { 0.10, 0.20, 0.10, 0.20 },
            [CITY] = { 0.52, 0.55, 0.62, 0.65 },
        }
        local types = {
            [CONTINENT] = Enum.UIMapType.Continent, [ELWYNN] = ZONE_TYPE, [DUN_MOROGH] = ZONE_TYPE,
            [WESTFALL] = ZONE_TYPE, [DUROTAR] = ZONE_TYPE, [CITY] = ZONE_TYPE,
        }
        _G.C_Map = {
            GetMapInfo = function(mapId) return types[mapId] and { mapID = mapId, mapType = types[mapId] } end,
            GetMapChildrenInfo = function(mapId, wanted)
                assert.equals(CONTINENT, mapId)
                assert.equals(ZONE_TYPE, wanted)
                local children = {}
                for _, id in ipairs({ ELWYNN, DUN_MOROGH, WESTFALL, DUROTAR, CITY }) do
                    children[#children + 1] = { mapID = id }
                end
                return children
            end,
            GetMapRectOnMap = function(mapId, top)
                assert.equals(CONTINENT, top)
                return unpack(rects[mapId])
            end,
        }
        return rects
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

    local function tinted()
        local colors = {}
        for index, zone in ipairs(provider().zones or {}) do
            local texture = provider().textures[index]
            colors[zone.uiMapId] = texture.shown and texture.color or false
        end
        return colors
    end

    before_each(function()
        ns, game = Env.new()
        ZONE_TYPE = Enum.UIMapType.Zone
        db = ns.DB.init(nil)
        ns.db, ns.ready = db, true
        ns.DB.touchCharacter(db, game.guid, "Arthas", "Alliance", "PALADIN")
        installMapApi()
        installWorldMap()
        link({ items = { { id = zoneItem(WESTFALL), sender = "Ben", loc = 1 } },
               locations = { [questLocation(170)] = true, [questLocation(7)] = true, [questLocation(15)] = true } })
    end)

    describe("zoneRects", function()
        it("returns the rectangles of the zones in the data and skips the rest", function()
            local rects = ns.MapOverlay.zoneRects(CONTINENT)
            local ids = {}
            for _, rect in ipairs(rects) do ids[#ids + 1] = rect.uiMapId end
            assert.same({ ELWYNN, DUN_MOROGH, WESTFALL, DUROTAR }, ids) -- the city is not in the data
            assert.same({ uiMapId = ELWYNN, left = 0.5, right = 0.6, top = 0.6, bottom = 0.7 }, rects[1])
        end)

        it("skips rectangles that are empty, inverted or not numbers", function()
            _G.C_Map.GetMapRectOnMap = function(mapId)
                if mapId == ELWYNN then return 0.5, 0.5, 0.1, 0.2 end
                if mapId == DUN_MOROGH then return 0.5, 0.4, 0.1, 0.2 end
                if mapId == WESTFALL then return nil end
                return "a", "b", "c", "d"
            end
            assert.same({}, ns.MapOverlay.zoneRects(CONTINENT))
        end)

        it("is empty without the map API or when it fails", function()
            _G.C_Map.GetMapChildrenInfo = function() error("restricted") end
            assert.same({}, ns.MapOverlay.zoneRects(CONTINENT))
            _G.C_Map = nil
            assert.same({}, ns.MapOverlay.zoneRects(CONTINENT))
        end)
    end)

    describe("zoneAt", function()
        it("picks the smallest zone that contains the point", function()
            local rects = ns.MapOverlay.zoneRects(CONTINENT)
            assert.equals(ELWYNN, ns.MapOverlay.zoneAt(rects, 0.55, 0.65).uiMapId) -- inside both Elwynn and Dun Morogh
            assert.equals(DUN_MOROGH, ns.MapOverlay.zoneAt(rects, 0.42, 0.52).uiMapId)
            assert.is_nil(ns.MapOverlay.zoneAt(rects, 0.9, 0.9))
        end)
    end)

    describe("view", function()
        local function slotOf() return ns.Inbox.slot(ns.Inbox.current(), SLOT) end

        it("describes every zone of a continent map with its state, tint and open checks", function()
            local view = ns.MapOverlay.view(CONTINENT, slotOf())
            assert.equals("continent", view.kind)
            local byId = {}
            for _, zone in ipairs(view.zones) do byId[zone.uiMapId] = zone end
            assert.equals("start", byId[ELWYNN].state)
            assert.is_nil(byId[ELWYNN].tint)
            assert.equals(2, byId[ELWYNN].open)
            assert.equals("locked", byId[DUN_MOROGH].state)
            assert.equals(ns.Style.COLORS.locked, byId[DUN_MOROGH].tint)
            assert.equals(1, byId[DUN_MOROGH].open)
            assert.equals("unlocked", byId[WESTFALL].state)
            assert.is_nil(byId[WESTFALL].tint)
            assert.equals(0, byId[WESTFALL].open)
            assert.equals("unavailable", byId[DUROTAR].state)
            assert.equals(ns.Style.COLORS.unavailable, byId[DUROTAR].tint)
        end)

        it("shows the locked banner on the map of a locked zone only", function()
            assert.same({ kind = "zone", banner = ns.L.MAP_LOCKED_BANNER }, ns.MapOverlay.view(DUN_MOROGH, slotOf()))
            assert.is_nil(ns.MapOverlay.view(ELWYNN, slotOf())) -- start zone
            assert.is_nil(ns.MapOverlay.view(WESTFALL, slotOf())) -- unlocked
            assert.is_nil(ns.MapOverlay.view(DUROTAR, slotOf())) -- other faction
        end)

        it("shows nothing for unknown maps, the world map or a missing API", function()
            assert.is_nil(ns.MapOverlay.view(99999, slotOf()))
            assert.is_nil(ns.MapOverlay.view(nil, slotOf()))
            _G.C_Map = nil
            assert.is_nil(ns.MapOverlay.view(CONTINENT, slotOf()))
        end)

        it("leaves out checks waiting in the outbox from the open count", function()
            local view = ns.MapOverlay.view(CONTINENT, slotOf(), { [questLocation(7)] = true })
            for _, zone in ipairs(view.zones) do
                if zone.uiMapId == ELWYNN then assert.equals(1, zone.open) end
            end
        end)

        it("counts bosses and areas of a zone as open checks next to its quests", function()
            ns.Data.bosses[9001] = { name = "Boss A", instance = "Test Mines", zone = ELWYNN }
            local slot = slotOf()
            slot.locations[ns.Ids.locationId(ns.Ids.LocCat.BOSS, 9001)] = true
            slot.locations[ns.Ids.locationId(ns.Ids.LocCat.AREA_DISCOVERY, 18)] = true
            for _, zone in ipairs(ns.MapOverlay.view(CONTINENT, slot).zones) do
                if zone.uiMapId == ELWYNN then assert.equals(4, zone.open) end
            end
        end)

        it("words the tooltip as zone name, state label and open checks", function()
            local view = ns.MapOverlay.view(CONTINENT, slotOf())
            local lines = {}
            for _, zone in ipairs(view.zones) do lines[zone.uiMapId] = ns.MapOverlay.tooltipLines(zone) end
            assert.same({ "Dun Morogh", "locked", "1 open checks" }, lines[DUN_MOROGH])
            assert.same({ "Westfall", "unlocked", "No open checks" }, lines[WESTFALL])
            assert.same({ "Durotar", "not in your seed", "No open checks" }, lines[DUROTAR])
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

    describe("drawing on a continent map", function()
        it("tints locked zones red and others dark, and leaves unlocked and start zones untouched", function()
            install()
            provider():RefreshAllData()
            local colors = tinted()
            local locked, dark = ns.Style.COLORS.locked, ns.Style.COLORS.unavailable
            assert.same({ locked.r, locked.g, locked.b, locked.a }, colors[DUN_MOROGH])
            assert.same({ dark.r, dark.g, dark.b, dark.a }, colors[DUROTAR])
            assert.is_false(colors[ELWYNN])
            assert.is_false(colors[WESTFALL])
        end)

        it("places each tint from the canvas size and re-places it when the canvas changes", function()
            install()
            provider():RefreshAllData()
            local dunMorogh = provider().textures[2]
            assert.same({ "TOPLEFT", provider().overlay, "TOPLEFT", 400, -250 }, dunMorogh.points[1])
            assert.is_true(math.abs(dunMorogh.width - 150) < 1e-6 and math.abs(dunMorogh.height - 75) < 1e-6)
            map.canvas:SetSize(2000, 1000)
            provider():OnCanvasSizeChanged()
            assert.same({ "TOPLEFT", provider().overlay, "TOPLEFT", 800, -500 }, dunMorogh.points[1])
            assert.is_true(math.abs(dunMorogh.width - 300) < 1e-6)
        end)

        it("lets clicks through: the overlay frame never takes the mouse", function()
            install()
            provider():RefreshAllData()
            assert.is_not_true(provider().overlay.mouseEnabled)
            assert.is_nil(provider().overlay.scripts.OnMouseDown)
        end)

        it("clears the tints when the player turns the overlay off", function()
            install()
            provider():RefreshAllData()
            db.ui.mapOverlay = false
            ns.MapOverlay.refresh()
            assert.is_nil(provider().zones)
            for _, texture in ipairs(provider().textures) do
                assert.is_false(texture:IsShown())
            end
            db.ui.mapOverlay = true
            ns.MapOverlay.refresh()
            assert.is_true(provider().textures[2]:IsShown())
        end)

        it("draws nothing for a character that is not linked", function()
            install()
            db.characters[game.guid].slotKey = nil
            provider():RefreshAllData()
            assert.is_nil(provider().overlay)
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
            hover(0.42, 0.52)
            assert.is_true(game.tooltip.shown)
            assert.same({ "Dun Morogh", "locked", "1 open checks" }, game.tooltip.lines)
            assert.equals(provider().overlay, game.tooltip.owner)
            hover(0.9, 0.9)
            assert.is_false(game.tooltip.shown)
        end)

        it("prefers the smaller zone where two overlap", function()
            hover(0.55, 0.65)
            assert.equals("Elwynn Forest", game.tooltip.lines[1])
        end)

        it("does not rebuild the tooltip while the cursor stays in the same zone", function()
            hover(0.42, 0.52)
            game.tooltip.lines[#game.tooltip.lines + 1] = "marker"
            hover(0.43, 0.53)
            assert.equals("marker", game.tooltip.lines[4])
        end)

        it("hides when the mouse is over a pin or off the map, and never touches another addon's tooltip", function()
            hover(0.42, 0.52)
            hover(0.42, 0.52, false)
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
            hover(0.42, 0.52)
            provider():OnHide()
            assert.is_false(game.tooltip.shown)
        end)

        it("does nothing on maps without an overlay", function()
            map.mapId = ELWYNN
            provider():RefreshAllData()
            hover(0.42, 0.52)
            assert.is_false(game.tooltip.shown)
        end)
    end)
end)
