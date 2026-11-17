-- Minimal fake of the game API for the specs. `install()` resets every global the addon touches and returns
-- the `game` table the spec mutates to steer the fake (locale, player, clock) and to read what the addon did.
local Stub = {}

local FAKE_GLOBALS = {
    "GetLocale", "time", "UnitGUID", "UnitName", "UnitLevel", "UnitFactionGroup", "UnitClass", "GetBuildInfo",
    "CreateFrame", "geterrorhandler", "StaticPopup_Show", "StaticPopupDialogs", "SlashCmdList", "SLASH_WFAP1",
    "C_Map", "C_QuestLog", "C_TradeSkillUI", "GetProfessions", "GetProfessionInfo",
    "Enum", "C_EventUtils", "UIErrorsFrame", "RaidWarningUtil", "RaidNotice_AddMessage", "RaidWarningFrame",
    "UIParent", "GameTooltip", "UISpecialFrames", "ButtonFrameTemplate_HidePortrait", "PanelTemplates_SetNumTabs",
    "PanelTemplates_SetTab", "CreateScrollBoxListLinearView", "ScrollUtil", "CreateDataProvider", "Settings",
    "WorldMapFrame", "MapCanvasDataProviderMixin", "CreateFromMixins",
    "WoWForeverAP_DB", "WoWForeverAP_Inbox", "WoWForeverAP_OnCompartmentClick",
}

-- A fake frame: it keeps what the addon sets (scripts, events, points, text, shown state) and answers every other
-- method with a no-op, so specs can build the whole window and then look at the result.
local Frame = {}
Frame.__index = function(_, key)
    if Frame[key] then
        return Frame[key]
    end
    if type(key) == "string" and key:match("^%u") then
        return function() end -- any other API method: accepted, nothing happens
    end
end

function Frame:RegisterEvent(event)
    self.events[event] = true
end

function Frame:SetScript(name, handler)
    self.scripts[name] = handler
end

function Frame:GetScript(name)
    return self.scripts[name]
end

function Frame:SetPoint(...)
    self.points[#self.points + 1] = { ... }
end

function Frame:ClearAllPoints()
    self.points = {}
end

function Frame:GetPoint()
    local point = self.points[1] or { "CENTER", nil, "CENTER", 0, 0 }
    return point[1], point[2], point[3], point[4] or 0, point[5] or 0
end

function Frame:SetShown(shown)
    if shown then
        self:Show()
    else
        self:Hide()
    end
end

function Frame:Show()
    local was = self.shown
    self.shown = true
    if not was and self.scripts.OnShow then
        self.scripts.OnShow(self)
    end
end

function Frame:Hide()
    self.shown = false
end

function Frame:IsShown()
    return self.shown == true
end

function Frame:SetText(text)
    self.text = text
end

function Frame:GetText()
    return self.text
end

function Frame:SetTextColor(red, green, blue)
    self.textColor = { red, green, blue }
end

function Frame:SetFontObject(font)
    self.font = font
end

function Frame:SetID(id)
    self.id = id
end

function Frame:GetID()
    return self.id
end

function Frame:SetSize(width, height)
    self.width, self.height = width, height
end

function Frame:GetWidth()
    return self.width or 0
end

function Frame:GetHeight()
    return self.height or 0
end

function Frame:SetColorTexture(red, green, blue, alpha)
    self.color = { red, green, blue, alpha }
end

function Frame:SetFrameLevel(level)
    self.level = level
end

function Frame:GetFrameLevel()
    return self.level or 1
end

function Frame:EnableMouse(enabled)
    self.mouseEnabled = enabled
end

function Frame:IsTruncated()
    return self.truncated == true
end

function Frame:SetDataProvider(provider)
    self.dataProvider = provider
end

function Frame:CreateFontString(_, _, font)
    local fontString = Frame.new(self.game, "FontString")
    fontString.font = font
    return fontString
end

function Frame:CreateTexture()
    return Frame.new(self.game, "Texture")
end

function Frame.new(game, kind, name, parent, template)
    local frame = setmetatable({
        game = game, kind = kind, name = name, parent = parent, template = template,
        events = {}, scripts = {}, points = {}, shown = false,
    }, Frame)
    game.frames[#game.frames + 1] = frame
    if template == "ButtonFrameTemplate" then
        frame.Inset = Frame.new(game, "Frame")
    end
    return frame
end

function Stub.install()
    for _, name in ipairs(FAKE_GLOBALS) do
        _G[name] = nil
    end
    local game = {
        locale = "enUS",
        now = 1000,
        guid = "Player-1-AAAA",
        name = "Arthas",
        faction = "Alliance",
        classFile = "PALADIN",
        level = 1,
        frames = {},
        popups = {},
        uiErrors = {}, -- messages shown through UIErrorsFrame:AddMessage
        errors = {},
        chat = {},
    }
    _G.GetLocale = function() return game.locale end
    _G.time = function() return game.now end
    _G.UnitGUID = function() return game.guid end
    _G.UnitName = function() return game.name end
    _G.UnitLevel = function() return game.level end
    _G.UnitFactionGroup = function() return game.faction end
    _G.UnitClass = function() return "Paladin", game.classFile, 2 end
    _G.GetBuildInfo = function() return "12.1.5", "70783", "Nov 4 2026", 120105 end
    -- A template missing from the client makes CreateFrame raise; specs list such templates in game.missingTemplates.
    game.missingTemplates = {}
    _G.CreateFrame = function(kind, name, parent, template)
        if template and game.missingTemplates[template] then
            error("CreateFrame: Couldn't find inherited node \"" .. template .. "\"")
        end
        return Frame.new(game, kind, name, parent, template)
    end
    _G.UIParent = Frame.new(game, "Frame", "UIParent")
    game.frames[#game.frames] = nil -- game.frames[1] stays the addon's event frame
    _G.UISpecialFrames = {}
    game.tooltip = { lines = {}, shown = false }
    _G.GameTooltip = {
        SetOwner = function(_, owner) game.tooltip.owner = owner end,
        IsOwned = function(_, frame) return game.tooltip.owner == frame end,
        AddLine = function(_, text) game.tooltip.lines[#game.tooltip.lines + 1] = text end,
        Show = function() game.tooltip.shown = true end,
        Hide = function() game.tooltip.shown, game.tooltip.lines = false, {} end,
    }
    -- Blizzard's panel, tab and scroll helpers, as far as the addon calls them.
    _G.ButtonFrameTemplate_HidePortrait = function(target) target.portraitHidden = true end
    _G.PanelTemplates_SetNumTabs = function(target, count) target.numTabs = count end
    _G.PanelTemplates_SetTab = function(target, index) target.selectedTab = index end
    _G.CreateScrollBoxListLinearView = function()
        local view = {}
        function view:SetElementExtent(extent) self.extent = extent end
        function view:SetElementInitializer(kind, initializer) self.kind, self.initializer = kind, initializer end
        return view
    end
    _G.ScrollUtil = {
        InitScrollBoxListWithScrollBar = function(list, bar, view) list.bar, list.view = bar, view end,
    }
    _G.CreateDataProvider = function(rows) return { rows = rows } end
    _G.geterrorhandler = function()
        return function(err) game.errors[#game.errors + 1] = err end
    end
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(which, arg1, arg2, data)
        game.popups[#game.popups + 1] = { which = which, arg1 = arg1, arg2 = arg2, data = data }
    end
    _G.SlashCmdList = {}
    -- Values as in the 12.x API documentation (Blizzard_APIDocumentationGenerated).
    _G.Enum = { PlayerInteractionType = {
        TradePartner = 1, Merchant = 5, Banker = 8, GuildBanker = 10, MailInfo = 17, Auctioneer = 21,
        AccountBanker = 68,
    }, UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
    _G.UIErrorsFrame = {
        AddMessage = function(_, text, red, green, blue, alpha)
            game.uiErrors[#game.uiErrors + 1] = { text = text, color = { red, green, blue, alpha } }
        end,
    }
    return game
end

return Stub
