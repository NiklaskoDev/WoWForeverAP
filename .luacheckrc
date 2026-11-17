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
    "C_Map",
    "C_QuestLog",
    "C_TradeSkillUI",
    "CreateFrame",
    "GetLocale",
    "GetProfessionInfo",
    "GetProfessions",
    "StaticPopup_Show",
    "UnitFactionGroup",
    "UnitGUID",
    "UnitLevel",
    "UnitName",
    "time",
}

-- busted provides its own globals in specs.
files["addon/spec"] = {
    std = "+busted",
}
