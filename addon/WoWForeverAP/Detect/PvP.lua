-- PvP: lifetime honorable kills (PLAYER_PVP_KILLS_CHANGED) and battleground wins become checks, counted from the
-- baselines stored when the character was linked. A battleground win is read from PVP_MATCH_COMPLETE(winner) and,
-- as a second source, from UPDATE_BATTLEFIELD_STATUS plus GetBattlefieldWinner(); both are matched to the
-- player's faction and counted once per match. Battleground = the instance id GetInstanceInfo() reports.
-- `character.baselines.bgWins` is not a snapshot like the other baselines: it is the running count of won
-- matches per battleground map id since the character was linked (there is no API for lifetime wins).
local _, ns = ...

local PvP = {}
ns.PvP = PvP

--- The faction numbers the client uses for a match winner (PvPFaction enum): Horde 0, Alliance 1.
PvP.FACTION_INDEX = { Horde = 0, Alliance = 1 }

local matchCounted = false

--- Lifetime honorable kills, nil when the API is missing or answers something else.
function PvP.honorableKills()
    local kills = ns.tryCall(GetPVPLifetimeStats)
    return type(kills) == "number" and kills or nil
end

--- The seed's PvP locations as { { locationId, kind, param }, ... } in location id order; rows the addon data
--- does not know (an addon older than the apworld) are left out.
local function seedRows(slot)
    local rows = {}
    for locationId in pairs(type(slot.locations) == "table" and slot.locations or {}) do
        local category, native = ns.Ids.tryDecode(locationId)
        local row = category == ns.Ids.LocCat.PVP and ns.Data.pvp[native]
        if row then
            rows[#rows + 1] = { locationId = locationId, kind = row.kind, param = row.param }
        end
    end
    table.sort(rows, function(a, b)
        return a.locationId < b.locationId
    end)
    return rows
end

--- Honorable-kill locations reached when the character has `gained` kills since the link.
function PvP.killMilestones(slot, gained)
    local found = {}
    for _, row in ipairs(seedRows(slot)) do
        if row.kind == "hk_total" and gained >= row.param then
            found[#found + 1] = row.locationId
        end
    end
    return found
end

--- Battleground-win locations of the battlegrounds with at least one win in `bgWins` (`{ [mapId] = wins }`).
function PvP.winMilestones(slot, bgWins)
    local found = {}
    for _, row in ipairs(seedRows(slot)) do
        if row.kind == "bg_win" and (bgWins[row.param] or 0) >= 1 then
            found[#found + 1] = row.locationId
        end
    end
    return found
end

function PvP.onKillsChanged()
    local character, _, slot = ns.Tracker.playerContext()
    local kills = slot and PvP.honorableKills()
    if not kills then
        return
    end
    character.baselines = character.baselines or {}
    local baseline = character.baselines.hk
    if not baseline then
        -- The total was unknown at link time: the first successful read becomes the baseline, so the kills made
        -- before the link (or before this read) never count.
        character.baselines.hk = kills
        return
    end
    for _, locationId in ipairs(PvP.killMilestones(slot, kills - baseline)) do
        ns.Tracker.recordForPlayer(locationId)
    end
end

--- Instance id of the instance the player is in (a battleground's map id), nil outside instances.
function PvP.instanceId()
    local _, _, _, _, _, _, _, instanceId = ns.tryCall(GetInstanceInfo)
    return type(instanceId) == "number" and instanceId or nil
end

--- True when `winner` is a faction number equal to the player's. A running match has no winner (nil), and a
--- Neutral or unknown player has no faction number: neither may count as a win. Wrapped in pcall in case the
--- client hands over a restricted value, which raises when compared.
local function playerWon(winner)
    local ok, won = pcall(function()
        local playerIndex = PvP.FACTION_INDEX[UnitFactionGroup("player")]
        return winner ~= nil and playerIndex ~= nil and winner == playerIndex
    end)
    return ok and won
end

--- A match ended with `winner` (a faction number): counts a win for the battleground the player is in when it
--- is the player's faction, once per match.
function PvP.onMatchEnd(winner)
    if matchCounted or not playerWon(winner) then
        return
    end
    local character, _, slot = ns.Tracker.playerContext()
    local mapId = slot and PvP.instanceId()
    if not mapId then
        return
    end
    matchCounted = true
    character.baselines = character.baselines or {}
    local wins = character.baselines.bgWins or {}
    character.baselines.bgWins = wins
    wins[mapId] = (wins[mapId] or 0) + 1
    for _, locationId in ipairs(PvP.winMilestones(slot, wins)) do
        ns.Tracker.recordForPlayer(locationId)
    end
end

function PvP.onBattlefieldStatus()
    PvP.onMatchEnd(ns.tryCall(GetBattlefieldWinner))
end

--- A new match or a loading screen starts a new count.
function PvP.resetMatch()
    matchCounted = false
end

ns.Events.tryRegister("PLAYER_PVP_KILLS_CHANGED", PvP.onKillsChanged)
ns.Events.tryRegister("PVP_MATCH_COMPLETE", PvP.onMatchEnd)
ns.Events.tryRegister("UPDATE_BATTLEFIELD_STATUS", PvP.onBattlefieldStatus)
ns.Events.register("PLAYER_ENTERING_WORLD", PvP.resetMatch)
