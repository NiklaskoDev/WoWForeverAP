"""Region graph: Menu -> one region per allowed zone (needs its unlock) and a Character region."""
from typing import TYPE_CHECKING

from BaseClasses import ItemClassification, Region

from . import rules
from .items import WoWForeverItem
from .locations import (
    CHARACTER_REGION,
    GOAL_LOCATION_NAME,
    VICTORY_ITEM_NAME,
    WoWForeverLocation,
)

if TYPE_CHECKING:
    from . import WoWForeverWorld


def create_regions(world: "WoWForeverWorld") -> None:
    menu = Region("Menu", world.player, world.multiworld)
    regions = {"Menu": menu}

    for zone in world.allowed_zones:
        region = Region(zone.name, world.player, world.multiworld)
        regions[zone.name] = region
        menu.connect(region, f"Menu to {zone.name}",
                     lambda state, zone_id=zone.ui_map_id: rules.has_zone(state, world, zone_id))

    character = Region(CHARACTER_REGION, world.player, world.multiworld)
    regions[CHARACTER_REGION] = character
    menu.connect(character, f"Menu to {CHARACTER_REGION}")

    for spec in world.location_specs:
        regions[spec.region].locations.append(WoWForeverLocation(world.player, spec.name, spec.address,
                                                                 regions[spec.region]))

    goal = WoWForeverLocation(world.player, GOAL_LOCATION_NAME, None, character)
    goal.place_locked_item(WoWForeverItem(VICTORY_ITEM_NAME, ItemClassification.progression, None, world.player))
    character.locations.append(goal)

    world.multiworld.regions.extend(regions.values())

