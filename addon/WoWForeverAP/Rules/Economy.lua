-- Economy rules of the linked slot (honor system): a warning when a window the seed forbids opens, and the
-- Care Package counter. The addon never moves gold or items, it only warns and counts.
-- Primary event: PLAYER_INTERACTION_MANAGER_FRAME_SHOW(type) with Enum.PlayerInteractionType (checked against the
-- 12.x UI source). Fallback when either is missing: the older per-window events.
local _, ns = ...

local Economy = {}
ns.Economy = Economy

local POPUP = "WOWFOREVERAP_CARE"
local INTERACTION_EVENT = "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"

--- Rule keys, in the order /wfap rules lists them. They are the keys of the slot's `options.economy`.
Economy.RULES = { "auctionHouse", "trading", "mail", "sharedBanks", "mainBoosts" }

local RULE_NAME_KEYS = {
    auctionHouse = "RULE_AUCTION_HOUSE",
    trading = "RULE_TRADING",
    mail = "RULE_MAIL",
    sharedBanks = "RULE_SHARED_BANKS",
    mainBoosts = "RULE_MAIN_BOOSTS",
}

-- Enum.PlayerInteractionType member -> the rule the window belongs to.
local INTERACTION_RULES = {
    Auctioneer = "auctionHouse",
    MailInfo = "mail",
    TradePartner = "trading",
    GuildBanker = "sharedBanks",
    AccountBanker = "sharedBanks",
}

-- Fallback events -> rule. The account bank has no older event, so only the primary path covers it.
local LEGACY_EVENT_RULES = {
    AUCTION_HOUSE_SHOW = "auctionHouse",
    MAIL_SHOW = "mail",
    TRADE_SHOW = "trading",
    GUILDBANKFRAME_OPENED = "sharedBanks",
}

local ERROR_COLOR = { 1, 0.1, 0.1, 1 }

--- The slot's economy rules table, nil when the slot has none.
function Economy.rules(slot)
    local economy = ns.Inbox.options(slot).economy
    return type(economy) == "table" and economy or nil
end

--- True only when the seed explicitly forbids the rule; a missing table or key forbids nothing.
function Economy.isForbidden(economy, ruleKey)
    return type(economy) == "table" and economy[ruleKey] == false
end

--- The rule key of an Enum.PlayerInteractionType value, or nil for windows that have no rule.
function Economy.ruleForInteraction(interactionType)
    local types = Enum and Enum.PlayerInteractionType
    if type(types) ~= "table" or interactionType == nil then
        return nil
    end
    for name, ruleKey in pairs(INTERACTION_RULES) do
        if types[name] ~= nil and types[name] == interactionType then
            return ruleKey
        end
    end
    return nil
end

local function used(db, slotKey)
    return ns.DB.carePackagesUsed(db, slotKey)
end

--- Care Packages received so far (items in the inbox).
function Economy.carePackagesReceived(slot)
    return ns.Inbox.countItem(slot, ns.Data.carePackageItemId)
end

--- Care Packages left to use: received minus used, never below 0.
function Economy.carePackagesAvailable(db, slotKey, slot)
    return math.max(Economy.carePackagesReceived(slot) - used(db, slotKey), 0)
end

--- Spends one Care Package. Returns true plus how many are left, or false when none is available.
function Economy.useCarePackage(db, slotKey, slot)
    local available = Economy.carePackagesAvailable(db, slotKey, slot)
    if available <= 0 then
        return false
    end
    ns.DB.addCarePackageUse(db, slotKey)
    return true, available - 1
end

local function showErrorFrame(text)
    if UIErrorsFrame then
        ns.tryCall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, unpack(ERROR_COLOR))
    end
end

--- Shows the warning for a forbidden window: on screen and in chat. With mail forbidden and Care Packages
--- left, the chat line also names the Care Package way out.
function Economy.warn(ruleKey, availableCarePackages)
    local text = ns.L.ECONOMY_WARNING:format(ns.L[RULE_NAME_KEYS[ruleKey]])
    showErrorFrame(text)
    if ruleKey == "mail" and availableCarePackages > 0 then
        text = text .. " " .. ns.L.CARE_MAIL_HINT:format(availableCarePackages)
    end
    ns.Notify.print(text)
end

--- Warns when the logged-in, linked character opens a window the seed forbids.
function Economy.check(ruleKey)
    local guid = ruleKey and ns.ready and UnitGUID("player")
    if not guid then
        return false
    end
    local _, slotKey, slot = ns.Tracker.linkedSlot(ns.db, ns.Inbox.current(), guid)
    if not slot or not Economy.isForbidden(Economy.rules(slot), ruleKey) then
        return false
    end
    Economy.warn(ruleKey, Economy.carePackagesAvailable(ns.db, slotKey, slot))
    return true
end

function Economy.onInteraction(interactionType)
    Economy.check(Economy.ruleForInteraction(interactionType))
end

--- True when the primary event can be used: the enum exists and the client knows the event.
function Economy.hasInteractionManager()
    if not (Enum and type(Enum.PlayerInteractionType) == "table") then
        return false
    end
    local isEventValid = C_EventUtils and C_EventUtils.IsEventValid
    return type(isEventValid) ~= "function" or isEventValid(INTERACTION_EVENT) == true
end

--- Registers the window events; returns the list of event names it registered.
function Economy.register()
    if Economy.hasInteractionManager() then
        ns.Events.register(INTERACTION_EVENT, Economy.onInteraction)
        return { INTERACTION_EVENT }
    end
    local registered = {}
    for event, ruleKey in pairs(LEGACY_EVENT_RULES) do
        -- a client that does not know an event raises an error on registration: skip that event
        local ok = pcall(ns.Events.register, event, function()
            Economy.check(ruleKey)
        end)
        if ok then
            registered[#registered + 1] = event
        end
    end
    table.sort(registered)
    return registered
end

--- The economy rules of the slot as display lines ("Mail: not allowed"), in /wfap rules order, plus the rules
--- table; nil when the slot has no economy rules (made by an older apworld).
function Economy.ruleLines(slot)
    local economy = Economy.rules(slot)
    if not economy then
        return nil
    end
    local lines = {}
    for _, ruleKey in ipairs(Economy.RULES) do
        local state = economy[ruleKey] == false and ns.L.RULES_FORBIDDEN or ns.L.RULES_ALLOWED
        lines[#lines + 1] = ns.L.RULES_LINE:format(ns.L[RULE_NAME_KEYS[ruleKey]], state)
    end
    return lines, economy
end

--- Prints the economy rules of the slot and the Care Package terms.
function Economy.printRules(slot)
    local lines, economy = Economy.ruleLines(slot)
    if not lines then
        ns.Notify.say("RULES_MISSING")
        return
    end
    ns.Notify.say("RULES_HEADER")
    for _, line in ipairs(lines) do
        ns.Notify.print(line)
    end
    ns.Notify.say("RULES_CARE", economy.carePackageGold or 0, economy.carePackageStacks or 0)
end

--- Prints how many Care Packages are left.
function Economy.printCare(db, slotKey, slot)
    local received = Economy.carePackagesReceived(slot)
    local spent = used(db, slotKey)
    ns.Notify.say("CARE_STATUS", Economy.carePackagesAvailable(db, slotKey, slot), received, spent)
end

--- Asks before spending a Care Package; refuses when none is left.
function Economy.askToUse(db, slotKey, slot)
    if Economy.carePackagesAvailable(db, slotKey, slot) <= 0 then
        ns.Notify.say("CARE_NONE")
        return false
    end
    local economy = Economy.rules(slot) or {}
    local amount = ns.L.CARE_AMOUNT:format(economy.carePackageGold or 0, economy.carePackageStacks or 0)
    StaticPopup_Show(POPUP, amount, nil, { slotKey = slotKey })
    return true
end

--- Popup accepted: spends the package against the slot's current inbox state.
function Economy.confirmUse(slotKey)
    local guid = ns.ready and UnitGUID("player")
    local slot = guid and ns.Inbox.slot(ns.Inbox.current(), slotKey)
    if not slot then
        return false
    end
    local ok, left = Economy.useCarePackage(ns.db, slotKey, slot)
    if ok then
        ns.Notify.say("CARE_USED", left)
    else
        ns.Notify.say("CARE_NONE")
    end
    return ok
end

StaticPopupDialogs[POPUP] = {
    text = ns.L.CARE_PROMPT, -- %s: the amount one Care Package allows (text_arg1 of StaticPopup_Show)
    button1 = ns.L.CARE_YES,
    button2 = ns.L.CARE_NO,
    OnAccept = function(_, data)
        Economy.confirmUse(data.slotKey)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

Economy.register()
