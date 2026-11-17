std = "lua51"
max_line_length = 120

-- SavedVariables and the client-written inbox are the only globals the addon owns.
globals = {
    "WoWForeverAP_DB",
    "WoWForeverAP_Inbox",
    "WoWForeverAP_OnCompartmentClick",
    "SLASH_WFAP1",
    "SlashCmdList",
    "StaticPopupDialogs",
}

-- Blizzard API functions and tables the addon is allowed to read. Keep this list explicit:
-- every entry is an API the addon really calls.
read_globals = {
    "ButtonFrameTemplate_HidePortrait",
    "C_EventUtils",
    "C_Map",
    "C_QuestLog",
    "C_TradeSkillUI",
    "CreateDataProvider",
    "CreateFrame",
    "CreateFromMixins",
    "CreateScrollBoxListLinearView",
    "Enum",
    "GameTooltip",
    "GetBuildInfo",
    "GetLocale",
    "GetProfessionInfo",
    "GetProfessions",
    "MapCanvasDataProviderMixin",
    "PanelTemplates_SetNumTabs",
    "PanelTemplates_SetTab",
    "RaidNotice_AddMessage",
    "RaidWarningFrame",
    "RaidWarningUtil",
    "ScrollUtil",
    "Settings",
    "StaticPopup_Show",
    "UIErrorsFrame",
    "UIParent",
    "UISpecialFrames",
    "UnitClass",
    "UnitFactionGroup",
    "UnitGUID",
    "UnitLevel",
    "UnitName",
    "WorldMapFrame",
    "geterrorhandler",
    "time",
}

-- Locale files hold long sentences; the generated data file is not hand-formatted.
files["addon/WoWForeverAP/Locales"] = { max_line_length = false }

-- busted provides its own globals in specs, and specs install fake game APIs into _G.
files["addon/spec"] = {
    std = "+busted",
}
