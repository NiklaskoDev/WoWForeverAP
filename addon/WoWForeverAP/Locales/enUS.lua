-- English strings; the fallback for every other locale. Keep keys in sync with deDE.lua (a spec checks it).
local _, ns = ...

ns.locales.enUS = {
    -- check detection and sync reminders
    CHECK_RECORDED = "Check recorded: %s",
    UNSYNCED = "%d checks waiting - /reload or log out to send them",
    GOAL_REACHED = "Goal reached! /reload or log out to send it.",
    LEVEL_CHECK = "Reach Level %d",
    PROFESSION_CHECK = "%s %d",
    QUEST_FMT = "Quest %d",
    ZONE_FMT = "Zone %d",
    PROFESSION_FMT = "Profession %d",

    -- items
    ITEM_ZONE = "Zone: %s",
    ITEM_PROFESSION_TIER = "Progressive %s (tier %d)",
    ITEM_UNKNOWN = "Unknown item %s",
    FILLER_1 = "Traveler's Tale",
    ITEM_CARE_PACKAGE = "Care Package",
    ITEM_LINE = "%s (from %s)",
    NEW_ITEMS = "%d new items since you last looked:",
    MORE_ITEMS = "... and %d more, see /wfap items",
    ITEMS_HEADER = "Received items (%d):",
    ITEMS_EMPTY = "No items received yet.",

    -- linking
    LINK_PROMPT = "Link %s to the Archipelago slot \"%s\"?\n\nFrom now on this character's quests, levels and profession skills count as checks.",
    LINK_YES = "Link",
    LINK_NO = "Not now",
    LINK_NEVER = "Never ask",
    LINK_OK = "%s is now linked to slot %s.",
    LINK_ALREADY = "This character is already linked to slot %s. Use /wfap unlink first.",
    LINK_FACTION_MISMATCH = "This character is %s, but the slot plays %s: cannot link.",
    LINK_LEVEL_WARNING = "This character is level %d. Progress made before linking does not count.",
    LINK_BAD_SLOT = "That slot is not in the inbox. Connect the client and /reload.",
    LINK_BAD_INDEX = "Use /wfap link <number> with one of the numbers above.",
    LINK_NO_SLOTS = "No slot found. Start the Archipelago client, connect it, then /reload.",
    LINK_CHOOSE = "Several slots found. Choose one with /wfap link <number>:",
    LINK_SLOT_LINE = "%d: %s",
    LINK_HINT = "Several slots found. Link this character with /wfap link <number>.",
    UNLINK_OK = "This character is no longer linked.",
    NOT_LINKED = "This character is not linked. Use /wfap link.",

    -- status
    STATUS_LINKED = "Linked to slot %s.",
    STATUS_ITEMS = "Items received: %d",
    STATUS_OPEN = "Open checks: %d",
    STATUS_UNSYNCED = "Checks waiting to be sent: %d",
    STATUS_SLOTS = "Slots in the inbox: %d",

    -- problems
    SLOT_MISSING = "Slot %s is not in the inbox. Start the client for it, then /reload.",
    INBOX_INVALID = "The inbox is missing or damaged. Check that the client is running and /reload.",
    DB_NEWER = "The saved data was written by a newer addon version. The addon stays inactive to protect it.",
    API_MISSING = "Profession checks are unavailable: the game API %s does not exist in this client.",

    -- economy rules (honor system)
    RULE_AUCTION_HOUSE = "Auction House",
    RULE_TRADING = "Trading",
    RULE_MAIL = "Mail",
    RULE_SHARED_BANKS = "Guild and account bank",
    RULE_MAIN_BOOSTS = "Boosts from a main",
    ECONOMY_WARNING = "%s is off in your seed's economy rules. Please keep to them (honor system).",
    CARE_MAIL_HINT = "A Care Package allows one pull from your main (%d left): /wfap care use.",
    RULES_HEADER = "Economy rules of your slot:",
    RULES_LINE = "%s: %s",
    RULES_ALLOWED = "allowed",
    RULES_FORBIDDEN = "not allowed",
    RULES_CARE = "Care Package: one pull of up to %d gold or %d stacks of materials from a main.",
    RULES_MISSING = "This slot has no economy rules: it was made by an older apworld version.",
    CARE_STATUS = "Care Packages: %d available (%d received, %d used).",
    CARE_NONE = "No Care Package available.",
    CARE_AMOUNT = "up to %d gold or %d stacks of materials",
    CARE_PROMPT = "Use one Care Package?\n\nYou may now take %s from your main character. This addon only keeps count: it never moves gold or items.",
    CARE_YES = "Use it",
    CARE_NO = "Cancel",
    CARE_USED = "Care Package used. %d left.",

    -- locked zone and profession warnings (honor system)
    ZONE_LOCKED = "%s is locked: travel only - no quests, kills for XP, gathering or looting.",
    PROFESSION_LOCKED = "%s is locked: do not learn it before its Progressive item has arrived.",
    PROFESSION_ABOVE_CAP = "%s skill %d is above your unlocked tier (%d). Wait for the next Progressive item.",

    -- capture (developer tool)
    CAPTURE_ON = "Capture is on: zones and turned-in quests are logged for the data review.",
    CAPTURE_OFF = "Capture is off.",
    CAPTURE_USAGE = "Use /wfap capture on or /wfap capture off.",

    -- help
    HELP_HEADER = "WoWForeverAP commands:",
    HELP_STATUS = "/wfap status - linked slot, items and checks",
    HELP_LINK = "/wfap link [number] - link this character to a slot",
    HELP_UNLINK = "/wfap unlink - unlink this character",
    HELP_ITEMS = "/wfap items - list received items",
    HELP_RULES = "/wfap rules - economy rules of your slot",
    HELP_CARE = "/wfap care [use] - show or spend a Care Package",
    HELP_CAPTURE = "/wfap capture on|off - log zones and quests for the data review",
}
