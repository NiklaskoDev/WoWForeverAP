-- World map overlay: on a continent map every zone of the data gets a flat colour tint for its state (locked: red,
-- not in the seed: dark, unlocked and start: none), a tooltip with name, state and open checks, and a "Locked"
-- banner on the map of a locked zone. Zone shapes are the rectangles C_Map.GetMapRectOnMap reports, so tints
-- overlap a little at borders (plan 003, decision "map overlay precision": rectangles first).
-- APIs (checked against the 12.x UI source): WorldMapFrame:AddDataProvider, MapCanvasDataProviderMixin (OnAdded,
-- RemoveAllData, RefreshAllData, OnCanvasSizeChanged, OnUpdate, GetMap), map:GetCanvas / GetCanvasContainer /
-- GetMapID / GetNormalizedCursorPosition / IsCanvasMouseFocus / RegisterDataProviderOnUpdate,
-- C_Map.GetMapChildrenInfo, C_Map.GetMapRectOnMap (returns left, right, top, bottom), Enum.UIMapType.
-- Whatever is missing leaves the map as it is.
local _, ns = ...

local MapOverlay = {}
ns.MapOverlay = MapOverlay

local provider

local function mapType(mapId)
    local info = C_Map and type(mapId) == "number" and ns.tryCall(C_Map.GetMapInfo, mapId)
    return type(info) == "table" and info.mapType or nil
end

--- The zone rectangles on a continent map: { { uiMapId, left, right, top, bottom }, ... }, normalised 0..1,
--- for every child zone the addon data lists and the API gives a usable rectangle for.
function MapOverlay.zoneRects(continentMapId)
    local rects = {}
    local children = C_Map and ns.tryCall(C_Map.GetMapChildrenInfo, continentMapId, Enum.UIMapType.Zone)
    for _, child in ipairs(type(children) == "table" and children or {}) do
        local uiMapId = type(child) == "table" and child.mapID
        if ns.Data.zones[uiMapId] then
            local left, right, top, bottom = ns.tryCall(C_Map.GetMapRectOnMap, uiMapId, continentMapId)
            if type(left) == "number" and type(right) == "number" and type(top) == "number"
                and type(bottom) == "number" and right > left and bottom > top then
                rects[#rects + 1] = { uiMapId = uiMapId, left = left, right = right, top = top, bottom = bottom }
            end
        end
    end
    return rects
end

--- The zone under the point (x, y): the smallest rectangle containing it, so a small zone inside a big one wins.
function MapOverlay.zoneAt(zones, x, y)
    local best, bestArea
    for _, zone in ipairs(zones) do
        if x >= zone.left and x <= zone.right and y >= zone.top and y <= zone.bottom then
            local area = (zone.right - zone.left) * (zone.bottom - zone.top)
            if not bestArea or area < bestArea then
                best, bestArea = zone, area
            end
        end
    end
    return best
end

local function openCounts(slot, pending)
    local counts = {}
    for _, group in ipairs(ns.Checks.openByZone(slot, pending)) do
        counts[group.uiMapId] = ns.Checks.openCount(group)
    end
    return counts
end

--- What to draw on the map `mapId` for the slot: nil (nothing), { kind = "continent", zones = { { uiMapId, state,
--- tint, left, right, top, bottom, open }, ... } } or { kind = "zone", banner = text } for a locked zone.
function MapOverlay.view(mapId, slot, pending)
    local types = Enum and Enum.UIMapType
    local kind = types and mapType(mapId)
    if kind == nil then
        return nil
    elseif kind == types.Continent then
        local counts = openCounts(slot, pending)
        local zones = {}
        for _, rect in ipairs(MapOverlay.zoneRects(mapId)) do
            local state = ns.Checks.zoneState(slot, rect.uiMapId)
            rect.state, rect.tint, rect.open = state, ns.Style.stateTint(state), counts[rect.uiMapId] or 0
            zones[#zones + 1] = rect
        end
        return { kind = "continent", zones = zones }
    elseif kind == types.Zone and ns.Checks.zoneState(slot, mapId) == "locked" then
        return { kind = "zone", banner = ns.L.MAP_LOCKED_BANNER }
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

local function placeTextures(self)
    local canvas = self:GetMap():GetCanvas()
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    for index, zone in ipairs(self.zones or {}) do
        local texture = self.textures[index]
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", self.overlay, "TOPLEFT", zone.left * width, -zone.top * height)
        texture:SetSize((zone.right - zone.left) * width, (zone.bottom - zone.top) * height)
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

local function drawZones(self, zones)
    ensureOverlay(self)
    self.zones = zones
    for index, zone in ipairs(zones) do
        local texture = self.textures[index] or self.overlay:CreateTexture(nil, "ARTWORK")
        self.textures[index] = texture
        local tint = zone.tint
        if tint then
            texture:SetColorTexture(tint.r, tint.g, tint.b, tint.a)
            texture:Show()
        else
            texture:Hide()
        end
    end
    placeTextures(self)
end

local function drawBanner(self, text)
    local map = self:GetMap()
    if not self.banner then
        self.banner = CreateFrame("Frame", nil, map)
        self.banner:SetFrameStrata("HIGH")
        self.banner:SetSize(260, 28)
        self.banner:SetPoint("TOP", map:GetCanvasContainer(), "TOP", 0, -ns.Style.SPACING.sm)
        self.banner.background = self.banner:CreateTexture(nil, "BACKGROUND")
        self.banner.background:SetAllPoints(self.banner)
        local tint = ns.Style.COLORS.locked
        self.banner.background:SetColorTexture(tint.r, tint.g, tint.b, ns.Style.BANNER_ALPHA)
        self.banner.text = self.banner:CreateFontString(nil, "OVERLAY", ns.Style.FONTS.title)
        self.banner.text:SetPoint("CENTER")
    end
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
    self.zones = nil
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
        drawBanner(self, view.banner)
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
    local zone = type(x) == "number" and type(y) == "number" and MapOverlay.zoneAt(self.zones, x, y) or nil
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
