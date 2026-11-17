-- The addon window (/wfap): tabs Checks, Items, Hints, Rules, built on Blizzard's ButtonFrameTemplate, tabs and
-- ScrollBox list so it looks like part of the game. What it shows is decided by pure functions of a snapshot
-- (Panel.rows, Panel.headerLines, Panel.message); the frame code below only displays their result.
-- Templates and functions (checked against the 12.x UI source): ButtonFrameTemplate, PanelTabButtonTemplate,
-- WowScrollBoxList, MinimalScrollBar, UIPanelButtonTemplate, CreateScrollBoxListLinearView, ScrollUtil,
-- CreateDataProvider, PanelTemplates_SetNumTabs/SetTab, ButtonFrameTemplate_HidePortrait. A missing template
-- makes /wfap say so in chat instead of raising an error.
local _, ns = ...

local Panel = {}
ns.Panel = Panel

local FRAME_NAME = "WoWForeverAPPanel"
local MAX_LISTED = 8 -- values named in a compact row ("Levels: 2, 3, ... (+55 more)"); the tooltip lists them all
local SECOND = 1
local MINUTE, HOUR, DAY = 60 * SECOND, 3600 * SECOND, 86400 * SECOND

Panel.TABS = { "checks", "items", "hints", "rules" }
local TAB_LABEL_KEYS = { checks = "TAB_CHECKS", items = "TAB_ITEMS", hints = "TAB_HINTS", rules = "TAB_RULES" }

local Style = ns.Style

--- What the panel knows about the logged-in character: the db, the inbox, the character record and, when it is
--- linked, the slot key and the inbox slot (nil while the inbox lacks it).
function Panel.snapshot()
    local guid = ns.ready and UnitGUID("player")
    local inbox = ns.Inbox.current()
    local snapshot = { db = ns.db, inbox = inbox, now = time(), character = guid and ns.db.characters[guid] }
    local slotKey = snapshot.character and snapshot.character.slotKey
    if slotKey then
        snapshot.slotKey = slotKey
        snapshot.slot = ns.Inbox.slot(inbox, slotKey)
    end
    return snapshot
end

--- "linked" (rows to show), "missing" (linked, but the inbox lacks the slot) or "unlinked".
function Panel.state(snapshot)
    if not snapshot.slotKey then
        return "unlinked"
    end
    return snapshot.slot and "linked" or "missing"
end

--- "12 min": age of the inbox in the largest fitting unit; a clock that runs backwards counts as "just now".
function Panel.ageText(seconds)
    seconds = math.max(seconds, 0)
    if seconds < MINUTE then
        return ns.L.AGE_LESS_THAN_MINUTE
    elseif seconds < HOUR then
        return ns.L.AGE_MINUTES:format(math.floor(seconds / MINUTE))
    elseif seconds < DAY then
        return ns.L.AGE_HOURS:format(math.floor(seconds / HOUR))
    end
    return ns.L.AGE_DAYS:format(math.floor(seconds / DAY))
end

--- The two meta lines above the list: the slot, then waiting checks and the age of the data.
function Panel.headerLines(snapshot)
    local waiting = ns.DB.unsyncedCount(snapshot.db, snapshot.slotKey, ns.Inbox.checkedSet(snapshot.slot))
    local segments = {}
    if waiting > 0 then
        segments[#segments + 1] = ns.L.PANEL_WAITING:format(waiting)
    end
    local written = ns.Inbox.written(snapshot.inbox)
    if written then
        segments[#segments + 1] = ns.L.PANEL_AGE:format(Panel.ageText(snapshot.now - written))
    else
        segments[#segments + 1] = ns.L.PANEL_AGE_UNKNOWN
    end
    return ns.L.PANEL_SLOT:format(Style.escape(snapshot.slotKey)), table.concat(segments, " - ")
end

--- What replaces the list while the character cannot show one: { lines = { text, ... }, linkSlotKey = key or nil }.
--- `linkSlotKey` is set when exactly one slot exists, so one button can link the character to it.
function Panel.message(snapshot)
    if snapshot.slotKey then
        return { lines = { ns.L.SLOT_MISSING:format(Style.escape(snapshot.slotKey)) } }
    end
    local keys = ns.Inbox.slotKeys(snapshot.inbox)
    if #keys == 0 then
        return { lines = { ns.L.PANEL_NO_INBOX } }
    elseif #keys == 1 then
        return { lines = { ns.L.PANEL_UNLINKED }, linkSlotKey = keys[1] }
    end
    local lines = { ns.L.PANEL_CHOOSE }
    for index, key in ipairs(keys) do
        lines[#lines + 1] = ns.L.LINK_SLOT_LINE:format(index, Style.escape(key))
    end
    return { lines = lines }
end

-- Rows: { kind = "header" | "row" | "empty", text, indent = bool, color = Style colour, tooltip = { lines } }.
local function header(text)
    return { kind = "header", text = text }
end

local function row(text, extra)
    local entry = { kind = "row", text = text }
    for key, value in pairs(extra or {}) do
        entry[key] = value
    end
    return entry
end

local function empty(text)
    return { kind = "empty", text = text }
end

--- "2, 3, 4 (+55 more)" for a long list, the whole list otherwise; second value: the whole list, for a tooltip.
local function compactList(values)
    local names = {}
    for index, value in ipairs(values) do
        names[index] = tostring(value)
    end
    local shown = table.concat(names, ", ", 1, math.min(#names, MAX_LISTED))
    if #names > MAX_LISTED then
        shown = ns.L.CHECKS_MORE:format(shown, #names - MAX_LISTED)
    end
    return shown, table.concat(names, ", ")
end

local function zoneHeader(group)
    if group.uiMapId == ns.Checks.UNKNOWN_ZONE then
        return header(ns.L.CHECKS_UNKNOWN_ZONE)
    end
    local label = ns.L[Style.STATE_LABEL_KEYS[group.state]]
    return header(ns.L.CHECKS_ZONE_HEADER:format(ns.Names.zone(group.uiMapId), label, #group.quests))
end

local function characterRows(character)
    local rows = {}
    if #character.levels > 0 then
        local shown, all = compactList(character.levels)
        rows[#rows + 1] = row(ns.L.CHECKS_LEVELS:format(shown), { indent = true, tooltip = { all } })
    end
    local skillLineIds = {}
    for skillLineId in pairs(character.professions) do
        skillLineIds[#skillLineIds + 1] = skillLineId
    end
    table.sort(skillLineIds)
    for _, skillLineId in ipairs(skillLineIds) do
        local shown, all = compactList(character.professions[skillLineId])
        local name = ns.Names.profession(skillLineId)
        rows[#rows + 1] = row(ns.L.CHECKS_PROFESSION:format(name, shown), {
            indent = true, tooltip = { ns.L.CHECKS_PROFESSION:format(name, all) },
        })
    end
    if #rows > 0 then
        table.insert(rows, 1, header(ns.L.CHECKS_CHARACTER_HEADER))
    end
    return rows
end

local function checksRows(snapshot)
    local pending = ns.DB.outboxIds(snapshot.db, snapshot.slotKey)
    local rows = {}
    for _, group in ipairs(ns.Checks.openByZone(snapshot.slot, pending)) do
        rows[#rows + 1] = zoneHeader(group)
        for _, questId in ipairs(group.quests) do
            rows[#rows + 1] = row(Style.escape(ns.Names.quest(questId)), { indent = true })
        end
    end
    for _, entry in ipairs(characterRows(ns.Checks.openCharacter(snapshot.slot, pending))) do
        rows[#rows + 1] = entry
    end
    return #rows > 0 and rows or { empty(ns.L.CHECKS_EMPTY) }
end

local function itemRows(snapshot)
    local received = ns.Inbox.items(snapshot.slot)
    if #received == 0 then
        return { empty(ns.L.ITEMS_EMPTY) }
    end
    local rows = {}
    for _, line in ipairs(ns.Names.itemLines(received, 1, #received)) do
        rows[#rows + 1] = row(Style.escape(line)) -- the sender is another player's name
    end
    return rows
end

local function hintText(hint, other)
    local format = hint.found and ns.L.HINT_LINE_FOUND or ns.L.HINT_LINE
    return format:format(Style.escape(hint.item), Style.escape(hint.location), Style.escape(other))
end

local function hintRow(hint)
    local other = hint.ourItem and hint.finder or hint.receiver
    return row(hintText(hint, other), {
        indent = true,
        color = hint.found and Style.COLORS.checked or nil,
        tooltip = {
            hintText(hint, other),
            ns.L.HINT_FINDER:format(Style.escape(hint.finder)),
            ns.L.HINT_RECEIVER:format(Style.escape(hint.receiver)),
        },
    })
end

local function validHint(hint)
    return type(hint) == "table" and type(hint.item) == "string" and type(hint.location) == "string"
        and type(hint.finder) == "string" and type(hint.receiver) == "string"
end

local function hintRows(snapshot)
    local ours, others = {}, {}
    for _, hint in ipairs(ns.Inbox.hints(snapshot.slot)) do
        if validHint(hint) then
            local list = hint.ourItem and ours or others
            list[#list + 1] = hintRow(hint)
        end
    end
    if #ours + #others == 0 then
        return { empty(ns.L.HINTS_EMPTY) }
    end
    local rows = {}
    for _, group in ipairs({ { ns.L.HINTS_OURS, ours }, { ns.L.HINTS_OTHERS, others } }) do
        if #group[2] > 0 then
            rows[#rows + 1] = header(group[1])
            for _, entry in ipairs(group[2]) do
                rows[#rows + 1] = entry
            end
        end
    end
    return rows
end

local function ruleRows(snapshot)
    local rows = { header(ns.L.RULES_HONOR_HEADER) }
    for _, key in ipairs({ "RULES_HONOR_ZONES", "RULES_HONOR_PROFESSIONS", "RULES_HONOR_LINK" }) do
        rows[#rows + 1] = row(ns.L[key], { indent = true, tooltip = { ns.L[key] } })
    end
    rows[#rows + 1] = header(ns.L.RULES_ECONOMY_HEADER)
    local lines, economy = ns.Economy.ruleLines(snapshot.slot)
    if not lines then
        rows[#rows + 1] = empty(ns.L.RULES_MISSING)
        return rows
    end
    for _, line in ipairs(lines) do
        rows[#rows + 1] = row(line, { indent = true })
    end
    local terms = ns.L.RULES_CARE:format(economy.carePackageGold or 0, economy.carePackageStacks or 0)
    rows[#rows + 1] = row(terms, { indent = true, tooltip = { terms } })
    local received = ns.Economy.carePackagesReceived(snapshot.slot)
    local available = ns.Economy.carePackagesAvailable(snapshot.db, snapshot.slotKey, snapshot.slot)
    local used = ns.DB.carePackagesUsed(snapshot.db, snapshot.slotKey)
    rows[#rows + 1] = row(ns.L.CARE_STATUS:format(available, received, used), { indent = true })
    return rows
end

local ROW_BUILDERS = { checks = checksRows, items = itemRows, hints = hintRows, rules = ruleRows }

--- The rows of a tab for a linked snapshot (Panel.state == "linked"). Never empty: an empty tab gives one
--- "empty" row that names the next step.
function Panel.rows(tabKey, snapshot)
    return ROW_BUILDERS[tabKey](snapshot)
end

-- Frame -------------------------------------------------------------------------------------------------------

local frame
Panel.activeTab = "checks"

local function savedPoint()
    local point = ns.db and ns.db.ui and ns.db.ui.panelPoint
    if type(point) == "table" and type(point[1]) == "string" and type(point[2]) == "string"
        and type(point[3]) == "number" and type(point[4]) == "number" then
        return point
    end
end

local function savePoint()
    local point, _, relativePoint, x, y = frame:GetPoint()
    if ns.db and ns.db.ui and point then
        ns.db.ui.panelPoint = { point, relativePoint, x, y }
    end
end

local function applyTextColor(fontString, tone)
    fontString:SetTextColor(tone.r, tone.g, tone.b)
end

local function showRowTooltip(button)
    local data = button.rowData
    local lines = data and data.tooltip
    local label = button.label
    if not lines and label and type(label.IsTruncated) == "function" and label:IsTruncated() then
        lines = { data.text }
    end
    if not (lines and GameTooltip) then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    for _, line in ipairs(lines) do
        GameTooltip:AddLine(line, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function hideRowTooltip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

local function initRow(button, data)
    if not button.label then
        button.label = button:CreateFontString(nil, "OVERLAY", Style.FONTS.row)
        button.label:SetJustifyH("LEFT")
        button.label:SetWordWrap(false)
        button:SetScript("OnEnter", showRowTooltip)
        button:SetScript("OnLeave", hideRowTooltip)
    end
    button.rowData = data
    local fontKey = data.kind == "header" and "header" or (data.kind == "empty" and "meta" or "row")
    button.label:SetFontObject(Style.FONTS[fontKey])
    applyTextColor(button.label, data.color or (data.kind == "header" and Style.COLORS.accent) or Style.COLORS.text)
    local left = data.indent and Style.SPACING.lg or Style.SPACING.xs
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", button, "LEFT", left, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -Style.SPACING.xs, 0)
    button.label:SetText(data.text)
end

local function buildList(parent)
    local list = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    local inset = parent.Inset
    list:SetPoint("TOPLEFT", inset, "TOPLEFT", Style.SPACING.xs, -Style.SPACING.xs)
    list:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -(Style.SPACING.lg + Style.SPACING.xs), Style.SPACING.xs)
    bar:SetPoint("TOPLEFT", list, "TOPRIGHT", Style.SPACING.xs, 0)
    bar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", Style.SPACING.xs, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(Style.ROW_HEIGHT)
    view:SetElementInitializer("Button", initRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(list, bar, view)
    return list, bar
end

local function buildMessage(parent)
    local text = parent:CreateFontString(nil, "OVERLAY", Style.FONTS.row)
    local inset = parent.Inset
    text:SetPoint("TOPLEFT", inset, "TOPLEFT", Style.SPACING.lg, -Style.SPACING.lg)
    text:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -Style.SPACING.lg, -Style.SPACING.lg)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(180, 24)
    button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -Style.SPACING.lg)
    button:SetText(ns.L.PANEL_LINK_BUTTON)
    button:SetScript("OnClick", function()
        if button.slotKey then
            ns.Link.linkPlayer(button.slotKey)
            Panel.refresh()
        end
    end)
    return text, button
end

local function buildTabs(parent)
    local tabs = {}
    for index, key in ipairs(Panel.TABS) do
        local tab = CreateFrame("Button", nil, parent, "PanelTabButtonTemplate")
        tab:SetID(index)
        tab:SetText(ns.L[TAB_LABEL_KEYS[key]])
        if index == 1 then
            tab:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", Style.SPACING.md - 1, 2)
        end
        tab:SetScript("OnClick", function()
            Panel.selectTab(index)
        end)
        tabs[index] = tab
    end
    parent.Tabs = tabs -- PanelTemplates_* reads the tabs from here
    if PanelTemplates_SetNumTabs and PanelTemplates_SetTab then
        PanelTemplates_SetNumTabs(parent, #tabs)
        PanelTemplates_SetTab(parent, 1)
    end
    return tabs
end

local function buildFrame()
    local created = CreateFrame("Frame", FRAME_NAME, UIParent, "ButtonFrameTemplate")
    if ButtonFrameTemplate_HidePortrait then
        ButtonFrameTemplate_HidePortrait(created)
    end
    if created.SetTitle then
        created:SetTitle(ns.L.PANEL_TITLE)
    end
    created:SetSize(Style.WINDOW.width, Style.WINDOW.height)
    local point = savedPoint()
    if point then
        created:SetPoint(point[1], UIParent, point[2], point[3], point[4])
    else
        created:SetPoint("CENTER")
    end
    created:SetMovable(true)
    created:SetClampedToScreen(true)
    created:EnableMouse(true)
    created:RegisterForDrag("LeftButton")
    created:SetScript("OnDragStart", created.StartMoving)
    created:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePoint()
    end)
    created:SetScript("OnShow", Panel.refresh)
    created:Hide()
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, FRAME_NAME) -- Esc closes the window
    end

    created.Line1 = created:CreateFontString(nil, "OVERLAY", Style.FONTS.header)
    created.Line1:SetPoint("TOPLEFT", created, "TOPLEFT", Style.SPACING.md, -Style.SPACING.xl - Style.SPACING.xs)
    created.Line1:SetJustifyH("LEFT")
    applyTextColor(created.Line1, Style.COLORS.accent)
    created.Line2 = created:CreateFontString(nil, "OVERLAY", Style.FONTS.meta)
    created.Line2:SetPoint("TOPLEFT", created.Line1, "BOTTOMLEFT", 0, -Style.SPACING.xs)
    created.Line2:SetPoint("RIGHT", created, "RIGHT", -Style.SPACING.md, 0)
    created.Line2:SetJustifyH("LEFT")
    created.Line2:SetWordWrap(false)

    created.List, created.ScrollBar = buildList(created)
    created.Message, created.LinkButton = buildMessage(created)
    created.TabButtons = buildTabs(created)
    return created
end

--- Builds the window once. Returns it, or nil when this client lacks a template (the caller tells the player).
function Panel.create()
    if frame then
        return frame
    end
    local ok, built = pcall(buildFrame)
    if ok then
        frame = built
    end
    return frame
end

local function showTabs(shown)
    for _, tab in ipairs(frame.TabButtons) do
        tab:SetShown(shown)
    end
end

local function showMessage(snapshot)
    local message = Panel.message(snapshot)
    frame.Line1:SetText("")
    frame.Line2:SetText("")
    frame.List:Hide()
    frame.ScrollBar:Hide()
    showTabs(false)
    frame.Message:SetText(table.concat(message.lines, "\n"))
    frame.Message:Show()
    frame.LinkButton.slotKey = message.linkSlotKey
    frame.LinkButton:SetShown(message.linkSlotKey ~= nil)
end

local function showRows(snapshot)
    local line1, line2 = Panel.headerLines(snapshot)
    frame.Line1:SetText(line1)
    frame.Line2:SetText(line2)
    frame.Message:Hide()
    frame.LinkButton:Hide()
    showTabs(true)
    frame.List:Show()
    frame.List:SetDataProvider(CreateDataProvider(Panel.rows(Panel.activeTab, snapshot)))
end

--- Redraws the window from the current state; does nothing while it is closed.
function Panel.refresh()
    if not (frame and frame:IsShown()) then
        return
    end
    local snapshot = Panel.snapshot()
    if Panel.state(snapshot) == "linked" then
        showRows(snapshot)
    else
        showMessage(snapshot)
    end
end

function Panel.selectTab(index)
    Panel.activeTab = Panel.TABS[index] or Panel.TABS[1]
    if frame and PanelTemplates_SetTab then
        PanelTemplates_SetTab(frame, index)
    end
    Panel.refresh()
end

--- Opens the window, or closes it when it is open. Says so in chat when the client cannot build it.
function Panel.toggle()
    if not ns.ready then
        ns.Notify.say(ns.dbError or "DB_NEWER")
        return
    end
    if not Panel.create() then
        ns.Notify.say("PANEL_UNAVAILABLE")
        return
    end
    frame:SetShown(not frame:IsShown())
end
