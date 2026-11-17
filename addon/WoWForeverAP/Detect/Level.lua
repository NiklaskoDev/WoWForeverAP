-- Character levels: PLAYER_LEVEL_UP(level) becomes "Reach Level" checks and, at the goal level, the goal.
local _, ns = ...

local Level = {}
ns.Level = Level

--- Level that wins the game for this slot (from the slot data; the generated constant as fallback).
function Level.goalLevel(slot)
    return ns.Inbox.options(slot).goalLevel or ns.Data.levelGoal
end

--- Levels L with `fromLevel < L <= toLevel` that carry a check in this seed, ascending.
--- Passing the level the character linked at as `fromLevel` keeps progress made before linking out.
function Level.milestones(slot, fromLevel, toLevel)
    local levels = {}
    for level = fromLevel + 1, toLevel do
        local ok, locationId = pcall(ns.Ids.locationId, ns.Ids.LocCat.LEVEL, level)
        if ok and ns.Inbox.isLocationInSeed(slot, locationId) then
            levels[#levels + 1] = level
        end
    end
    return levels
end

function Level.onLevelUp(level)
    local guid = ns.ready and type(level) == "number" and UnitGUID("player")
    if not guid then
        return
    end
    local character, _, slot = ns.Tracker.linkedSlot(ns.db, ns.Inbox.current(), guid)
    if not slot then
        return
    end
    for _, milestone in ipairs(Level.milestones(slot, character.linkedLevel or 0, level)) do
        ns.Tracker.recordForPlayer(ns.Ids.locationId(ns.Ids.LocCat.LEVEL, milestone))
    end
    if level >= Level.goalLevel(slot) then
        ns.Tracker.goalForPlayer()
    end
end

ns.Events.register("PLAYER_LEVEL_UP", Level.onLevelUp)
