"""Access rules: pure functions of ``(state, world)``; the only place that knows the logic."""
from typing import TYPE_CHECKING

from BaseClasses import CollectionState
from worlds.generic.Rules import set_rule

from .data_loader import MaterialBracket, ProfessionTier, Zone
from .locations import GOAL_LEVEL, GOAL_LOCATION_NAME, LocationKind, LocationSpec

if TYPE_CHECKING:
    from . import WoWForeverWorld

LEVEL_BRACKET_SIZE = 5  # logic needs a zone that covers every 5th level on the way up


def compute_bracket_zone_ids(zones: tuple[Zone, ...]) -> dict[int, tuple[int, ...]]:
    """For every level bracket start (1, 6, 11, ...) the zones whose level range contains it."""
    return {
        bracket: tuple(zone.ui_map_id for zone in zones if zone.min_level <= bracket <= zone.max_level)
        for bracket in range(1, GOAL_LEVEL, LEVEL_BRACKET_SIZE)
    }


def has_zone(state: CollectionState, world: "WoWForeverWorld", ui_map_id: int) -> bool:
    """The start zone is always open; every other zone needs its unlock item."""
    if ui_map_id == world.start_zone.ui_map_id:
        return True
    return state.has(world.data.zones_by_id[ui_map_id].item_name, world.player)


def can_reach_level(state: CollectionState, world: "WoWForeverWorld", level: int) -> bool:
    """A character can level to ``level`` when every 5-level bracket below it has an unlocked zone."""
    for bracket in range(1, level, LEVEL_BRACKET_SIZE):
        if not any(has_zone(state, world, zone_id) for zone_id in world.bracket_zone_ids.get(bracket, ())):
            return False
    return True


def tier_for(world: "WoWForeverWorld", skill: int) -> ProfessionTier:
    """The profession tier a skill value belongs to (lowest tier whose max_skill covers it)."""
    for tier in world.allowed_tiers:
        if skill <= tier.max_skill:
            return tier
    raise ValueError(f"skill {skill} is above the highest tier of this content release")


def bracket_for(world: "WoWForeverWorld", skill: int) -> MaterialBracket:
    """The material bracket a skill value belongs to."""
    for bracket in world.data.material_brackets:
        if skill <= bracket.max_skill:
            return bracket
    raise ValueError(f"skill {skill} is above the highest material bracket")


def has_profession_tier(state: CollectionState, world: "WoWForeverWorld", skill_line_id: int, skill: int) -> bool:
    """The progressive profession item has unlocked the tier and the character is high enough to train it."""
    tier = tier_for(world, skill)
    item_name = world.data.professions_by_id[skill_line_id].item_name
    return state.count(item_name, world.player) >= tier.tier and can_reach_level(state, world, tier.required_level)


def has_material_access(state: CollectionState, world: "WoWForeverWorld", skill_line_id: int, skill: int) -> bool:
    """Single seam for material logic (plan 002 extends it): self-gathering needs the bracket's level."""
    return can_reach_level(state, world, bracket_for(world, skill).required_level)


def _quest_rule(world: "WoWForeverWorld", spec: LocationSpec):
    quest = world.data.quests_by_id[spec.quest_id]
    return lambda state: (all(has_zone(state, world, zone_id) for zone_id in quest.effective_zones)
                          and can_reach_level(state, world, quest.effective_level))


def _rule_for(world: "WoWForeverWorld", spec: LocationSpec):
    if spec.kind is LocationKind.QUEST:
        return _quest_rule(world, spec)
    if spec.kind is LocationKind.LEVEL:
        return lambda state: can_reach_level(state, world, spec.level)
    return lambda state: (has_profession_tier(state, world, spec.skill_line_id, spec.skill)
                          and has_material_access(state, world, spec.skill_line_id, spec.skill))


def set_rules(world: "WoWForeverWorld") -> None:
    """Attach rules to every location and set the completion condition."""
    for spec in world.location_specs:
        set_rule(world.get_location(spec.name), _rule_for(world, spec))
    set_rule(world.get_location(GOAL_LOCATION_NAME), lambda state: can_reach_level(state, world, GOAL_LEVEL))
    world.multiworld.completion_condition[world.player] = lambda state: state.has("Victory", world.player)
