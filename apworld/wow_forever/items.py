"""Item table, item class and pool building. Names and ids come from the CSV data (``data_loader``)."""
from typing import TYPE_CHECKING

from BaseClasses import Item, ItemClassification
from Options import OptionError

from . import ids
from .data_loader import GameData, load_game_data

if TYPE_CHECKING:
    from . import WoWForeverWorld

GAME_NAME = "World of Warcraft Forever"
FILLER_ITEM_NAME = "Traveler's Tale"
CARE_PACKAGE_ITEM_NAME = "Care Package"


class WoWForeverItem(Item):
    game = GAME_NAME


def build_item_table(data: GameData) -> dict[str, tuple[int, ItemClassification]]:
    """Every item any seed can contain, over all releases: name -> (id, classification)."""
    table: dict[str, tuple[int, ItemClassification]] = {}
    for zone in data.zones:
        table[zone.item_name] = (ids.item_id(ids.ItemCat.ZONE, zone.ui_map_id), ItemClassification.progression)
    for profession in data.professions:
        table[profession.item_name] = (ids.item_id(ids.ItemCat.PROFESSION_TIER, profession.skill_line_id),
                                       ItemClassification.progression)
    for misc in data.misc_items:
        classification = ItemClassification.useful if misc.kind == "care_package" else ItemClassification.filler
        table[misc.name] = (ids.item_id(misc.category, misc.native_id), classification)
    return table


ITEM_TABLE = build_item_table(load_game_data())
ITEM_NAME_TO_ID = {name: item_id for name, (item_id, _) in ITEM_TABLE.items()}


def build_pool(world: "WoWForeverWorld", location_count: int) -> list[WoWForeverItem]:
    """Zone unlocks (all but the precollected start zone), profession tiers, care packages, then filler.

    Care packages are convenience only and are dropped first when the locations run short.
    Raises OptionError when the progression items alone do not fit into the locations.
    """
    names = [zone.item_name for zone in world.allowed_zones if zone.ui_map_id != world.start_zone.ui_map_id]
    tier_count = len(world.allowed_tiers)
    for profession in world.selected_professions:
        names.extend([profession.item_name] * tier_count)
    if len(names) > location_count:
        raise OptionError(
            f"{world.player_name}: {len(names)} items for only {location_count} locations; "
            "enable more professions or a later content_release")
    care_packages = min(world.options.care_packages.value, location_count - len(names))
    names.extend([CARE_PACKAGE_ITEM_NAME] * care_packages)
    names.extend([world.get_filler_item_name()] * (location_count - len(names)))
    return [world.create_item(name) for name in names]
