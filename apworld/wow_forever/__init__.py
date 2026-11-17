import json
import pkgutil
from typing import Any, ClassVar

from BaseClasses import Tutorial
from Options import OptionError
from worlds.AutoWorld import WebWorld, World
from worlds.LauncherComponents import Component, Type, components, launch

from . import items, locations, regions, rules
from .data_loader import GameData, Profession, ProfessionMaterial, ProfessionTier, Zone, load_game_data
from .items import CARE_PACKAGE_ITEM_NAME, FILLER_ITEM_NAME, GAME_NAME, ITEM_NAME_TO_ID, ITEM_TABLE, WoWForeverItem
from .locations import GOAL_LEVEL, LocationSpec, build_location_name_to_id
from .options import RANDOM_START_ZONE, WoWForeverOptions
from .settings import WoWForeverSettings

SLOT_DATA_SCHEMA = 1
EARLY_ZONE_LEVEL = 11  # the early zone must be able to carry a character past the start zone's range
WORLD_VERSION_FALLBACK = "0.0.0"


def run_client(*args: str) -> None:
    # Imported lazily: the client module pulls in the GUI stack, which generation must not need.
    from .client.wow_client import launch_client

    launch(launch_client, name="World of Warcraft Forever Client", args=args)


components.append(Component("World of Warcraft Forever Client", func=run_client, game_name=GAME_NAME,
                            component_type=Type.CLIENT))


class WoWForeverWeb(WebWorld):
    theme = "grassFlowers"
    setup_en = Tutorial(
        "Multiworld Setup Guide",
        "Set up World of Warcraft: Forever with the Archipelago client and the WoWForeverAP addon.",
        "English",
        "setup_en.md",
        "setup/en",
        ["WoWForeverAP contributors"],
    )
    tutorials = [setup_en]


class WoWForeverWorld(World):
    """
    World of Warcraft: Forever as an honor-system multiworld. Zones and profession tiers are the items;
    quest turn-ins, character levels and profession skill milestones are the checks. Reach level 60 to win.
    """

    game = GAME_NAME
    web = WoWForeverWeb()
    options_dataclass = WoWForeverOptions
    options: WoWForeverOptions
    settings_key = "wow_forever_options"
    settings: ClassVar[WoWForeverSettings]

    item_name_to_id = ITEM_NAME_TO_ID
    location_name_to_id = build_location_name_to_id(load_game_data())

    data: GameData
    content_release: int
    faction: str
    allowed_zones: tuple[Zone, ...]
    start_zone: Zone
    selected_professions: tuple[Profession, ...]
    selected_skill_line_ids: frozenset[int]
    material_sources: dict[tuple[int, int], tuple[ProfessionMaterial, ...]]
    care_package_count: int
    allowed_tiers: tuple[ProfessionTier, ...]
    bracket_zone_ids: dict[int, tuple[int, ...]]
    location_specs: list[LocationSpec]

    def generate_early(self) -> None:
        self.data = load_game_data()
        self.content_release = self.options.content_release.value
        self.faction = self.options.faction.current_key
        self.allowed_zones = tuple(
            zone for zone in self.data.zones
            if zone.release <= self.content_release and zone.faction in (self.faction, "both"))
        self.start_zone = self._resolve_start_zone()
        self.allowed_tiers = tuple(tier for tier in self.data.profession_tiers if tier.release <= self.content_release)
        self.selected_professions = tuple(
            profession for profession in self.data.professions
            if profession.key in self.options.professions.value and profession.release <= self.content_release)
        self.selected_skill_line_ids = frozenset(profession.skill_line_id for profession in self.selected_professions)
        self.material_sources = rules.compute_material_sources(self.data, self.content_release)
        self._check_self_found_materials()
        self.bracket_zone_ids = rules.compute_bracket_zone_ids(self.allowed_zones)
        self.location_specs = locations.select_locations(
            self.content_release, self.faction, frozenset(zone.ui_map_id for zone in self.allowed_zones),
            frozenset(profession.skill_line_id for profession in self.selected_professions),
            self.options.level_milestone_step.value, self.options.profession_milestone_step.value, self.data)

    def _check_self_found_materials(self) -> None:
        missing = rules.unreachable_material_sources(self)
        if not missing:
            return
        needs = "; ".join(f"{profession.name} needs {', '.join(gatherer.name for gatherer in gatherers)}"
                          for profession, gatherers in missing.items())
        raise OptionError(
            f"{self.player_name}: {needs}. Those gathering professions are not in professions, and the Auction "
            "House, trading, mail and shared banks are all off, so the materials could not be obtained. "
            "Select them or turn one of those options on")

    def _resolve_start_zone(self) -> Zone:
        start_zones = [zone for zone in self.allowed_zones if zone.is_start]
        chosen = self.options.start_zone.value
        if chosen == RANDOM_START_ZONE:
            if not start_zones:
                raise OptionError(f"{self.player_name}: no start zone exists for faction {self.faction} "
                                  "in this content_release")
            return self.random.choice(sorted(start_zones, key=lambda zone: zone.ui_map_id))
        zone = self.data.zones_by_id[chosen]
        if zone.faction not in (self.faction, "both"):
            raise OptionError(f"{self.player_name}: start zone {zone.name} is a {zone.faction} zone, "
                              f"but the faction is {self.faction}")
        if zone.release > self.content_release:
            raise OptionError(f"{self.player_name}: start zone {zone.name} is not part of the chosen content_release")
        return zone

    def create_regions(self) -> None:
        regions.create_regions(self)

    def create_item(self, name: str) -> WoWForeverItem:
        item_id, classification = ITEM_TABLE[name]
        return WoWForeverItem(name, classification, item_id, self.player)

    def create_items(self) -> None:
        location_count = len(self.multiworld.get_unfilled_locations(self.player))
        pool = items.build_pool(self, location_count)
        self.care_package_count = sum(1 for item in pool if item.name == CARE_PACKAGE_ITEM_NAME)
        self.multiworld.itempool += pool
        self.multiworld.push_precollected(self.create_item(self.start_zone.item_name))
        early_zone = self._pick_early_zone()
        if early_zone is not None:
            self.multiworld.early_items[self.player][early_zone.item_name] = 1

    def _pick_early_zone(self) -> Zone | None:
        candidates = sorted(
            (zone for zone in self.allowed_zones
             if zone.ui_map_id != self.start_zone.ui_map_id and zone.min_level <= EARLY_ZONE_LEVEL <= zone.max_level),
            key=lambda zone: zone.ui_map_id)
        return self.random.choice(candidates) if candidates else None

    def set_rules(self) -> None:
        rules.set_rules(self)

    def get_filler_item_name(self) -> str:
        return FILLER_ITEM_NAME

    def fill_slot_data(self) -> dict[str, Any]:
        return {
            "schema": SLOT_DATA_SCHEMA,
            "world_version": self._world_version(),
            "faction": self.faction,
            "start_zone": self.start_zone.ui_map_id,
            "content_release": self.content_release,
            "goal_level": GOAL_LEVEL,
            "professions": [profession.skill_line_id for profession in self.selected_professions],
            "level_step": self.options.level_milestone_step.value,
            "profession_step": self.options.profession_milestone_step.value,
            "economy": {
                "auctionHouse": bool(self.options.allow_auction_house),
                "trading": bool(self.options.allow_trading),
                "mail": bool(self.options.allow_mail),
                "sharedBanks": bool(self.options.allow_shared_banks),
                "mainBoosts": bool(self.options.allow_main_boosts),
                "carePackages": self.care_package_count,
                "carePackageGold": self.options.care_package_gold.value,
                "carePackageStacks": self.options.care_package_stacks.value,
            },
        }

    @classmethod
    def _world_version(cls) -> str:
        raw = pkgutil.get_data(__name__, "archipelago.json")
        return json.loads(raw)["world_version"] if raw else WORLD_VERSION_FALLBACK
