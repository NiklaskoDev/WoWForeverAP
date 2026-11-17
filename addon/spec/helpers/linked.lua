-- A fresh addon namespace with a logged-in character linked to the slot S1:Wow, for the detector specs.
local Env = require("helpers.addon_env")

local Linked = {}

--- Returns ns, game, db, character. `locations` is a list of location ids the seed holds, `baselines` what the
--- character had when it linked (nil: none), `extraSlot` more inbox slot fields (checked, options, ...).
function Linked.new(locations, baselines, extraSlot)
    local ns, game = Env.new()
    local db = ns.DB.init(nil)
    ns.db, ns.ready = db, true
    local set = {}
    for _, id in ipairs(locations) do
        set[id] = true
    end
    local overrides = { locations = set }
    for key, value in pairs(extraSlot or {}) do
        overrides[key] = value
    end
    _G.WoWForeverAP_Inbox = Env.inbox(overrides)
    local character = ns.DB.touchCharacter(db, game.guid, "Arthas", "Alliance", "PALADIN")
    character.slotKey, character.linkedLevel, character.skillAtLink = "S1:Wow", 1, {}
    character.baselines = baselines
    return ns, game, db, character
end

--- Location ids in the outbox of the slot, in order.
function Linked.outbox(db)
    local found = {}
    local slot = db.slots["S1:Wow"]
    for _, entry in ipairs(slot and slot.outbox or {}) do
        found[#found + 1] = entry.id
    end
    return found
end

return Linked
