from unittest import mock

import worlds.wow_forever as wow_world
from BaseClasses import CollectionState
from Options import OptionError
from test.bases import WorldTestBase
from worlds.wow_forever import ids, locations
from worlds.wow_forever.data_loader import load_game_data, parse_game_data, read_shipped_files

GAME = "World of Warcraft Forever"
ALL_START_ZONE_KEYS = ["elwynn_forest", "dun_morogh", "teldrassil", "durotar", "mulgore", "tirisfal_glades",
                       "zephras_isle"]
ALLIANCE_START = {"elwynn_forest", "dun_morogh", "teldrassil", "zephras_isle"}
HORDE_START = {"durotar", "mulgore", "tirisfal_glades", "zephras_isle"}


class WoWTestBase(WorldTestBase):
    game = GAME
    # Non-empty options switch on the base class' generic tests (fill, reachability, beatability).
    options = {"faction": "alliance"}

    def generate(self, **options) -> None:
        self.options = options
        self.world_setup()

    def location_names(self) -> set[str]:
        return {location.name for location in self.multiworld.get_locations(self.player) if location.address}


class TestDefaultOptions(WoWTestBase):
    def test_default_world_is_beatable_with_all_items(self):
        self.collect(self.multiworld.itempool)
        self.assertBeatable(True)

    def test_default_world_is_not_beatable_without_items(self):
        self.assertBeatable(False)

    def test_start_zone_is_precollected_and_belongs_to_the_faction(self):
        start = self.world.start_zone
        self.assertIn(start.faction, ("alliance", "both"))
        self.assertTrue(start.is_start)
        self.assertEqual(self.count(start.item_name), 1)
        self.assertNotIn(start.item_name, [item.name for item in self.multiworld.itempool])

    def test_pool_size_equals_location_count(self):
        self.assertEqual(len(self.multiworld.itempool), len(self.location_names()))

    def test_every_other_allowed_zone_is_in_the_pool_once(self):
        pool = [item.name for item in self.multiworld.itempool]
        for zone in self.world.allowed_zones:
            expected = 0 if zone.ui_map_id == self.world.start_zone.ui_map_id else 1
            self.assertEqual(pool.count(zone.item_name), expected, zone.name)

    def test_one_progressive_item_per_tier_per_profession(self):
        pool = [item.name for item in self.multiworld.itempool]
        tiers = len(load_game_data().profession_tiers)
        for profession in load_game_data().professions:
            self.assertEqual(pool.count(profession.item_name), tiers, profession.name)

    def test_remaining_slots_are_filler(self):
        filler = [item for item in self.multiworld.itempool if item.name == "Traveler's Tale"]
        self.assertTrue(filler)
        self.assertFalse(any(item.advancement for item in filler))
        self.assertEqual(self.world.get_filler_item_name(), "Traveler's Tale")

    def test_early_item_is_a_non_start_zone_that_covers_level_11(self):
        early = self.multiworld.early_items[self.player]
        self.assertEqual(len(early), 1)
        (name, count), = early.items()
        zone = next(z for z in self.world.allowed_zones if z.item_name == name)
        self.assertEqual(count, 1)
        self.assertNotEqual(zone.ui_map_id, self.world.start_zone.ui_map_id)
        self.assertTrue(zone.min_level <= 11 <= zone.max_level)

    def test_location_and_item_ids_use_the_id_scheme(self):
        by_name = {spec.name: spec for spec in self.world.location_specs}
        for location in self.multiworld.get_locations(self.player):
            if location.address is None:
                continue
            category, native = ids.decode(location.address)
            spec = by_name[location.name]
            self.assertEqual(location.address, spec.address)
            if spec.quest_id:
                self.assertEqual((category, native), (ids.LocCat.QUEST, spec.quest_id))
            elif spec.level:
                self.assertEqual((category, native), (ids.LocCat.LEVEL, spec.level))
            else:
                self.assertEqual((category, native), (ids.LocCat.PROFESSION_SKILL,
                                                      ids.profession_skill_native(spec.skill_line_id, spec.skill)))
        zones = {zone.item_name: zone for zone in load_game_data().zones}
        professions = {p.item_name: p for p in load_game_data().professions}
        for item in self.multiworld.itempool:
            category, native = ids.decode(item.code)
            if item.name in zones:
                self.assertEqual((category, native), (ids.ItemCat.ZONE, zones[item.name].ui_map_id))
            elif item.name in professions:
                expected = (ids.ItemCat.PROFESSION_TIER, professions[item.name].skill_line_id)
                self.assertEqual((category, native), expected)
            else:
                self.assertEqual(category, ids.ItemCat.FILLER)

    def test_static_name_tables_cover_every_seed_item_and_location(self):
        self.assertTrue(set(item.name for item in self.multiworld.itempool) <= set(self.world.item_name_to_id))
        self.assertTrue(self.location_names() <= set(self.world.location_name_to_id))

    def test_goal_location_holds_victory_and_is_not_a_check(self):
        goal = self.multiworld.get_location("Goal", self.player)
        self.assertIsNone(goal.address)
        self.assertEqual(goal.item.name, "Victory")
        self.assertNotIn("Goal", self.location_names())

    def test_level_locations_follow_the_step_and_always_include_the_goal_level(self):
        names = self.location_names()
        self.assertEqual({n for n in names if n.startswith("Reach Level")},
                         {f"Reach Level {level}" for level in range(2, 61)})

    def test_slot_data_describes_the_seed(self):
        data = self.world.fill_slot_data()
        self.assertEqual(data["schema"], 1)
        self.assertEqual(data["faction"], "alliance")
        self.assertEqual(data["start_zone"], self.world.start_zone.ui_map_id)
        self.assertEqual(data["content_release"], 1)
        self.assertEqual(data["goal_level"], 60)
        self.assertEqual(data["level_step"], 1)
        self.assertEqual(data["profession_step"], 25)
        self.assertEqual(sorted(data["professions"]), sorted(p.skill_line_id for p in load_game_data().professions))
        self.assertEqual(data["world_version"], "0.0.0")


class TestFactionsAndStartZones(WoWTestBase):
    def test_every_start_zone_generates_for_its_factions(self):
        for faction, allowed in (("alliance", ALLIANCE_START), ("horde", HORDE_START)):
            for key in ALL_START_ZONE_KEYS:
                if key not in allowed:
                    continue
                with self.subTest(faction=faction, start_zone=key):
                    self.generate(faction=faction, start_zone=key)
                    self.assertTrue(self.multiworld.get_all_state().has("Victory", self.player)
                                    or self.multiworld.can_beat_game(self.multiworld.get_all_state()))

    def test_start_zone_of_the_other_faction_is_an_error(self):
        for faction, key in (("alliance", "durotar"), ("horde", "elwynn_forest")):
            with self.subTest(faction=faction, start_zone=key), self.assertRaises(OptionError):
                self.generate(faction=faction, start_zone=key)

    def test_faction_random_start_zone_stays_in_the_faction(self):
        for seed in range(12):
            for faction in ("alliance", "horde"):
                self.options = {"faction": faction, "start_zone": "faction_random"}
                self.world_setup(seed)
                self.assertIn(self.world.start_zone.faction, (faction, "both"))
                self.assertTrue(self.world.start_zone.is_start)

    def test_horde_seed_has_no_alliance_zones_or_quests(self):
        self.generate(faction="horde", start_zone="durotar")
        names = self.location_names()
        self.assertNotIn("Elwynn Forest: A Threat Within", names)
        self.assertIn("Durotar: Cutting Teeth", names)
        self.assertNotIn("Zone: Westfall", [item.name for item in self.multiworld.itempool])
        self.assertIn("Zone: The Barrens", [item.name for item in self.multiworld.itempool])

    def test_quests_of_a_start_zone_other_than_the_chosen_one_stay_locked_behind_its_item(self):
        self.generate(faction="alliance", start_zone="elwynn_forest")
        state = CollectionState(self.multiworld)
        self.assertTrue(state.can_reach("Elwynn Forest: A Threat Within", "Location", self.player))
        self.assertFalse(state.can_reach("Dun Morogh: Dwarven Outfitters", "Location", self.player))
        state.collect(self.get_item_by_name("Zone: Dun Morogh"))
        self.assertTrue(state.can_reach("Dun Morogh: Dwarven Outfitters", "Location", self.player))


class TestOptions(WoWTestBase):
    def test_empty_profession_set_generates_without_skill_locations(self):
        self.generate(professions=[])
        self.assertFalse(any(name.startswith("Alchemy") for name in self.location_names()))
        self.assertFalse(any(item.name.startswith("Progressive") for item in self.multiworld.itempool))
        self.assertTrue(self.multiworld.can_beat_game(self.multiworld.get_all_state()))

    def test_selected_professions_only(self):
        self.generate(professions=["alchemy"])
        names = self.location_names()
        self.assertIn("Alchemy 300", names)
        self.assertNotIn("Mining 25", names)
        pool = [item.name for item in self.multiworld.itempool]
        self.assertEqual(pool.count("Progressive Alchemy"), 4)
        self.assertEqual(pool.count("Progressive Mining"), 0)

    def test_profession_step_shapes_the_skill_locations(self):
        self.generate(profession_milestone_step=75)
        alchemy = {n for n in self.location_names() if n.startswith("Alchemy")}
        self.assertEqual(alchemy, {"Alchemy 75", "Alchemy 150", "Alchemy 225", "Alchemy 300"})

    def test_level_step_shapes_the_level_locations(self):
        self.generate(level_milestone_step=10)
        levels = {n for n in self.location_names() if n.startswith("Reach Level")}
        self.assertEqual(levels, {f"Reach Level {level}" for level in (11, 21, 31, 41, 51, 60)})

    def test_odd_level_step_still_includes_level_60(self):
        self.generate(level_milestone_step=7)
        self.assertIn("Reach Level 60", self.location_names())
        self.assertIn("Reach Level 8", self.location_names())
        self.assertNotIn("Reach Level 7", self.location_names())

    def test_too_few_locations_is_an_option_error(self):
        with self.assertRaises(OptionError) as error:
            self.generate(professions=[], level_milestone_step=10, start_zone="elwynn_forest")
        self.assertIn("enable more professions or a later content_release", str(error.exception))


def fixture_data_with_a_later_release():
    """Shipped data plus release 2 rows: a zone, a quest in it and a fifth profession tier."""
    files = read_shipped_files()
    files["releases.csv"] += "2,later,Later,2027-01-01\n"
    files["zones.csv"] += "9001,Later Zone,20,30,both,0,2\n"
    files["quests.csv"] += "900001,Later Quest,9001,20,both,2,,,\n"
    files["profession_tiers.csv"] += "5,Master,375,50,2\n"
    files["material_brackets.csv"] += "375,55\n"
    return parse_game_data(files)


class TestContentRelease(WoWTestBase):
    def test_release_2_rows_are_excluded_from_a_launch_seed(self):
        fixture = fixture_data_with_a_later_release()
        with mock.patch.object(wow_world, "load_game_data", return_value=fixture):
            self.generate(faction="alliance", start_zone="elwynn_forest")
        self.assertEqual(self.world.content_release, 1)
        self.assertNotIn("Later Zone", [zone.name for zone in self.world.allowed_zones])
        names = self.location_names()
        self.assertNotIn("Later Zone: Later Quest", names)
        self.assertNotIn("Alchemy 375", names)
        pool = [item.name for item in self.multiworld.itempool]
        self.assertNotIn("Zone: Later Zone", pool)
        self.assertEqual(pool.count("Progressive Alchemy"), 4)  # four launch tiers, not five

    def test_select_locations_filters_by_release_and_faction(self):
        fixture = fixture_data_with_a_later_release()
        zones = frozenset(zone.ui_map_id for zone in fixture.zones)
        professions = frozenset({171})

        def names(release: int, faction: str) -> set[str]:
            specs = locations.select_locations(release, faction, zones, professions, 1, 25, fixture)
            return {spec.name for spec in specs}

        self.assertNotIn("Later Zone: Later Quest", names(1, "alliance"))
        self.assertIn("Later Zone: Later Quest", names(2, "alliance"))
        self.assertIn("Alchemy 375", names(2, "alliance"))
        self.assertNotIn("Alchemy 375", names(1, "alliance"))
        self.assertNotIn("Durotar: Cutting Teeth", names(2, "alliance"))
        self.assertIn("Durotar: Cutting Teeth", names(2, "horde"))

    def test_quests_needing_a_disallowed_zone_are_dropped(self):
        fixture = fixture_data_with_a_later_release()
        zones = frozenset(zone.ui_map_id for zone in fixture.zones) - {1426}
        specs = locations.select_locations(1, "alliance", zones, frozenset(), 1, 25, fixture)
        self.assertNotIn("Dun Morogh: Dwarven Outfitters", {spec.name for spec in specs})
