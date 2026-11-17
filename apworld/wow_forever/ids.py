"""ID scheme shared by the apworld, the client and (mirrored in Lua) the addon.

``id = BASE + category * CATEGORY_SIZE + native`` with ``0 <= native < CATEGORY_SIZE``.
Category numbers are permanent: a reserved number must never be reused for something else,
and BASE must never change once a release has shipped. Pure module: no Archipelago imports.
"""
from enum import IntEnum

BASE = 5_100_000_000
CATEGORY_SIZE = 10_000_000


class LocCat(IntEnum):
    QUEST = 1  # native: questID
    LEVEL = 2  # native: character level reached
    PROFESSION_SKILL = 3  # native: skillLineID * 1000 + skill
    BOSS = 4  # reserved, plan 004: encounterID
    AREA_DISCOVERY = 5  # reserved, plan 004: areaID
    REPUTATION = 6  # reserved, plan 004: factionID * 10 + standingID
    LEGACY = 7  # reserved, plan 004: curated id
    PVP = 8  # reserved, plan 004: curated id


class ItemCat(IntEnum):
    ZONE = 1  # native: uiMapID
    PROFESSION_TIER = 2  # native: skillLineID
    FILLER = 3  # native: curated id (misc_items.csv)
    CARE_PACKAGE = 4  # reserved, plan 002: curated id
    DUNGEON_ACCESS = 5  # reserved: instance id


PROFESSION_SKILL_FACTOR = 1000


def _encode(category_enum: type[IntEnum], category: int, native: int) -> int:
    try:
        category = category_enum(category)
    except ValueError:
        raise ValueError(f"unknown {category_enum.__name__} category {category}") from None
    if not 0 <= native < CATEGORY_SIZE:
        raise ValueError(f"native id {native} out of range 0..{CATEGORY_SIZE - 1}")
    return BASE + category * CATEGORY_SIZE + native


def location_id(category: int, native: int) -> int:
    """Location id for a category and native id; raises ValueError when either is invalid."""
    return _encode(LocCat, category, native)


def item_id(category: int, native: int) -> int:
    """Item id for a category and native id; raises ValueError when either is invalid."""
    return _encode(ItemCat, category, native)


def profession_skill_native(skill_line_id: int, skill: int) -> int:
    """Native id of a profession-skill location (skillLineID * 1000 + skill)."""
    if not 0 <= skill < PROFESSION_SKILL_FACTOR:
        raise ValueError(f"skill {skill} out of range 0..{PROFESSION_SKILL_FACTOR - 1}")
    return skill_line_id * PROFESSION_SKILL_FACTOR + skill


def decode(identifier: int) -> tuple[int, int]:
    """Split an item or location id into ``(category, native)``; raises ValueError below BASE."""
    offset = identifier - BASE
    if offset < 0:
        raise ValueError(f"id {identifier} is below BASE {BASE}")
    return divmod(offset, CATEGORY_SIZE)
