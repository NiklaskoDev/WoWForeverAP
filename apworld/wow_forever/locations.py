"""Location table and per-seed selection. Names and ids come from the CSV data (``data_loader``)."""
from dataclasses import dataclass
from enum import Enum

from BaseClasses import Location

from . import ids
from .data_loader import GameData, load_game_data
from .items import GAME_NAME

GOAL_LEVEL = 60
CHARACTER_REGION = "Character"
GOAL_LOCATION_NAME = "Goal"
VICTORY_ITEM_NAME = "Victory"


class LocationKind(Enum):
    QUEST = "quest"
    LEVEL = "level"
    PROFESSION_SKILL = "profession_skill"


@dataclass(frozen=True)
class LocationSpec:
    """One location of a seed: where it lives and what the rules need to know about it."""
    name: str
    address: int
    region: str
    kind: LocationKind
    quest_id: int = 0
    level: int = 0
    skill_line_id: int = 0
    skill: int = 0


class WoWForeverLocation(Location):
    game = GAME_NAME


def level_location_name(level: int) -> str:
    return f"Reach Level {level}"


def profession_location_name(profession_name: str, skill: int) -> str:
    return f"{profession_name} {skill}"


def max_tier_skill(data: GameData, content_release: int | None = None) -> int:
    """Highest skill reachable through tiers of releases up to ``content_release`` (all when None)."""
    return max((t.max_skill for t in data.profession_tiers if content_release is None or t.release <= content_release),
               default=0)


def build_location_name_to_id(data: GameData) -> dict[str, int]:
    """Every location name any seed can contain, over all releases, for the static world table."""
    table = {quest.location_name: ids.location_id(ids.LocCat.QUEST, quest.quest_id) for quest in data.quests}
    for level in range(2, GOAL_LEVEL + 1):
        table[level_location_name(level)] = ids.location_id(ids.LocCat.LEVEL, level)
    for profession in data.professions:
        for skill in range(1, max_tier_skill(data) + 1):
            native = ids.profession_skill_native(profession.skill_line_id, skill)
            table[profession_location_name(profession.name, skill)] = ids.location_id(
                ids.LocCat.PROFESSION_SKILL, native)
    return table


def milestone_levels(step: int) -> list[int]:
    """Levels with a 'Reach Level' check: every ``step`` levels after 1, and the goal level always."""
    levels = set(range(1 + step, GOAL_LEVEL + 1, step))
    levels.add(GOAL_LEVEL)
    return sorted(levels)


def select_locations(
    content_release: int,
    faction: str,
    allowed_zone_ids: frozenset[int],
    profession_ids: frozenset[int],
    level_step: int,
    profession_step: int,
    data: GameData | None = None,
) -> list[LocationSpec]:
    """Locations of one seed (all filtered by release and faction), without the event location."""
    data = data or load_game_data()
    specs: list[LocationSpec] = []
    for quest in data.quests:
        if (quest.release <= content_release and quest.faction in (faction, "both")
                and allowed_zone_ids.issuperset(quest.effective_zones)):
            specs.append(LocationSpec(
                quest.location_name, ids.location_id(ids.LocCat.QUEST, quest.quest_id),
                data.zones_by_id[quest.zone_ui_map_id].name, LocationKind.QUEST, quest_id=quest.quest_id))
    for level in milestone_levels(level_step):
        specs.append(LocationSpec(level_location_name(level), ids.location_id(ids.LocCat.LEVEL, level),
                                  CHARACTER_REGION, LocationKind.LEVEL, level=level))
    top_skill = max_tier_skill(data, content_release)
    for profession in data.professions:
        if profession.skill_line_id not in profession_ids or profession.release > content_release:
            continue
        for skill in range(profession_step, top_skill + 1, profession_step):
            native = ids.profession_skill_native(profession.skill_line_id, skill)
            specs.append(LocationSpec(
                profession_location_name(profession.name, skill),
                ids.location_id(ids.LocCat.PROFESSION_SKILL, native), CHARACTER_REGION,
                LocationKind.PROFESSION_SKILL, skill_line_id=profession.skill_line_id, skill=skill))
    return specs
