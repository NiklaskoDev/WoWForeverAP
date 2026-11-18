"""Access rules: pure functions of ``(state, world)``; the only place that knows the logic."""
from collections.abc import Iterable
from typing import TYPE_CHECKING

from BaseClasses import CollectionState
from worlds.generic.Rules import set_rule

from .data_loader import GameData, MaterialBracket, Profession, ProfessionMaterial, ProfessionTier, Zone
from .locations import GOAL_LOCATION_NAME, LocationKind, LocationSpec

if TYPE_CHECKING:
    from . import WoWForeverWorld

LEVEL_BRACKET_SIZE = 5  # logic needs a zone that covers every 5th level on the way up


def compute_bracket_zone_ids(zones: tuple[Zone, ...], goal_level: int) -> dict[int, tuple[int, ...]]:
    """For every level bracket start (1, 6, 11, ...) the zones whose level range contains it."""
    return {
        bracket: tuple(zone.ui_map_id for zone in zones if zone.min_level <= bracket <= zone.max_level)
        for bracket in range(1, goal_level, LEVEL_BRACKET_SIZE)
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


def has_market_access(world: "WoWForeverWorld") -> bool:
    """Characters may get materials from other players: Auction House, trading, mail or a shared bank."""
    options = world.options
    return bool(options.allow_auction_house or options.allow_trading or options.allow_mail
                or options.allow_shared_banks)


def compute_material_sources(data: GameData,
                             content_release: int) -> dict[tuple[int, int], tuple[ProfessionMaterial, ...]]:
    """The material sources of the content release, per (crafting skill line, bracket max_skill)."""
    sources: dict[tuple[int, int], list[ProfessionMaterial]] = {}
    for material in data.profession_materials:
        if material.release <= content_release:
            sources.setdefault((material.crafting_skill_line_id, material.max_skill), []).append(material)
    return {key: tuple(rows) for key, rows in sources.items()}


def _has_material_source(state: CollectionState, world: "WoWForeverWorld", source: ProfessionMaterial) -> bool:
    if not can_reach_level(state, world, source.required_level):
        return False
    if source.source != "gather":
        return True
    gatherer = world.data.professions_by_id[source.gather_skill_line_id]
    return (gatherer.skill_line_id in world.selected_skill_line_ids
            and state.count(gatherer.item_name, world.player) >= tier_for(world, source.gather_skill).tier)


def has_material_access(state: CollectionState, world: "WoWForeverWorld", skill_line_id: int, skill: int) -> bool:
    """Materials for the skill bracket.

    With market access (Auction House, trading, mail or a shared bank) the bracket's level is enough. Otherwise
    one of the profession's own sources must work: loot and vendors need the level, gathering also needs the
    gathering profession and its tier. Professions or brackets without source rows keep the level-only rule.
    """
    bracket = bracket_for(world, skill)
    sources = world.material_sources.get((skill_line_id, bracket.max_skill))
    if has_market_access(world) or not sources:
        return can_reach_level(state, world, bracket.required_level)
    return any(_has_material_source(state, world, source) for source in sources)


def missing_gatherers(professions: Iterable[Profession],
                      material_sources: dict[tuple[int, int], tuple[ProfessionMaterial, ...]],
                      data: GameData) -> dict[Profession, list[Profession]]:
    """Crafting professions among `professions` that could not get materials by themselves: profession -> the
    gathering professions outside the set they would need."""
    selected = tuple(professions)
    selected_ids = {profession.skill_line_id for profession in selected}
    missing: dict[Profession, list[Profession]] = {}
    for profession in selected:
        needed: list[Profession] = []
        for (crafting_line, _), sources in material_sources.items():
            if crafting_line != profession.skill_line_id or any(s.source != "gather" for s in sources):
                continue
            gatherers = [data.professions_by_id[s.gather_skill_line_id] for s in sources]
            if all(g.skill_line_id not in selected_ids for g in gatherers):
                needed.extend(g for g in gatherers if g not in needed)
        if needed:
            missing[profession] = needed
    return missing


def unreachable_material_sources(world: "WoWForeverWorld") -> dict[Profession, list[Profession]]:
    """Selected crafting professions that cannot get materials by themselves: profession -> the unselected
    gathering professions they would need. Empty with market access."""
    if has_market_access(world):
        return {}
    return missing_gatherers(world.selected_professions, world.material_sources, world.data)


def _quest_rule(world: "WoWForeverWorld", spec: LocationSpec):
    quest = world.data.quests_by_id[spec.quest_id]
    return lambda state: (all(has_zone(state, world, zone_id) for zone_id in quest.effective_zones)
                          and can_reach_level(state, world, quest.effective_level))


def _boss_rule(world: "WoWForeverWorld", spec: LocationSpec):
    """The entrance zone is unlocked and the character is at the instance's level; raids need the goal level."""
    instance = world.data.instances_by_id[world.data.encounters_by_id[spec.native].instance_id]
    level = max(instance.min_level, world.goal_level) if instance.kind == "raid" else instance.min_level
    return lambda state: (has_zone(state, world, instance.entrance_ui_map_id)
                          and can_reach_level(state, world, level))


def _reputation_rule(world: "WoWForeverWorld", spec: LocationSpec):
    reputation = world.data.reputations_by_native[spec.native]
    return lambda state: (all(has_zone(state, world, zone_id) for zone_id in reputation.required_ui_map_ids)
                          and can_reach_level(state, world, reputation.required_level))


def _rule_for(world: "WoWForeverWorld", spec: LocationSpec):
    if spec.kind is LocationKind.QUEST:
        return _quest_rule(world, spec)
    if spec.kind is LocationKind.LEVEL:
        return lambda state: can_reach_level(state, world, spec.level)
    if spec.kind is LocationKind.BOSS:
        return _boss_rule(world, spec)
    if spec.kind is LocationKind.DISCOVERY:
        ui_map_id = world.data.discoveries_by_id[spec.native].ui_map_id
        return lambda state: has_zone(state, world, ui_map_id)
    if spec.kind is LocationKind.REPUTATION:
        return _reputation_rule(world, spec)
    if spec.kind is LocationKind.PVP:
        required_level = world.data.pvp_by_id[spec.native].required_level
        return lambda state: can_reach_level(state, world, required_level)
    return lambda state: (has_profession_tier(state, world, spec.skill_line_id, spec.skill)
                          and has_material_access(state, world, spec.skill_line_id, spec.skill))


def set_rules(world: "WoWForeverWorld") -> None:
    """Attach rules to every location and set the completion condition."""
    for spec in world.location_specs:
        set_rule(world.get_location(spec.name), _rule_for(world, spec))
    set_rule(world.get_location(GOAL_LOCATION_NAME), lambda state: can_reach_level(state, world, world.goal_level))
    world.multiworld.completion_condition[world.player] = lambda state: state.has("Victory", world.player)
