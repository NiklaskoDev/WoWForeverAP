-- Profession skill: SKILL_LINES_CHANGED, then a scan of the player's professions for new skill milestones.
-- Primary API: GetProfessions() + GetProfessionInfo(index). Fallback: C_TradeSkillUI.GetProfessionInfoBySkillLineID.
-- (GetSkillLineInfo, the Classic-era call, does not exist in the Mainline 12.x client.)
local _, ns = ...

local Professions = {}
ns.Professions = Professions

local GET_PROFESSIONS_RETURNS = 6 -- two primary, archaeology, fishing, cooking, first aid

local warnedMissingApi = false

--- Reads {[skillLineID] = rank} through GetProfessions/GetProfessionInfo (passed in, so specs can fake them).
function Professions.readRanks(getProfessions, getProfessionInfo)
    local ranks = {}
    for position = 1, GET_PROFESSIONS_RETURNS do
        local index = select(position, getProfessions())
        if index then
            local _, _, rank, _, _, _, skillLine = getProfessionInfo(index)
            if type(skillLine) == "number" and type(rank) == "number" then
                ranks[skillLine] = rank
            end
        end
    end
    return ranks
end

--- Reads {[skillLineID] = rank} for every profession of the data through the per-skill-line API.
function Professions.readRanksBySkillLine(getInfoBySkillLine, skillLineIds)
    local ranks = {}
    for _, skillLineId in ipairs(skillLineIds) do
        local ok, info = pcall(getInfoBySkillLine, skillLineId)
        if ok and type(info) == "table" and type(info.skillLevel) == "number" and info.skillLevel > 0 then
            ranks[skillLineId] = info.skillLevel
        end
    end
    return ranks
end

local function dataSkillLineIds()
    local ids = {}
    for skillLineId in pairs(ns.Data.professions) do
        ids[#ids + 1] = skillLineId
    end
    table.sort(ids)
    return ids
end

--- Current ranks of the player's professions; nil plus the missing API name when no known API exists.
function Professions.currentRanks()
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        return Professions.readRanks(GetProfessions, GetProfessionInfo)
    end
    if C_TradeSkillUI and type(C_TradeSkillUI.GetProfessionInfoBySkillLineID) == "function" then
        return Professions.readRanksBySkillLine(C_TradeSkillUI.GetProfessionInfoBySkillLineID, dataSkillLineIds())
    end
    return nil, "GetProfessions"
end

--- Location ids of the profession milestones passed since linking: for every profession of the slot,
--- each skill s with `skillAtLink[line] < s <= rank` that carries a check in this seed.
function Professions.milestones(slot, skillAtLink, ranks)
    local found = {}
    local lines = {}
    for _, skillLineId in ipairs(ns.Inbox.options(slot).professions or {}) do
        lines[#lines + 1] = skillLineId
    end
    table.sort(lines)
    for _, skillLineId in ipairs(lines) do
        for skill = (skillAtLink[skillLineId] or 0) + 1, ranks[skillLineId] or 0 do
            local ok, native = pcall(ns.Ids.professionSkillNative, skillLineId, skill)
            local locationId = ok and ns.Ids.locationId(ns.Ids.LocCat.PROFESSION_SKILL, native)
            if locationId and ns.Inbox.isLocationInSeed(slot, locationId) then
                found[#found + 1] = locationId
            end
        end
    end
    return found
end

function Professions.scan()
    local guid = ns.ready and UnitGUID("player")
    if not guid then
        return
    end
    local character, _, slot = ns.Tracker.linkedSlot(ns.db, ns.Inbox.current(), guid)
    if not slot then
        return
    end
    local ranks, missingApi = Professions.currentRanks()
    if not ranks then
        if not warnedMissingApi then
            warnedMissingApi = true
            ns.Notify.say("API_MISSING", missingApi)
        end
        return
    end
    for _, locationId in ipairs(Professions.milestones(slot, character.skillAtLink or {}, ranks)) do
        ns.Tracker.recordForPlayer(locationId)
    end
end

ns.Events.register("SKILL_LINES_CHANGED", Professions.scan)
