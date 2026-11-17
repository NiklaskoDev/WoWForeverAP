import re
from dataclasses import dataclass

from Options import Choice, OptionSet, PerGameCommonOptions, Range

from .data_loader import load_game_data

_DATA = load_game_data()
RANDOM_START_ZONE = 0  # no ui_map_id is 0, so zone options can use their own id as value


def _option_key(name: str) -> str:
    """snake_case option key from a display name, e.g. "Zephra's Isle" -> "zephras_isle"."""
    return re.sub(r"[^a-z0-9]+", "_", name.lower().replace("'", "")).strip("_")


class Faction(Choice):
    """Faction of every character linked to this slot. Zones, quests and start zone must match it."""
    display_name = "Faction"
    option_alliance = 0
    option_horde = 1
    default = 0


# Choice options are read from class attributes at class creation, so the data-driven ones are built with type().
StartZone = type("StartZone", (Choice,), {
    "__doc__": "Zone every character starts in. It is unlocked from the beginning. 'faction_random' picks a start "
               "zone of your faction. A start zone of the other faction is an error. (Archipelago reserves the "
               "plain key 'random': it would pick among all start zones, whatever the faction.)",
    "display_name": "Start Zone",
    "option_faction_random": RANDOM_START_ZONE,
    **{f"option_{_option_key(zone.name)}": zone.ui_map_id for zone in _DATA.zones if zone.is_start},
    "default": RANDOM_START_ZONE,
})

ContentRelease = type("ContentRelease", (Choice,), {
    "__doc__": "Newest content release whose zones, quests and profession tiers can appear in the seed.",
    "display_name": "Content Release",
    **{f"option_{release.key}": release.id for release in _DATA.releases},
    "default": max(release.id for release in _DATA.releases),
})


class Professions(OptionSet):
    """Professions whose tiers are items and whose skill milestones are locations."""
    display_name = "Professions"
    valid_keys = frozenset(profession.key for profession in _DATA.professions)
    default = frozenset(profession.key for profession in _DATA.professions)


class LevelMilestoneStep(Range):
    """Every how many character levels there is a 'Reach Level' check. Level 60 is always a check."""
    display_name = "Level Milestone Step"
    range_start = 1
    range_end = 10
    default = 1


class ProfessionMilestoneStep(Range):
    """Every how many profession skill points there is a check."""
    display_name = "Profession Milestone Step"
    range_start = 5
    range_end = 75
    default = 25


@dataclass
class WoWForeverOptions(PerGameCommonOptions):
    faction: Faction
    start_zone: StartZone
    content_release: ContentRelease
    professions: Professions
    level_milestone_step: LevelMilestoneStep
    profession_milestone_step: ProfessionMilestoneStep
