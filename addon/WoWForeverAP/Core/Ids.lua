-- Id scheme, mirror of apworld/wow_forever/ids.py: id = BASE + category * CATEGORY_SIZE + native.
-- addon/spec/fixtures/ids.lua (generated from ids.py) pins both implementations to the same numbers.
local _, ns = ...

local Ids = {}
ns.Ids = Ids

Ids.BASE = 5100000000
Ids.CATEGORY_SIZE = 10000000
Ids.PROFESSION_SKILL_FACTOR = 1000

Ids.LocCat = {
    QUEST = 1, -- native: questID
    LEVEL = 2, -- native: character level reached
    PROFESSION_SKILL = 3, -- native: skillLineID * 1000 + skill
    BOSS = 4, -- reserved (plan 004)
    AREA_DISCOVERY = 5, -- reserved (plan 004)
    REPUTATION = 6, -- reserved (plan 004)
    LEGACY = 7, -- reserved (plan 004)
    PVP = 8, -- reserved (plan 004)
}

Ids.ItemCat = {
    ZONE = 1, -- native: uiMapID
    PROFESSION_TIER = 2, -- native: skillLineID
    FILLER = 3, -- native: curated id
    CARE_PACKAGE = 4, -- reserved (plan 002)
    DUNGEON_ACCESS = 5, -- reserved
}

local function isCategoryOf(categories, category)
    for _, value in pairs(categories) do
        if value == category then
            return true
        end
    end
    return false
end

local function encode(categories, category, native)
    if not isCategoryOf(categories, category) then
        error("unknown category " .. tostring(category), 3)
    end
    if type(native) ~= "number" or native < 0 or native >= Ids.CATEGORY_SIZE or native % 1 ~= 0 then
        error("native id " .. tostring(native) .. " out of range", 3)
    end
    return Ids.BASE + category * Ids.CATEGORY_SIZE + native
end

--- Location id of a category and native id; raises an error when either is invalid.
function Ids.locationId(category, native)
    return encode(Ids.LocCat, category, native)
end

--- Item id of a category and native id; raises an error when either is invalid.
function Ids.itemId(category, native)
    return encode(Ids.ItemCat, category, native)
end

--- Native id of a profession-skill location (skillLineID * 1000 + skill).
function Ids.professionSkillNative(skillLineId, skill)
    if type(skill) ~= "number" or skill < 0 or skill >= Ids.PROFESSION_SKILL_FACTOR then
        error("skill " .. tostring(skill) .. " out of range", 2)
    end
    return skillLineId * Ids.PROFESSION_SKILL_FACTOR + skill
end

--- Splits an id into (category, native); raises an error below BASE.
function Ids.decode(id)
    local offset = id - Ids.BASE
    if offset < 0 then
        error("id " .. tostring(id) .. " is below BASE", 2)
    end
    local native = offset % Ids.CATEGORY_SIZE
    return (offset - native) / Ids.CATEGORY_SIZE, native
end

--- Like decode, but returns nothing for a value that is not a number or lies below BASE.
function Ids.tryDecode(id)
    if type(id) ~= "number" or id < Ids.BASE then
        return nil
    end
    return Ids.decode(id)
end
