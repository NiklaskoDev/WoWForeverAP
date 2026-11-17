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
    ITEM_CARE_PACKAGE = "Hilfspaket",
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

    -- Wirtschaftsregeln (Ehrensystem)
    RULE_AUCTION_HOUSE = "Auktionshaus",
    RULE_TRADING = "Handel",
    RULE_MAIL = "Post",
    RULE_SHARED_BANKS = "Gilden- und Accountbank",
    RULE_MAIN_BOOSTS = "Hilfe durch einen Hauptcharakter",
    ECONOMY_WARNING = "%s ist in den Wirtschaftsregeln deines Seeds ausgeschaltet. Bitte halte dich daran (Ehrensystem).",
    CARE_MAIL_HINT = "Ein Hilfspaket erlaubt einmal Nehmen von deinem Hauptcharakter (%d übrig): /wfap care use.",
    RULES_HEADER = "Wirtschaftsregeln deines Slots:",
    RULES_LINE = "%s: %s",
    RULES_ALLOWED = "erlaubt",
    RULES_FORBIDDEN = "nicht erlaubt",
    RULES_CARE = "Hilfspaket: einmal bis zu %d Gold oder %d Stapel Material von einem Hauptcharakter nehmen.",
    RULES_MISSING = "Dieser Slot hat keine Wirtschaftsregeln: er stammt von einer älteren apworld-Version.",
    CARE_STATUS = "Hilfspakete: %d verfügbar (%d erhalten, %d benutzt).",
    CARE_NONE = "Kein Hilfspaket verfügbar.",
    CARE_AMOUNT = "bis zu %d Gold oder %d Stapel Material",
    CARE_PROMPT = "Ein Hilfspaket benutzen?\n\nDu darfst dir jetzt %s von deinem Hauptcharakter nehmen. Das Addon zählt nur mit: es bewegt niemals Gold oder Gegenstände.",
    CARE_YES = "Benutzen",
    CARE_NO = "Abbrechen",
    CARE_USED = "Hilfspaket benutzt. %d übrig.",

    -- locked zone and profession warnings (honor system)
    ZONE_LOCKED = "%s ist gesperrt: nur durchreisen - keine Quests, keine Kills für Erfahrung, kein Sammeln oder Looten.",
    PROFESSION_LOCKED = "%s ist gesperrt: Erlerne den Beruf nicht, bevor sein fortschreitendes Item angekommen ist.",
    PROFESSION_ABOVE_CAP = "%s-Fertigkeit %d liegt über deiner freigeschalteten Stufe (%d). Warte auf das nächste fortschreitende Item.",

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
    HELP_RULES = "/wfap rules - Wirtschaftsregeln deines Slots",
    HELP_CARE = "/wfap care [use] - Hilfspakete anzeigen oder benutzen",
    HELP_CAPTURE = "/wfap capture on|off - Zonen und Quests für die Datenprüfung protokollieren",
}
