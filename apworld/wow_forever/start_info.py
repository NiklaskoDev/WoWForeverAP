"""Plain-text summary of a slot's faction, start zone, goal level and professions.

Pure and free of client imports, so the spoiler log (generation) and the client's /start share it. It reads only
slot data keys that exist since v0.1.0.
"""
from collections.abc import Mapping
from typing import Any

from .data_loader import GameData

UNKNOWN = "unknown"
NONE = "none"


def _zone_name(zone_id: Any, data: GameData) -> str:
    zone = data.zones_by_id.get(zone_id)
    return zone.name if zone else f"zone {zone_id}"


def _profession_names(skill_line_ids: Any, data: GameData, kind: str) -> str:
    names = []
    for skill_line_id in skill_line_ids:
        profession = data.professions_by_id.get(skill_line_id)
        if profession is None:  # an id this data does not know is shown rather than dropped
            if kind == "primary":
                names.append(f"profession {skill_line_id}")
        elif profession.kind == kind:
            names.append(profession.name)
    return ", ".join(names) or NONE


def start_info_lines(slot_data: Mapping[str, Any], data: GameData) -> list[str]:
    """The five lines of the start info; a missing slot data key shows as "unknown"."""
    faction = slot_data.get("faction")
    zone_id = slot_data.get("start_zone")
    goal = slot_data.get("goal_level")
    professions = slot_data.get("professions")
    primary = secondary = UNKNOWN
    if professions is not None:
        primary = _profession_names(professions, data, "primary")
        secondary = _profession_names(professions, data, "secondary")
    return [
        f"Faction: {str(faction).capitalize() if faction else UNKNOWN}",
        f"Start zone: {_zone_name(zone_id, data) if zone_id is not None else UNKNOWN}",
        f"Goal level: {goal if goal is not None else UNKNOWN}",
        f"Primary professions: {primary}",
        f"Secondary professions: {secondary}",
    ]
