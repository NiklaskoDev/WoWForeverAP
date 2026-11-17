-- Minimal fake of the game API for the specs. `install()` resets every global the addon touches and returns
-- the `game` table the spec mutates to steer the fake (locale, player, clock) and to read what the addon did.
local Stub = {}

local FAKE_GLOBALS = {
    "GetLocale", "time", "UnitGUID", "UnitName", "UnitLevel", "UnitFactionGroup", "UnitClass", "GetBuildInfo",
    "CreateFrame", "geterrorhandler", "StaticPopup_Show", "StaticPopupDialogs", "SlashCmdList", "SLASH_WFAP1",
    "C_Map", "C_QuestLog", "C_TradeSkillUI", "GetProfessions", "GetProfessionInfo",
    "Enum", "C_EventUtils", "UIErrorsFrame",
    "WoWForeverAP_DB", "WoWForeverAP_Inbox", "WoWForeverAP_OnCompartmentClick",
}

local function newFrame(game)
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event)
        self.events[event] = true
    end
    function frame:SetScript(name, handler)
        self.scripts[name] = handler
    end
    game.frames[#game.frames + 1] = frame
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
    _G.CreateFrame = function() return newFrame(game) end
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
    } }
    _G.UIErrorsFrame = {
        AddMessage = function(_, text, red, green, blue, alpha)
            game.uiErrors[#game.uiErrors + 1] = { text = text, color = { red, green, blue, alpha } }
        end,
    }
    return game
end

return Stub
