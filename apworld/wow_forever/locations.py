"""Location table and per-seed selection. Names and ids come from the CSV data (``data_loader``)."""
import random
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from enum import Enum
from typing import TypeVar

from BaseClasses import Location

from . import ids
from .data_loader import GOAL_LEVEL, GameData, load_game_data
from .items import GAME_NAME

CHARACTER_REGION = "Character"
GOAL_LOCATION_NAME = "Goal"
VICTORY_ITEM_NAME = "Victory"

_T = TypeVar("_T")


class LocationKind(Enum):
    QUEST = "quest"
    LEVEL = "level"
    PROFESSION_SKILL = "profession_skill"
    BOSS = "boss"
    DISCOVERY = "discovery"
    REPUTATION = "reputation"
    PVP = "pvp"


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
    native: int = 0  # native id of the extra categories: encounter id, area id, faction*10+standing, pvp id


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
    for encounter in data.encounters:
        table[encounter.location_name] = ids.location_id(ids.LocCat.BOSS, encounter.encounter_id)
    for discovery in data.discoveries:
        table[discovery.location_name] = ids.location_id(ids.LocCat.AREA_DISCOVERY, discovery.area_id)
    for reputation in data.reputations:
        table[reputation.location_name] = ids.location_id(ids.LocCat.REPUTATION, reputation.native_id)
    for milestone in data.pvp_milestones:
        table[milestone.location_name] = ids.location_id(ids.LocCat.PVP, milestone.pvp_id)
    return table


def milestone_levels(step: int) -> list[int]:
    """Levels with a 'Reach Level' check: every ``step`` levels after 1, and the goal level always."""
    levels = set(range(1 + step, GOAL_LEVEL + 1, step))
    levels.add(GOAL_LEVEL)
    return sorted(levels)


def sample_by_weight(candidates: Sequence[_T], weight: int, rng: random.Random | None) -> list[_T]:
    """``weight`` percent of the candidates (rounded half up, at least one when there are any), in their original
    order. Weight 100 keeps everything and needs no ``rng``."""
    if weight >= 100 or not candidates:
        return list(candidates)
    if rng is None:
        raise ValueError(f"a random generator is needed to sample at weight {weight}")
    count = max(1, (len(candidates) * weight + 50) // 100)
    return [candidates[index] for index in sorted(rng.sample(range(len(candidates)), count))]


def _extra_category_specs(content_release: int, faction: str, allowed_zone_ids: frozenset[int],
                          data: GameData) -> dict[str, list[LocationSpec]]:
    """Every location of the extra categories this release, faction and zone set allows, in data order."""
    def usable(release: int) -> bool:
        return release <= content_release

    bosses = []
    for encounter in data.encounters:
        instance = data.instances_by_id[encounter.instance_id]
        if (usable(encounter.release) and usable(instance.release) and instance.faction in (faction, "both")
                and instance.entrance_ui_map_id in allowed_zone_ids):
            bosses.append(LocationSpec(
                encounter.location_name, ids.location_id(ids.LocCat.BOSS, encounter.encounter_id),
                data.zones_by_id[instance.entrance_ui_map_id].name, LocationKind.BOSS, native=encounter.encounter_id))
    discoveries = [
        LocationSpec(discovery.location_name, ids.location_id(ids.LocCat.AREA_DISCOVERY, discovery.area_id),
                     data.zones_by_id[discovery.ui_map_id].name, LocationKind.DISCOVERY, native=discovery.area_id)
        for discovery in data.discoveries
        if usable(discovery.release) and discovery.ui_map_id in allowed_zone_ids]
    reputations = [
        LocationSpec(reputation.location_name, ids.location_id(ids.LocCat.REPUTATION, reputation.native_id),
                     CHARACTER_REGION, LocationKind.REPUTATION, native=reputation.native_id)
        for reputation in data.reputations
        if (usable(reputation.release) and reputation.faction_side in (faction, "both")
            and allowed_zone_ids.issuperset(reputation.required_ui_map_ids))]
    pvp = [
        LocationSpec(milestone.location_name, ids.location_id(ids.LocCat.PVP, milestone.pvp_id),
                     CHARACTER_REGION, LocationKind.PVP, native=milestone.pvp_id)
        for milestone in data.pvp_milestones if usable(milestone.release)]
    return {"boss": bosses, "discovery": discoveries, "reputation": reputations, "pvp": pvp}


def select_locations(
    content_release: int,
    faction: str,
    allowed_zone_ids: frozenset[int],
    profession_ids: frozenset[int],
    level_step: int,
    profession_step: int,
    data: GameData | None = None,
    category_weights: Mapping[str, int] | None = None,
    rng: random.Random | None = None,
) -> list[LocationSpec]:
    """Locations of one seed (all filtered by release and faction), without the event location.

    ``category_weights`` holds the extra categories (boss, discovery, reputation, pvp) that are on, each with the
    percentage of its eligible locations to include; sampling uses ``rng``. Absent categories add nothing."""
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
    if category_weights:
        eligible = _extra_category_specs(content_release, faction, allowed_zone_ids, data)
        for category, candidates in eligible.items():
            if category in category_weights:
                specs.extend(sample_by_weight(candidates, category_weights[category], rng))
    return specs
