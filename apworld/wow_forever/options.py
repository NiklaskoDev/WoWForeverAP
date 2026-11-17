import re
from dataclasses import dataclass

from Options import Choice, DefaultOnToggle, OptionSet, PerGameCommonOptions, Range, Toggle

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


class AllowAuctionHouse(DefaultOnToggle):
    """Characters may use the Auction House. Off: no buying or selling there (honor system)."""
    display_name = "Allow Auction House"


class AllowTrading(DefaultOnToggle):
    """Characters may trade with other players. Off: no trade window (honor system)."""
    display_name = "Allow Trading"


class AllowMail(DefaultOnToggle):
    """Characters may send and receive mail with items or gold. Off: no mailbox (honor system)."""
    display_name = "Allow Mail"


class AllowSharedBanks(Toggle):
    """Characters may use the guild bank and the account (warband) bank. Off: neither (honor system)."""
    display_name = "Allow Shared Banks"


class AllowMainBoosts(Toggle):
    """Dungeon carries and power levelling by a main character are allowed. Honor system only: it does not
    change which checks are in logic."""
    display_name = "Allow Main Boosts"


class CarePackages(Range):
    """How many Care Package items are added to the item pool. Each one allows a single pull from a main
    character: up to Care Package Gold gold or Care Package Stacks stacks of materials. Honor system, never
    required by the logic. They are the first items dropped when there are fewer locations than items."""
    display_name = "Care Packages"
    range_start = 0
    range_end = 20
    default = 5


class CarePackageGold(Range):
    """Gold one Care Package allows you to pull from a main character (or the stacks of materials below)."""
    display_name = "Care Package Gold"
    range_start = 0
    range_end = 10000
    default = 50


class CarePackageStacks(Range):
    """Stacks of crafting materials one Care Package allows you to pull from a main character (or the gold above)."""
    display_name = "Care Package Stacks"
    range_start = 0
    range_end = 20
    default = 5


class BossChecks(DefaultOnToggle):
    """Killing a dungeon boss is a check, for dungeons whose entrance zone is in the seed."""
    display_name = "Boss Checks"


class BossWeight(Range):
    """Percentage of the eligible boss checks that are included in the seed (at least one when any are eligible)."""
    display_name = "Boss Weight"
    range_start = 1
    range_end = 100
    default = 100


class DiscoveryChecks(DefaultOnToggle):
    """Discovering a map area (the parts of a zone map that are revealed as you explore) is a check. Unlike
    reputation and PvP, an area you explored before linking counts when you stand in it again: the game does not
    say when an area was discovered."""
    display_name = "Discovery Checks"


class DiscoveryWeight(Range):
    """Percentage of the eligible area discoveries that are included in the seed (at least one when any are
    eligible). There are many of them: lower this for a shorter seed."""
    display_name = "Discovery Weight"
    range_start = 1
    range_end = 100
    default = 100


class ReputationChecks(Toggle):
    """Reaching Friendly, Honored, Revered or Exalted with a city or Steamwheedle Cartel faction is a check.
    Only standing gained after the character was linked counts."""
    display_name = "Reputation Checks"


class ReputationWeight(Range):
    """Percentage of the eligible reputation checks that are included in the seed (at least one when any are
    eligible)."""
    display_name = "Reputation Weight"
    range_start = 1
    range_end = 100
    default = 100


class PvpChecks(Toggle):
    """Honorable-kill totals and a first win in each battleground are checks. Only kills and wins after the
    character was linked count. Whether battlegrounds are open depends on the Forever release."""
    display_name = "PvP Checks"


class PvpWeight(Range):
    """Percentage of the eligible PvP checks that are included in the seed (at least one when any are eligible)."""
    display_name = "PvP Weight"
    range_start = 1
    range_end = 100
    default = 100


# Category key (slot data, location selection) -> names of its toggle and weight in WoWForeverOptions.
CATEGORY_OPTIONS = {
    "boss": ("boss_checks", "boss_weight"),
    "discovery": ("discovery_checks", "discovery_weight"),
    "reputation": ("reputation_checks", "reputation_weight"),
    "pvp": ("pvp_checks", "pvp_weight"),
}


@dataclass
class WoWForeverOptions(PerGameCommonOptions):
    faction: Faction
    start_zone: StartZone
    content_release: ContentRelease
    professions: Professions
    level_milestone_step: LevelMilestoneStep
    profession_milestone_step: ProfessionMilestoneStep
    allow_auction_house: AllowAuctionHouse
    allow_trading: AllowTrading
    allow_mail: AllowMail
    allow_shared_banks: AllowSharedBanks
    allow_main_boosts: AllowMainBoosts
    care_packages: CarePackages
    care_package_gold: CarePackageGold
    care_package_stacks: CarePackageStacks
    boss_checks: BossChecks
    boss_weight: BossWeight
    discovery_checks: DiscoveryChecks
    discovery_weight: DiscoveryWeight
    reputation_checks: ReputationChecks
    reputation_weight: ReputationWeight
    pvp_checks: PvpChecks
    pvp_weight: PvpWeight


def category_switches(options: WoWForeverOptions) -> dict[str, bool]:
    """Which extra check categories are on, by category key."""
    return {key: bool(getattr(options, toggle)) for key, (toggle, _) in CATEGORY_OPTIONS.items()}


def category_weights(options: WoWForeverOptions) -> dict[str, int]:
    """Weight (percent) of every extra check category that is on; categories that are off are absent."""
    return {key: getattr(options, weight).value for key, (toggle, weight) in CATEGORY_OPTIONS.items()
            if getattr(options, toggle)}
