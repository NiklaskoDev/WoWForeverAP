-- Linking a character to an Archipelago slot. The rules are pure functions of (db, inbox, ...);
-- linkPlayer and the StaticPopup wrap them with the live game state.
local _, ns = ...

local Link = {}
ns.Link = Link

local POPUP = "WOWFOREVERAP_LINK"

--- Faction names compare case-insensitively: the game says "Alliance", the slot data "alliance".
function Link.factionMatches(characterFaction, slotFaction)
    return type(characterFaction) == "string" and type(slotFaction) == "string"
        and characterFaction:lower() == slotFaction:lower()
end

--- What to do at login: "prompt" (one slot, ask), "hint" (several slots, tell how to choose) or nil.
--- The second return value is the slot key for "prompt".
function Link.loginAction(db, guid, inbox)
    local character = db.characters[guid]
    if not character or character.slotKey or character.neverAsk then
        return nil
    end
    local keys = ns.Inbox.slotKeys(inbox)
    if #keys == 1 then
        return "prompt", keys[1]
    elseif #keys > 1 then
        return "hint"
    end
    return nil
end

--- Links the character to the slot. `skills` maps skillLineID to the current rank.
--- Returns true plus a list of warning messages, or false plus one error message.
--- A message is { localeKey, formatArgs... }.
function Link.link(db, guid, slotKey, inbox, level, skills, now)
    local character = db.characters[guid]
    local slot = ns.Inbox.slot(inbox, slotKey)
    if not character or not slot then
        return false, { "LINK_BAD_SLOT" }
    end
    if character.slotKey then
        return false, { "LINK_ALREADY", character.slotKey }
    end
    local slotFaction = ns.Inbox.options(slot).faction
    if not Link.factionMatches(character.faction, slotFaction) then
        return false, { "LINK_FACTION_MISMATCH", tostring(character.faction), tostring(slotFaction) }
    end
    character.slotKey = slotKey
    character.linkedAt = now
    character.linkedLevel = level
    character.skillAtLink = skills
    character.seenItemCount = 0
    character.neverAsk = nil
    local warnings = {}
    if level > 1 then
        warnings[#warnings + 1] = { "LINK_LEVEL_WARNING", level }
    end
    return true, warnings
end

--- Removes the link; checks already in the outbox stay and are still sent. Returns false when not linked.
function Link.unlink(db, guid)
    local character = db.characters[guid]
    if not character or not character.slotKey then
        return false
    end
    character.slotKey = nil
    character.linkedAt = nil
    character.linkedLevel = nil
    character.skillAtLink = nil
    character.seenItemCount = nil
    return true
end

local function sayMessage(message)
    ns.Notify.say(unpack(message))
end

--- Links the logged-in character to `slotKey` and tells the player the outcome.
function Link.linkPlayer(slotKey)
    local guid = ns.ready and UnitGUID("player")
    if not guid then
        return false
    end
    local skills = ns.Professions.currentRanks() or {}
    local ok, result = Link.link(ns.db, guid, slotKey, ns.Inbox.current(), UnitLevel("player"), skills, time())
    if not ok then
        sayMessage(result)
        return false
    end
    ns.Notify.say("LINK_OK", ns.db.characters[guid].name, slotKey)
    for _, warning in ipairs(result) do
        sayMessage(warning)
    end
    return true
end

local function showPopup(slotKey)
    local guid = UnitGUID("player")
    local character = guid and ns.db.characters[guid]
    if character then
        StaticPopup_Show(POPUP, character.name, slotKey, { slotKey = slotKey })
    end
end

--- Called at login: asks to link when exactly one slot exists, hints when several do.
function Link.promptIfNeeded()
    local guid = ns.ready and UnitGUID("player")
    if not guid then
        return
    end
    local action, slotKey = Link.loginAction(ns.db, guid, ns.Inbox.current())
    if action == "prompt" then
        showPopup(slotKey)
    elseif action == "hint" then
        ns.Notify.say("LINK_HINT")
    end
end

StaticPopupDialogs[POPUP] = {
    text = ns.L.LINK_PROMPT, -- %s: character name, %s: slot key (text_arg1, text_arg2 of StaticPopup_Show)
    button1 = ns.L.LINK_YES,
    button2 = ns.L.LINK_NO,
    button3 = ns.L.LINK_NEVER,
    OnAccept = function(_, data)
        Link.linkPlayer(data.slotKey)
    end,
    OnAlt = function()
        local guid = UnitGUID("player")
        if guid and ns.db.characters[guid] then
            ns.db.characters[guid].neverAsk = true
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}
