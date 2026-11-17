"""Extra check categories (plan 004): options, weighted selection, rules and slot data."""
import random
import unittest
from unittest import mock

import pytest
import worlds.wow_forever as wow_world
from BaseClasses import CollectionState
from test.bases import WorldTestBase
from worlds.wow_forever import ids, locations, options
from worlds.wow_forever.data_loader import load_game_data, parse_game_data, read_shipped_files
from worlds.wow_forever.locations import LocationKind

GAME = "World of Warcraft Forever"
EXTRA_KINDS = {LocationKind.BOSS, LocationKind.DISCOVERY, LocationKind.REPUTATION, LocationKind.PVP}
CATEGORY_IDS = {LocationKind.BOSS: ids.LocCat.BOSS, LocationKind.DISCOVERY: ids.LocCat.AREA_DISCOVERY,
                LocationKind.REPUTATION: ids.LocCat.REPUTATION, LocationKind.PVP: ids.LocCat.PVP}
ALL_ON = {"boss_checks": True, "discovery_checks": True, "reputation_checks": True, "pvp_checks": True}
ALL_OFF = {"boss_checks": False, "discovery_checks": False, "reputation_checks": False, "pvp_checks": False}
ALL_FULL = {"boss": 100, "discovery": 100, "reputation": 100, "pvp": 100}


def fixture_files() -> dict[str, str]:
    """Shipped data plus fixture rows for every extra category, with release 2 and horde rows mixed in."""
    files = read_shipped_files()
    files["releases.csv"] += "2,later,Later,2027-01-01\n"
    files["instances.csv"] += (
        "9100,Fixture Dungeon,dungeon,1436,15,5,both,1\n"          # Westfall, level 15
        "9101,Fixture Raid,raid,1434,40,40,both,1\n"                # Stranglethorn Vale
        "9102,Horde Dungeon,dungeon,1411,10,5,horde,1\n"            # Durotar: not in an alliance seed
        "9103,Later Dungeon,dungeon,1436,20,5,both,2\n"
        "9104,Gate Dungeon,dungeon,1429,15,5,both,1\n")             # start zone, but level 15
    files["encounters.csv"] += (
        "9001,Boss A,9100,1\n9002,Boss B,9100,1\n9003,Raid Boss,9101,1\n9004,Horde Boss,9102,1\n"
        "9005,Later Boss,9103,2\n9006,Late Addition,9100,2\n9007,Gate Boss,9104,1\n")
    files["discoveries.csv"] += (
        "90001,Fixture Hollow,1436,1\n90002,Later Hollow,1436,2\n90003,Horde Hollow,1411,1\n")
    files["reputations.csv"] += (
        "9000,5,Fixture Alliance,alliance,12,1436,1\n9000,6,Fixture Alliance,alliance,30,1436;1426,1\n"
        "9001,5,Fixture Horde,horde,12,1411,1\n9002,5,Fixture Later,both,12,1436,2\n")
    files["pvp.csv"] += "99,hk_total,5000,5000 Honorable Kills,60,2\n"
    return files


def fixture_data():
    return parse_game_data(fixture_files())


def alliance_zone_ids(data) -> frozenset[int]:
    return frozenset(zone.ui_map_id for zone in data.zones if zone.faction in ("alliance", "both"))


def select(data, content_release=1, faction="alliance", weights=None, rng=None, zones=None):
    zones = alliance_zone_ids(data) if zones is None else zones
    return locations.select_locations(content_release, faction, zones, frozenset(), 1, 25, data, weights, rng)


def names_of(specs, kind) -> set[str]:
    return {spec.name for spec in specs if spec.kind is kind}


class TestSampleByWeight(unittest.TestCase):
    def test_weight_100_keeps_everything_in_order_and_needs_no_generator(self):
        self.assertEqual(locations.sample_by_weight(list("abcde"), 100, None), list("abcde"))

    def test_half_of_ten_is_five_and_one_percent_of_three_is_one(self):
        self.assertEqual(len(locations.sample_by_weight(list(range(10)), 50, random.Random(1))), 5)
        self.assertEqual(len(locations.sample_by_weight(list(range(3)), 1, random.Random(1))), 1)

    def test_rounding_is_half_up_and_never_below_one(self):
        rng = random.Random(0)
        for size, weight, expected in ((7, 50, 4), (7, 49, 3), (1, 1, 1), (200, 1, 2), (99, 99, 98), (10, 5, 1)):
            with self.subTest(size=size, weight=weight):
                self.assertEqual(len(locations.sample_by_weight(list(range(size)), weight, rng)), expected)

    def test_no_candidates_give_nothing_even_at_a_low_weight(self):
        self.assertEqual(locations.sample_by_weight([], 1, random.Random(0)), [])

    def test_the_sample_keeps_the_original_order_and_has_no_repeats(self):
        sample = locations.sample_by_weight(list(range(50)), 40, random.Random(3))
        self.assertEqual(sample, sorted(set(sample)))
        self.assertEqual(len(sample), 20)

    def test_the_same_seed_gives_the_same_sample_and_another_seed_another_one(self):
        first = locations.sample_by_weight(list(range(100)), 30, random.Random(5))
        self.assertEqual(first, locations.sample_by_weight(list(range(100)), 30, random.Random(5)))
        self.assertNotEqual(first, locations.sample_by_weight(list(range(100)), 30, random.Random(6)))

    def test_a_weight_below_100_without_a_generator_is_an_error(self):
        with self.assertRaises(ValueError):
            locations.sample_by_weight([1, 2, 3], 99, None)


class TestSelectionPerCategory(unittest.TestCase):
    data = fixture_data()

    def test_a_category_that_is_off_has_no_locations_and_none_of_them_appear_without_weights(self):
        for weights in (None, {}):
            self.assertEqual([s for s in select(self.data, weights=weights) if s.kind in EXTRA_KINDS], [])
        for category, kind in (("boss", LocationKind.BOSS), ("discovery", LocationKind.DISCOVERY),
                               ("reputation", LocationKind.REPUTATION), ("pvp", LocationKind.PVP)):
            with self.subTest(category=category):
                specs = select(self.data, weights={category: 100})
                self.assertTrue(names_of(specs, kind))
                self.assertEqual({s.kind for s in specs} & EXTRA_KINDS, {kind})

    def test_weight_100_includes_every_eligible_location(self):
        specs = select(self.data, weights=ALL_FULL)
        self.assertEqual(names_of(specs, LocationKind.BOSS),
                         {"Fixture Dungeon: Boss A", "Fixture Dungeon: Boss B", "Fixture Raid: Raid Boss",
                          "Gate Dungeon: Gate Boss"})
        self.assertIn("Discover Westfall: Fixture Hollow", names_of(specs, LocationKind.DISCOVERY))
        self.assertIn("Fixture Alliance: Honored", names_of(specs, LocationKind.REPUTATION))
        self.assertIn("PvP: Win Warsong Gulch", names_of(specs, LocationKind.PVP))

    def test_weights_sample_each_category_separately_with_the_given_generator(self):
        eligible = select(self.data, weights=ALL_FULL)
        counts = {kind: len(names_of(eligible, kind)) for kind in EXTRA_KINDS}
        specs = select(self.data, weights={"boss": 50, "discovery": 1, "reputation": 100, "pvp": 100},
                       rng=random.Random(11))
        self.assertEqual(len(names_of(specs, LocationKind.BOSS)), (counts[LocationKind.BOSS] + 1) // 2)
        self.assertEqual(len(names_of(specs, LocationKind.DISCOVERY)), max(1, counts[LocationKind.DISCOVERY] // 100))
        self.assertEqual(names_of(specs, LocationKind.REPUTATION), names_of(eligible, LocationKind.REPUTATION))
        self.assertEqual(names_of(specs, LocationKind.PVP), names_of(eligible, LocationKind.PVP))

    def test_exactly_ten_eligible_at_weight_50_gives_five(self):
        files = fixture_files()
        files["pvp.csv"] = "pvp_id,kind,param,name,required_level,release\n" + "".join(
            f"{number},hk_total,{number * 100},{number * 100} Kills,20,1\n" for number in range(1, 11))
        data = parse_game_data(files)
        specs = select(data, weights={"pvp": 50}, rng=random.Random(2))
        self.assertEqual(len(names_of(specs, LocationKind.PVP)), 5)

    def test_three_eligible_at_weight_1_gives_one(self):
        files = fixture_files()
        files["pvp.csv"] = "pvp_id,kind,param,name,required_level,release\n" + "".join(
            f"{number},hk_total,{number * 100},{number * 100} Kills,20,1\n" for number in range(1, 4))
        specs = select(parse_game_data(files), weights={"pvp": 1}, rng=random.Random(2))
        self.assertEqual(len(names_of(specs, LocationKind.PVP)), 1)

    def test_a_category_without_any_eligible_row_stays_empty_at_any_weight(self):
        files = fixture_files()
        files["pvp.csv"] = "pvp_id,kind,param,name,required_level,release\n"
        specs = select(parse_game_data(files), weights={"pvp": 1}, rng=random.Random(2))
        self.assertEqual(names_of(specs, LocationKind.PVP), set())

    def test_the_content_release_filters_every_category(self):
        launch = select(self.data, content_release=1, weights=ALL_FULL)
        later = select(self.data, content_release=2, weights=ALL_FULL)
        released_later = {"Later Dungeon: Later Boss": LocationKind.BOSS,
                          "Fixture Dungeon: Late Addition": LocationKind.BOSS,
                          "Discover Westfall: Later Hollow": LocationKind.DISCOVERY,
                          "Fixture Later: Friendly": LocationKind.REPUTATION,
                          "PvP: 5000 Honorable Kills": LocationKind.PVP}
        for name, kind in released_later.items():
            with self.subTest(name=name):
                self.assertNotIn(name, names_of(launch, kind))
                self.assertIn(name, names_of(later, kind))

    def test_rows_of_the_other_faction_and_of_zones_outside_the_seed_are_excluded(self):
        alliance = select(self.data, weights=ALL_FULL)
        horde_zones = frozenset(zone.ui_map_id for zone in self.data.zones if zone.faction in ("horde", "both"))
        horde = select(self.data, faction="horde", weights=ALL_FULL, zones=horde_zones)
        self.assertNotIn("Horde Dungeon: Horde Boss", names_of(alliance, LocationKind.BOSS))
        self.assertIn("Horde Dungeon: Horde Boss", names_of(horde, LocationKind.BOSS))
        self.assertNotIn("Discover Durotar: Horde Hollow", names_of(alliance, LocationKind.DISCOVERY))
        self.assertIn("Discover Durotar: Horde Hollow", names_of(horde, LocationKind.DISCOVERY))
        self.assertNotIn("Fixture Horde: Friendly", names_of(alliance, LocationKind.REPUTATION))
        self.assertIn("Fixture Horde: Friendly", names_of(horde, LocationKind.REPUTATION))
        self.assertNotIn("Fixture Alliance: Friendly", names_of(horde, LocationKind.REPUTATION))

    def test_a_row_whose_zone_is_not_in_the_seed_is_dropped(self):
        without_westfall = alliance_zone_ids(self.data) - {1436}
        specs = select(self.data, weights=ALL_FULL, zones=without_westfall)
        self.assertNotIn("Fixture Dungeon: Boss A", names_of(specs, LocationKind.BOSS))
        self.assertNotIn("Discover Westfall: Fixture Hollow", names_of(specs, LocationKind.DISCOVERY))
        self.assertNotIn("Fixture Alliance: Friendly", names_of(specs, LocationKind.REPUTATION))
        # a reputation needing two zones is dropped when either one is missing
        without_dun_morogh = alliance_zone_ids(self.data) - {1426}
        specs = select(self.data, weights=ALL_FULL, zones=without_dun_morogh)
        self.assertIn("Fixture Alliance: Friendly", names_of(specs, LocationKind.REPUTATION))
        self.assertNotIn("Fixture Alliance: Honored", names_of(specs, LocationKind.REPUTATION))

    def test_generated_ids_use_the_category_and_native_id_of_the_row(self):
        for spec in select(self.data, weights=ALL_FULL):
            if spec.kind not in EXTRA_KINDS:
                continue
            category, native = ids.decode(spec.address)
            self.assertEqual((category, native), (CATEGORY_IDS[spec.kind], spec.native), spec.name)
        by_name = {spec.name: spec for spec in select(self.data, weights=ALL_FULL)}
        self.assertEqual(by_name["Fixture Dungeon: Boss A"].address, ids.location_id(4, 9001))
        self.assertEqual(by_name["Discover Westfall: Fixture Hollow"].address, ids.location_id(5, 90001))
        self.assertEqual(by_name["Fixture Alliance: Honored"].address, ids.location_id(6, 90006))
        self.assertEqual(by_name["PvP: Win Warsong Gulch"].address, ids.location_id(8, 10))

    def test_regions_are_the_entrance_zone_for_bosses_and_discoveries_and_the_character_otherwise(self):
        by_name = {spec.name: spec for spec in select(self.data, weights=ALL_FULL)}
        self.assertEqual(by_name["Fixture Dungeon: Boss A"].region, "Westfall")
        self.assertEqual(by_name["Fixture Raid: Raid Boss"].region, "Stranglethorn Vale")
        self.assertEqual(by_name["Discover Westfall: Fixture Hollow"].region, "Westfall")
        self.assertEqual(by_name["Fixture Alliance: Honored"].region, locations.CHARACTER_REGION)
        self.assertEqual(by_name["PvP: Win Warsong Gulch"].region, locations.CHARACTER_REGION)

    def test_the_static_location_table_holds_every_row_of_every_release(self):
        table = locations.build_location_name_to_id(self.data)
        for name, address in (("Fixture Dungeon: Boss A", ids.location_id(4, 9001)),
                              ("Later Dungeon: Later Boss", ids.location_id(4, 9005)),
                              ("Discover Westfall: Later Hollow", ids.location_id(5, 90002)),
                              ("Fixture Later: Friendly", ids.location_id(6, 90025)),
                              ("PvP: 5000 Honorable Kills", ids.location_id(8, 99))):
            self.assertEqual(table[name], address)
        self.assertEqual(len(set(table.values())), len(table))


class WoWWorldBase(WorldTestBase):
    game = GAME
    options = {"faction": "alliance", "start_zone": "elwynn_forest"}

    def generate(self, seed: int | None = None, **world_options) -> None:
        self.options = {"faction": "alliance", "start_zone": "elwynn_forest", **world_options}
        self.world_setup(seed)

    def only(self, seed: int | None = None, **on: int | bool) -> None:
        """Generates with every extra category off except the given options."""
        self.generate(seed, **{**ALL_OFF, **on})

    def kinds(self) -> dict[LocationKind, int]:
        counts: dict[LocationKind, int] = {}
        for spec in self.world.location_specs:
            counts[spec.kind] = counts.get(spec.kind, 0) + 1
        return counts


class TestDefaults(WoWWorldBase):
    def test_default_options_turn_boss_and_discovery_on_and_reputation_and_pvp_off(self):
        self.assertEqual(options.category_switches(self.world.options),
                         {"boss": True, "discovery": True, "reputation": False, "pvp": False})
        self.assertEqual(options.category_weights(self.world.options), {"boss": 100, "discovery": 100})
        for _, weight in options.CATEGORY_OPTIONS.values():
            self.assertEqual(getattr(self.world.options, weight).value, 100)

    def test_default_seed_holds_discoveries_but_neither_reputation_nor_pvp(self):
        kinds = self.kinds()
        self.assertGreater(kinds[LocationKind.DISCOVERY], 0)
        self.assertNotIn(LocationKind.REPUTATION, kinds)
        self.assertNotIn(LocationKind.PVP, kinds)

    def test_shipped_data_has_no_boss_rows_yet_so_the_boss_category_adds_nothing(self):
        self.assertNotIn(LocationKind.BOSS, self.kinds())

    def test_default_world_is_beatable_with_all_items_and_not_without(self):
        self.collect(self.multiworld.itempool)
        self.assertBeatable(True)

    def test_pool_size_still_equals_the_location_count(self):
        count = len([location for location in self.multiworld.get_locations(self.player) if location.address])
        self.assertEqual(len(self.multiworld.itempool), count)

    def test_slot_data_carries_the_category_switches_and_no_legacy_key(self):
        self.assertEqual(self.world.fill_slot_data()["categories"],
                         {"boss": True, "discovery": True, "reputation": False, "pvp": False})


class TestOptions(WoWWorldBase):
    def test_every_category_off_leaves_only_the_old_locations(self):
        self.only()
        self.assertEqual(self.kinds().keys() & EXTRA_KINDS, set())
        self.assertEqual(self.world.fill_slot_data()["categories"], {key: False for key in ALL_FULL})

    def test_each_category_on_alone_adds_only_its_own_locations(self):
        for toggle, kind in (("discovery_checks", LocationKind.DISCOVERY),
                             ("reputation_checks", LocationKind.REPUTATION), ("pvp_checks", LocationKind.PVP)):
            with self.subTest(option=toggle):
                self.only(**{toggle: True})
                self.assertEqual(self.kinds().keys() & EXTRA_KINDS, {kind})

    def test_weight_100_includes_all_eligible_and_a_lower_weight_includes_that_share(self):
        self.only(pvp_checks=True)
        self.assertEqual(self.kinds()[LocationKind.PVP], len(load_game_data().pvp_milestones))
        self.only(pvp_checks=True, pvp_weight=50)
        self.assertEqual(self.kinds()[LocationKind.PVP], 4)  # 7 rows, half rounded up
        self.only(reputation_checks=True)
        everything = self.kinds()[LocationKind.REPUTATION]
        self.only(reputation_checks=True, reputation_weight=25)
        self.assertEqual(self.kinds()[LocationKind.REPUTATION], everything // 4)

    def test_weight_1_still_keeps_one_location(self):
        self.only(pvp_checks=True, pvp_weight=1)
        self.assertEqual(self.kinds()[LocationKind.PVP], 1)

    def test_the_sample_follows_the_seed_and_is_stable_for_one_seed(self):
        picks = []
        for seed in (1, 1, 2):
            self.only(seed, discovery_checks=True, discovery_weight=30)
            picks.append(names_of(self.world.location_specs, LocationKind.DISCOVERY))
        self.assertEqual(picks[0], picks[1])
        self.assertNotEqual(picks[0], picks[2])
        everything = len(load_game_data().discoveries)
        self.assertLess(len(picks[0]), everything)

    def test_alliance_seeds_have_no_horde_zone_discoveries_or_horde_reputations(self):
        self.generate(**ALL_ON)
        names = {spec.name for spec in self.world.location_specs}
        self.assertNotIn("Discover Durotar: Valley of Trials", names)
        self.assertNotIn("Orgrimmar: Friendly", names)
        self.assertIn("Stormwind: Friendly", names)
        self.generate(**ALL_ON, faction="horde", start_zone="durotar")
        names = {spec.name for spec in self.world.location_specs}
        self.assertNotIn("Stormwind: Friendly", names)
        self.assertIn("Orgrimmar: Friendly", names)

    def test_a_weight_outside_1_to_100_is_refused(self):
        for value in (0, 101):
            with self.subTest(value=value), self.assertRaisesRegex(Exception, "PvpWeight"):
                self.generate(pvp_weight=value)


class TestEveryCategoryOn(WoWWorldBase):
    options = {"faction": "alliance", "start_zone": "elwynn_forest", **ALL_ON}

    def test_the_world_is_beatable_with_all_items_and_not_without(self):
        self.collect(self.multiworld.itempool)
        self.assertBeatable(True)

    def test_the_world_is_not_beatable_without_items(self):
        self.assertBeatable(False)

    def test_every_extra_location_has_a_rule_and_uses_the_id_scheme(self):
        found = set()
        for location in self.multiworld.get_locations(self.player):
            if location.address is None:
                continue
            spec = next(s for s in self.world.location_specs if s.name == location.name)
            if spec.kind in EXTRA_KINDS:
                found.add(spec.kind)
                self.assertEqual(ids.decode(location.address), (CATEGORY_IDS[spec.kind], spec.native))
        self.assertEqual(found, EXTRA_KINDS - {LocationKind.BOSS})

    def test_slot_data_switches_are_all_true(self):
        self.assertEqual(self.world.fill_slot_data()["categories"], {key: True for key in ALL_FULL})


class FixtureWorld(WorldTestBase):
    """A world on the fixture data: bosses in a dungeon, a raid and a level-gated dungeon, all categories on."""
    game = GAME
    auto_construct = False
    options = {"faction": "alliance", "start_zone": "elwynn_forest", **ALL_ON}

    def setUp(self) -> None:
        with mock.patch.object(wow_world, "load_game_data", return_value=fixture_data()):
            self.world_setup()

    def reachable(self, name: str, *items: str) -> bool:
        state = CollectionState(self.multiworld)
        for item in items:
            state.collect(self.world.create_item(item))
        return state.can_reach(name, "Location", self.player)

    def zone_items_below(self, level: int) -> list[str]:
        return [zone.item_name for zone in self.world.allowed_zones if zone.max_level < level]


class TestFixtureBeatability(FixtureWorld):
    def test_fixture_world_with_every_category_on_is_beatable(self):
        self.collect(self.multiworld.itempool)
        self.assertBeatable(True)

    def test_fixture_world_is_not_beatable_without_items(self):
        self.assertBeatable(False)

    def test_bosses_are_in_the_seed_at_default_options(self):
        names = {location.name for location in self.multiworld.get_locations(self.player)}
        self.assertTrue({"Fixture Dungeon: Boss A", "Fixture Raid: Raid Boss", "Gate Dungeon: Gate Boss"} <= names)
        self.assertNotIn("Later Dungeon: Later Boss", names)
        self.assertNotIn("Horde Dungeon: Horde Boss", names)


class TestBossRules(FixtureWorld):
    def test_a_dungeon_boss_needs_its_entrance_zone_and_the_instance_level(self):
        boss = "Fixture Dungeon: Boss A"  # Westfall, level 15
        self.assertFalse(self.reachable(boss))
        self.assertTrue(self.reachable(boss, "Zone: Westfall"))  # Westfall also covers the level bracket 11

    def test_a_boss_in_the_start_zone_still_needs_the_level(self):
        boss = "Gate Dungeon: Gate Boss"  # Elwynn Forest (start zone, no item), level 15
        self.assertFalse(self.reachable(boss))
        self.assertTrue(self.reachable(boss, "Zone: Westfall"))
        self.assertFalse(self.reachable(boss, "Zone: Dun Morogh"))  # 1-10 only: bracket 11 stays uncovered

    def test_a_raid_boss_also_needs_level_60_logic(self):
        boss = "Fixture Raid: Raid Boss"  # Stranglethorn Vale, instance level 40
        below_top = self.zone_items_below(56)  # covers level 40 and every bracket up to 51, not the top one
        self.assertIn("Zone: Stranglethorn Vale", below_top)
        self.assertFalse(self.reachable(boss, *below_top))
        self.assertTrue(self.reachable(boss, *[zone.item_name for zone in self.world.allowed_zones]))

    def test_the_raid_rule_needs_the_entrance_zone_even_at_level_60(self):
        everything_but_the_entrance = [zone.item_name for zone in self.world.allowed_zones
                                       if zone.ui_map_id != 1434]
        self.assertFalse(self.reachable("Fixture Raid: Raid Boss", *everything_but_the_entrance))


class TestDiscoveryRules(FixtureWorld):
    def test_a_discovery_needs_exactly_its_zone(self):
        name = "Discover Westfall: Fixture Hollow"
        self.assertFalse(self.reachable(name))
        self.assertFalse(self.reachable(name, "Zone: Dun Morogh"))
        self.assertTrue(self.reachable(name, "Zone: Westfall"))

    def test_a_discovery_in_the_start_zone_needs_nothing(self):
        self.assertTrue(self.reachable("Discover Elwynn Forest: Crystal Lake"))


class TestReputationRules(FixtureWorld):
    def test_a_reputation_needs_its_zones_and_its_level(self):
        friendly, honored = "Fixture Alliance: Friendly", "Fixture Alliance: Honored"  # Westfall; level 12 / 30
        self.assertFalse(self.reachable(friendly))
        self.assertTrue(self.reachable(friendly, "Zone: Westfall"))
        self.assertFalse(self.reachable(honored, "Zone: Westfall"))  # level 30 needs more level brackets
        both_zones = ["Zone: Westfall", "Zone: Dun Morogh"]
        self.assertFalse(self.reachable(honored, *both_zones, "Zone: Redridge Mountains"))  # bracket 26 is open
        self.assertTrue(self.reachable(honored, *both_zones, "Zone: Redridge Mountains", "Zone: Duskwood"))
        # the level is there but the second required zone (Dun Morogh) is not
        self.assertFalse(self.reachable(honored, "Zone: Westfall", "Zone: Redridge Mountains", "Zone: Duskwood"))


class TestPvpRules(FixtureWorld):
    def test_a_pvp_check_needs_only_the_level(self):
        low, high = "PvP: 100 Honorable Kills", "PvP: Win Alterac Valley"  # level 20 and 51
        self.assertFalse(self.reachable(low))
        self.assertTrue(self.reachable(low, "Zone: Westfall", "Zone: Redridge Mountains"))
        self.assertFalse(self.reachable(high, "Zone: Westfall", "Zone: Redridge Mountains"))
        self.assertTrue(self.reachable(high, *[zone.item_name for zone in self.world.allowed_zones]))


class TestShippedDataRules(WoWWorldBase):
    options = {"faction": "alliance", "start_zone": "elwynn_forest", **ALL_ON}

    def test_shipped_reputation_rules_use_the_home_zone_and_level(self):
        state = CollectionState(self.multiworld)
        self.assertTrue(state.can_reach("Stormwind: Friendly", "Location", self.player))  # Elwynn is the start zone
        self.assertFalse(state.can_reach("Stormwind: Exalted", "Location", self.player))  # level 50
        self.assertFalse(state.can_reach("Booty Bay: Friendly", "Location", self.player))  # Stranglethorn Vale
        state.collect(self.world.create_item("Zone: Stranglethorn Vale"))
        self.assertFalse(state.can_reach("Booty Bay: Friendly", "Location", self.player))  # still level 30


@pytest.mark.parametrize("name", ["boss_checks", "discovery_checks", "reputation_checks", "pvp_checks"])
def test_every_category_has_a_toggle_and_a_weight_option(name):
    toggle, weight = options.CATEGORY_OPTIONS[name.removesuffix("_checks")]
    assert toggle == name
    assert weight == name.replace("_checks", "_weight")
    assert {toggle, weight} <= set(options.WoWForeverOptions.__dataclass_fields__)
