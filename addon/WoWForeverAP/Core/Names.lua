-- Localised display names for zones, professions, quests, locations and items.
-- Game APIs are optional and guarded; the English names generated from the CSVs are the last fallback.
local _, ns = ...

local Names = {}
ns.Names = Names

local function present(value)
    return type(value) == "string" and value ~= "" and value or nil
end

local tryCall = ns.tryCall

function Names.zone(uiMapId)
    local info = C_Map and tryCall(C_Map.GetMapInfo, uiMapId)
    local name = type(info) == "table" and present(info.name)
    if name then
        return name
    end
    local zone = ns.Data.zones[uiMapId]
    return zone and zone.name or ns.L.ZONE_FMT:format(uiMapId)
end

function Names.profession(skillLineId)
    local info = C_TradeSkillUI and tryCall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineId)
    local name = type(info) == "table" and present(info.professionName)
    if name then
        return name
    end
    local profession = ns.Data.professions[skillLineId]
    return profession and profession.name or ns.L.PROFESSION_FMT:format(skillLineId)
end

function Names.quest(questId)
    local title = C_QuestLog and present(tryCall(C_QuestLog.GetTitleForQuestID, questId))
    return title or ns.L.QUEST_FMT:format(questId)
end

--- Boss kill, "Instance: Boss": the client has no localised boss names, so the generated English names stand.
function Names.boss(encounterId)
    local boss = ns.Data.bosses[encounterId]
    return boss and ("%s: %s"):format(boss.instance, boss.name) or ns.L.BOSS_FMT:format(encounterId)
end

function Names.area(areaId)
    local name = C_Map and present(tryCall(C_Map.GetAreaInfo, areaId))
    if name then
        return name
    end
    local area = ns.Data.areas[areaId]
    return area and area.name or ns.L.AREA_FMT:format(areaId)
end

--- Display name of a slot's faction key ("alliance" / "horde", any case); anything else is shown as it is.
function Names.side(key)
    local lower = type(key) == "string" and key:lower()
    if lower == "alliance" then
        return ns.L.SIDE_ALLIANCE
    elseif lower == "horde" then
        return ns.L.SIDE_HORDE
    end
    return tostring(key)
end

--- Reputation faction by id.
function Names.faction(factionId)
    local data = C_Reputation and tryCall(C_Reputation.GetFactionDataByID, factionId)
    local name = type(data) == "table" and present(data.name)
    if name then
        return name
    end
    return ns.Data.factions[factionId] or ns.L.FACTION_FMT:format(factionId)
end

--- Name of a reputation standing id (5 Friendly ... 8 Exalted).
function Names.standing(standing)
    local key = "STANDING_" .. tostring(standing)
    return ns.L[key] ~= key and ns.L[key] or tostring(standing)
end

--- PvP milestone: kill totals are formatted with the count, battleground wins use the generated English name.
function Names.pvp(pvpId)
    local row = ns.Data.pvp[pvpId]
    if not row then
        return ns.L.PVP_FMT:format(pvpId)
    end
    return row.kind == "hk_total" and ns.L.PVP_HK_CHECK:format(row.param) or row.name
end

local decode = ns.Ids.tryDecode

--- Display name of a location id.
function Names.location(locationId)
    local category, native = decode(locationId)
    if category == ns.Ids.LocCat.QUEST then
        return Names.quest(native)
    elseif category == ns.Ids.LocCat.LEVEL then
        return ns.L.LEVEL_CHECK:format(native)
    elseif category == ns.Ids.LocCat.PROFESSION_SKILL then
        local skillLineId = math.floor(native / ns.Ids.PROFESSION_SKILL_FACTOR)
        return ns.L.PROFESSION_CHECK:format(Names.profession(skillLineId), native % ns.Ids.PROFESSION_SKILL_FACTOR)
    elseif category == ns.Ids.LocCat.BOSS then
        return Names.boss(native)
    elseif category == ns.Ids.LocCat.AREA_DISCOVERY then
        return ns.L.AREA_CHECK:format(Names.area(native))
    elseif category == ns.Ids.LocCat.REPUTATION then
        return ns.L.REPUTATION_CHECK:format(Names.faction(math.floor(native / 10)), Names.standing(native % 10))
    elseif category == ns.Ids.LocCat.PVP then
        return Names.pvp(native)
    end
    return tostring(locationId)
end

local function fillerName(native)
    local key = "FILLER_" .. native
    local text = ns.L[key]
    if text ~= key then
        return text
    end
    local filler = ns.Data.fillers[native]
    return filler and filler.name or ns.L.ITEM_UNKNOWN:format(tostring(native))
end

--- Display name of an item id; `tier` is how many progressive items of that profession were received so far.
function Names.item(itemId, tier)
    local category, native = decode(itemId)
    if category == ns.Ids.ItemCat.ZONE then
        return ns.L.ITEM_ZONE:format(Names.zone(native))
    elseif category == ns.Ids.ItemCat.PROFESSION_TIER then
        return ns.L.ITEM_PROFESSION_TIER:format(Names.profession(native), tier or 1)
    elseif category == ns.Ids.ItemCat.FILLER then
        return fillerName(native)
    elseif category == ns.Ids.ItemCat.CARE_PACKAGE then
        return ns.L.ITEM_CARE_PACKAGE
    end
    return ns.L.ITEM_UNKNOWN:format(tostring(itemId))
end

--- Chat lines for received items number `first` to `last` (1-based, in received order).
--- Walks from the start so every progressive profession item shows the tier it unlocked.
function Names.itemLines(received, first, last)
    local lines, seen = {}, {}
    for index = 1, math.min(last, #received) do
        local item = received[index]
        seen[item.id] = (seen[item.id] or 0) + 1
        if index >= first then
            local sender = type(item.sender) == "string" and item.sender or "?"
            lines[#lines + 1] = ns.L.ITEM_LINE:format(Names.item(item.id, seen[item.id]), sender)
        end
    end
    return lines
end
