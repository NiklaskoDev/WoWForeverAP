-- World map overlay (plans 003, 010): on a continent map every zone of the data that is locked or not in the seed
-- is filled in its real shape (locked: red, not in the seed: dark; unlocked and start: no fill), with a tooltip
-- (name, state, open checks); the map of a locked or not-in-the-seed zone gets a banner. Shapes come from
-- MapShapes: the zone's highlight art, or strips sampled from the zone lookup when there is none.
-- APIs (checked against the 12.1.5 UI source): WorldMapFrame:AddDataProvider, MapCanvasDataProviderMixin (OnAdded,
-- RemoveAllData, RefreshAllData, OnCanvasSizeChanged, OnUpdate, GetMap), map:GetCanvas / GetCanvasContainer /
-- GetMapID / GetNormalizedCursorPosition / IsCanvasMouseFocus / RegisterDataProviderOnUpdate, C_Map.GetMapInfo,
-- Enum.UIMapType, texture SetColorTexture / SetAtlas / SetTexture / SetTexCoord / SetVertexColor / SetDesaturated /
-- SetBlendMode (the zone shape APIs are in MapShapes). Whatever is missing leaves the map as it is.
local _, ns = ...

local MapOverlay = {}
ns.MapOverlay = MapOverlay

local provider

local function mapType(mapId)
    local info = C_Map and type(mapId) == "number" and ns.tryCall(C_Map.GetMapInfo, mapId)
    return type(info) == "table" and info.mapType or nil
end

local function openCounts(slot, pending)
    local counts = {}
    for _, group in ipairs(ns.Checks.openByZone(slot, pending)) do
        counts[group.uiMapId] = ns.Checks.openCount(group)
    end
    return counts
end

--- What to draw on the map `mapId` for the slot: nil (nothing), { kind = "continent", zones = { [uiMapId] = {
--- uiMapId, state, tint, open, shape } } } for every zone the continent shows, or { kind = "zone", banner = text,
--- tone = "locked" | "unavailable" } for a zone map of a locked or not-in-the-seed zone.
function MapOverlay.view(mapId, slot, pending)
    local types = Enum and Enum.UIMapType
    local kind = types and mapType(mapId)
    if kind == nil then
        return nil
    elseif kind == types.Continent then
        local counts = openCounts(slot, pending)
        local zones = {}
        for uiMapId, shape in pairs(ns.MapShapes.forContinent(mapId)) do
            local state = ns.Checks.zoneState(slot, uiMapId)
            zones[uiMapId] = {
                uiMapId = uiMapId, state = state, tint = ns.Style.stateTint(state), open = counts[uiMapId] or 0,
                shape = shape,
            }
        end
        return next(zones) and { kind = "continent", zones = zones } or nil
    elseif kind == types.Zone then
        local state = ns.Checks.zoneState(slot, mapId)
        if state == "locked" then
            return { kind = "zone", banner = ns.L.MAP_LOCKED_BANNER, tone = "locked" }
        elseif state == "unavailable" then
            return { kind = "zone", banner = ns.L.MAP_UNAVAILABLE_BANNER, tone = "unavailable" }
        end
    end
    return nil
end

--- Tooltip lines of a zone entry of `view`: name, state label (text, not only colour), open checks.
function MapOverlay.tooltipLines(zone)
    local open = zone.open > 0 and ns.L.MAP_OPEN_CHECKS:format(zone.open) or ns.L.MAP_NO_OPEN_CHECKS
    return { ns.Names.zone(zone.uiMapId), ns.L[ns.Style.STATE_LABEL_KEYS[zone.state]], open }
end

-- Drawing ---------------------------------------------------------------------------------------------------

local function hideTooltip(self)
    if self.hovered and self.overlay and GameTooltip and GameTooltip:IsOwned(self.overlay) then
        GameTooltip:Hide()
    end
    self.hovered = nil
end

--- The art a zone is drawn with, or nil for strips: the art must be there, wanted, and placeable the way
--- Blizzard places it (a file texture needs a size).
local function usableArt(shape)
    local art = shape.art
    if ns.Style.MAP_SHAPE_SOURCE == "art" and art and (art.atlas or (art.width > 0 and art.height > 0)) then
        return art
    end
    return nil
end

-- Placement math of Blizzard's MapHighlightPinMixin:Refresh (Blizzard_SharedMapDataProviders/
-- MapHighlightDataProvider.lua), with the canvas-sized overlay in place of the pin.
local function placeItem(overlay, item, width, height)
    local texture, art = item.texture, item.art
    texture:ClearAllPoints()
    if item.kind == "atlas" then
        texture:SetPoint("CENTER", overlay, "CENTER", ((art.left + 0.5 * art.width) - 0.5) * width,
            -((art.top + 0.5 * art.height) - 0.5) * height)
    elseif item.kind == "file" then
        texture:SetSize(art.width * width, art.height * height)
        texture:SetPoint("TOPLEFT", overlay, "TOPLEFT", art.left * width, -art.top * height)
    else
        texture:SetSize((item.last - item.first + 1) / ns.MapShapes.COLUMNS * width, height / ns.MapShapes.ROWS)
        texture:SetPoint("TOPLEFT", overlay, "TOPLEFT", (item.first - 1) / ns.MapShapes.COLUMNS * width,
            -(item.row - 1) / ns.MapShapes.ROWS * height)
    end
end

local function placeTextures(self)
    local canvas = self:GetMap():GetCanvas()
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    for _, item in ipairs(self.items or {}) do
        placeItem(self.overlay, item, width, height)
    end
end

local function ensureOverlay(self)
    if self.overlay then
        return
    end
    local canvas = self:GetMap():GetCanvas()
    self.overlay = CreateFrame("Frame", nil, canvas)
    self.overlay:SetAllPoints(canvas)
    self.overlay:SetFrameLevel(canvas:GetFrameLevel() + 2) -- above the map art, below the pins
    self.textures = {}
end

--- Dresses a pooled texture for one piece of a zone's fill; a recycled texture may carry the last zone's art.
local function dress(texture, item)
    local tint = item.tint
    texture:SetDesaturated(false)
    texture:SetBlendMode("BLEND")
    if item.kind == "run" then
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetVertexColor(1, 1, 1, 1)
        texture:SetColorTexture(tint.r, tint.g, tint.b, tint.a)
        return
    end
    -- the art is made for additive blending; as a desaturated, tinted layer it should read as a flat fill
    local art = item.art
    texture:SetTexCoord(0, art.texRight, 0, art.texBottom)
    if item.kind == "atlas" then
        texture:SetAtlas(art.atlas, true)
    else
        texture:SetTexture(art.file)
    end
    texture:SetDesaturated(true)
    texture:SetVertexColor(tint.r, tint.g, tint.b, tint.a)
end

--- The textures a zone needs: one for its art, or one per strip.
local function zoneItems(zone, items)
    local art = usableArt(zone.shape)
    if art then
        items[#items + 1] = { kind = art.atlas and "atlas" or "file", art = art, tint = zone.tint }
        return
    end
    for _, run in ipairs(zone.shape.runs) do
        items[#items + 1] = { kind = "run", row = run[1], first = run[2], last = run[3], tint = zone.tint }
    end
end

local function drawZones(self, zones)
    ensureOverlay(self)
    self.zones = zones
    local ids = {}
    for uiMapId, zone in pairs(zones) do
        if zone.tint then
            ids[#ids + 1] = uiMapId
        end
    end
    table.sort(ids) -- the same order on every redraw
    local items = {}
    for _, uiMapId in ipairs(ids) do
        zoneItems(zones[uiMapId], items)
    end
    for index, item in ipairs(items) do
        local texture = self.textures[index] or self.overlay:CreateTexture(nil, "ARTWORK")
        self.textures[index] = texture
        item.texture = texture
        dress(texture, item)
        texture:Show()
    end
    for index = #items + 1, #self.textures do
        self.textures[index]:Hide()
    end
    self.items = items
    placeTextures(self)
end

local function drawBanner(self, text, tone)
    local map = self:GetMap()
    if not self.banner then
        self.banner = CreateFrame("Frame", nil, map)
        self.banner:SetFrameStrata("HIGH")
        self.banner:SetSize(260, 28)
        self.banner:SetPoint("TOP", map:GetCanvasContainer(), "TOP", 0, -ns.Style.SPACING.sm)
        self.banner.background = self.banner:CreateTexture(nil, "BACKGROUND")
        self.banner.background:SetAllPoints(self.banner)
        self.banner.text = self.banner:CreateFontString(nil, "OVERLAY", ns.Style.FONTS.title)
        self.banner.text:SetPoint("CENTER")
    end
    local tint = tone == "unavailable" and ns.Style.COLORS.unavailableBanner or ns.Style.COLORS.locked
    self.banner.background:SetColorTexture(tint.r, tint.g, tint.b, ns.Style.BANNER_ALPHA)
    self.banner.text:SetText(text)
    self.banner:Show()
end

local ProviderMethods = {}

function ProviderMethods:OnAdded(map)
    MapCanvasDataProviderMixin.OnAdded(self, map)
    if type(map.RegisterDataProviderOnUpdate) == "function" then
        map:RegisterDataProviderOnUpdate(self) -- the tooltip follows the cursor
    end
end

function ProviderMethods:RemoveAllData()
    hideTooltip(self)
    self.zones, self.items = nil, nil
    for _, texture in ipairs(self.textures or {}) do
        texture:Hide()
    end
    if self.banner then
        self.banner:Hide()
    end
end

function ProviderMethods:RefreshAllData()
    self:RemoveAllData()
    if not (ns.ready and ns.db.ui.mapOverlay) then
        return
    end
    local _, slotKey, slot = ns.Tracker.playerContext()
    if not slot then
        return
    end
    local view = MapOverlay.view(self:GetMap():GetMapID(), slot, ns.DB.outboxIds(ns.db, slotKey))
    if not view then
        return
    elseif view.kind == "continent" then
        drawZones(self, view.zones)
    else
        drawBanner(self, view.banner, view.tone)
    end
end

function ProviderMethods:OnCanvasSizeChanged()
    if self.zones then
        placeTextures(self)
    end
end

function ProviderMethods:OnHide()
    hideTooltip(self)
end

function ProviderMethods:OnUpdate()
    local map = self:GetMap()
    if not (self.zones and map:IsCanvasMouseFocus()) then
        hideTooltip(self)
        return
    end
    local x, y = map:GetNormalizedCursorPosition()
    local uiMapId = type(x) == "number" and type(y) == "number" and ns.MapShapes.zoneAt(map:GetMapID(), x, y)
    local zone = uiMapId and self.zones[uiMapId] or nil
    if zone == self.hovered then
        return
    end
    hideTooltip(self)
    if zone and GameTooltip then
        self.hovered = zone
        GameTooltip:SetOwner(self.overlay, "ANCHOR_CURSOR")
        for _, line in ipairs(MapOverlay.tooltipLines(zone)) do
            GameTooltip:AddLine(line, 1, 1, 1)
        end
        GameTooltip:Show()
    end
end

--- Adds the overlay to the world map; false when this client's map code is not what the addon expects.
function MapOverlay.install()
    local ready = WorldMapFrame and type(WorldMapFrame.AddDataProvider) == "function"
        and type(MapCanvasDataProviderMixin) == "table" and type(CreateFromMixins) == "function"
    if provider or not ready then
        return provider ~= nil
    end
    local created = CreateFromMixins(MapCanvasDataProviderMixin, ProviderMethods)
    if pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, created) then
        provider = created
    end
    return provider ~= nil
end

--- Redraws the current map, for example after an option changed.
function MapOverlay.refresh()
    if provider and provider:GetMap() then
        provider:RefreshAllData()
    end
end

ns.Events.register("PLAYER_LOGIN", MapOverlay.install)
