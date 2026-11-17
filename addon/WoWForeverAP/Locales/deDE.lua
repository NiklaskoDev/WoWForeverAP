-- Deutsche Texte. Fehlt ein Schlüssel, greift enUS. Die Schlüssel müssen zu enUS.lua passen (ein Spec prüft das).
local _, ns = ...

ns.locales.deDE = {
    -- check detection and sync reminders
    CHECK_RECORDED = "Check erfasst: %s",
    UNSYNCED = "%d Checks warten - /reload oder Ausloggen sendet sie",
    GOAL_REACHED = "Ziel erreicht! /reload oder Ausloggen sendet es.",
    LEVEL_CHECK = "Stufe %d erreichen",
    PROFESSION_CHECK = "%s %d",
    QUEST_FMT = "Quest %d",
    ZONE_FMT = "Zone %d",
    PROFESSION_FMT = "Beruf %d",

    -- items
    ITEM_ZONE = "Zone: %s",
    ITEM_PROFESSION_TIER = "Fortschreitend %s (Stufe %d)",
    ITEM_UNKNOWN = "Unbekannter Gegenstand %s",
    FILLER_1 = "Geschichte eines Reisenden",
    ITEM_LINE = "%s (von %s)",
    NEW_ITEMS = "%d neue Gegenstände seit deinem letzten Blick:",
    MORE_ITEMS = "... und %d weitere, siehe /wfap items",
    ITEMS_HEADER = "Erhaltene Gegenstände (%d):",
    ITEMS_EMPTY = "Noch keine Gegenstände erhalten.",

    -- linking
    LINK_PROMPT = "%s mit dem Archipelago-Slot \"%s\" verknüpfen?\n\nAb jetzt zählen Quests, Stufen und Berufsfertigkeiten dieses Charakters als Checks.",
    LINK_YES = "Verknüpfen",
    LINK_NO = "Jetzt nicht",
    LINK_NEVER = "Nie fragen",
    LINK_OK = "%s ist jetzt mit dem Slot %s verknüpft.",
    LINK_ALREADY = "Dieser Charakter ist bereits mit dem Slot %s verknüpft. Nutze zuerst /wfap unlink.",
    LINK_FACTION_MISMATCH = "Dieser Charakter gehört zu %s, der Slot spielt aber %s: Verknüpfen nicht möglich.",
    LINK_LEVEL_WARNING = "Dieser Charakter ist Stufe %d. Fortschritt vor dem Verknüpfen zählt nicht.",
    LINK_BAD_SLOT = "Dieser Slot ist nicht in der Inbox. Starte den Client und /reload.",
    LINK_BAD_INDEX = "Nutze /wfap link <Nummer> mit einer der Nummern oben.",
    LINK_NO_SLOTS = "Kein Slot gefunden. Starte den Archipelago-Client, verbinde ihn, dann /reload.",
    LINK_CHOOSE = "Mehrere Slots gefunden. Wähle einen mit /wfap link <Nummer>:",
    LINK_SLOT_LINE = "%d: %s",
    LINK_HINT = "Mehrere Slots gefunden. Verknüpfe diesen Charakter mit /wfap link <Nummer>.",
    UNLINK_OK = "Dieser Charakter ist nicht mehr verknüpft.",
    NOT_LINKED = "Dieser Charakter ist nicht verknüpft. Nutze /wfap link.",

    -- status
    STATUS_LINKED = "Verknüpft mit Slot %s.",
    STATUS_ITEMS = "Erhaltene Gegenstände: %d",
    STATUS_OPEN = "Offene Checks: %d",
    STATUS_UNSYNCED = "Checks, die noch gesendet werden müssen: %d",
    STATUS_SLOTS = "Slots in der Inbox: %d",

    -- problems
    SLOT_MISSING = "Slot %s ist nicht in der Inbox. Starte den Client dafür, dann /reload.",
    INBOX_INVALID = "Die Inbox fehlt oder ist beschädigt. Prüfe, ob der Client laeuft, und /reload.",
    DB_NEWER = "Die gespeicherten Daten stammen von einer neueren Addon-Version. Das Addon bleibt inaktiv, um sie zu schuetzen.",
    API_MISSING = "Berufs-Checks sind nicht verfügbar: die Spiel-API %s existiert in diesem Client nicht.",

    -- capture (developer tool)
    CAPTURE_ON = "Capture ist an: Zonen und abgegebene Quests werden für die Datenprüfung protokolliert.",
    CAPTURE_OFF = "Capture ist aus.",
    CAPTURE_USAGE = "Nutze /wfap capture on oder /wfap capture off.",

    -- help
    HELP_HEADER = "WoWForeverAP-Befehle:",
    HELP_STATUS = "/wfap status - verknüpfter Slot, Gegenstände und Checks",
    HELP_LINK = "/wfap link [Nummer] - diesen Charakter mit einem Slot verknüpfen",
    HELP_UNLINK = "/wfap unlink - diesen Charakter trennen",
    HELP_ITEMS = "/wfap items - erhaltene Gegenstände auflisten",
    HELP_CAPTURE = "/wfap capture on|off - Zonen und Quests für die Datenprüfung protokollieren",
}
