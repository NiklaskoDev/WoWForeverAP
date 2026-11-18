"""The goal_level option (plan 008): the level cap that wins the game and prunes everything above it."""
import hashlib
import unittest

from BaseClasses import CollectionState
from test.bases import WorldTestBase
from worlds.wow_forever import locations, options
from worlds.wow_forever.data_loader import load_game_data, parse_game_data, read_shipped_files
from worlds.wow_forever.locations import LocationKind

GAME = "World of Warcraft Forever"
ALL_CATEGORIES = {"boss_checks": True, "discovery_checks": True, "reputation_checks": True, "pvp_checks": True}
# Digest of the default alliance seed 20260101, taken with the code before the option existed (v0.1.0).
DEFAULT_SEED = 20260101
DEFAULT_SEED_COUNTS = (591, 591)  # locations, items
DEFAULT_SEED_DIGEST = "834faeaaeddc5695c9733091fc7ed8224fd8804c3f1a886714224b5e59166832"


class GoalWorldBase(WorldTestBase):
    game = GAME
    options = {"faction": "alliance"}  # non-empty switches on the generic fill and beatability tests

    def generate(self, seed: int | None = None, **world_options) -> None:
        self.options = world_options
        self.world_setup(seed)

    def location_names(self) -> set[str]:
        return {location.name for location in self.multiworld.get_locations(self.player) if location.address}

    def pool_names(self) -> list[str]:
        return [item.name for item in self.multiworld.itempool]


def seed_digest(world_test: GoalWorldBase) -> tuple[tuple[int, int], str]:
    names = sorted(world_test.location_names())
    pool = sorted(world_test.pool_names())
    start = world_test.world.start_zone.name
    payload = "\n".join([start, *names, "--", *pool, "--", *sorted(world_test.multiworld.early_items[1])])
    return (len(names), len(pool)), hashlib.sha256(payload.encode()).hexdigest()


class TestDefaultGoalLevel(GoalWorldBase):
    def test_the_option_is_a_slider_from_10_to_60_that_defaults_to_60(self):
        self.assertTrue(issubclass(options.GoalLevel, options.Range))
        self.assertEqual((options.GoalLevel.range_start, options.GoalLevel.range_end, options.GoalLevel.default),
                         (10, 60, 60))
        self.assertEqual(options.GoalLevel.display_name, "Goal Level")

    def test_default_options_keep_the_goal_at_60_and_the_slot_data_says_so(self):
        self.assertEqual(self.world.goal_level, 60)
        self.assertEqual(self.world.fill_slot_data()["goal_level"], 60)
        self.assertEqual(len(self.world.allowed_tiers), 4)

    def test_the_default_seed_is_unchanged_since_v0_1_0(self):
        self.generate(seed=DEFAULT_SEED)
        counts, digest = seed_digest(self)
        self.assertEqual(counts, DEFAULT_SEED_COUNTS)
        self.assertEqual(digest, DEFAULT_SEED_DIGEST)

    def test_an_explicit_60_gives_the_same_seed_as_the_default(self):
        self.generate(seed=DEFAULT_SEED)
        default = seed_digest(self)
        self.generate(seed=DEFAULT_SEED, goal_level=60)
        self.assertEqual(seed_digest(self), default)


class TestCappedSeed(GoalWorldBase):
    def test_nothing_above_the_goal_level_is_in_the_seed(self):
        for faction in ("alliance", "horde"):
            with self.subTest(faction=faction):
                self.generate(faction=faction, goal_level=30, **ALL_CATEGORIES)
                self.assertEqual(self.world.goal_level, 30)
                self.assertEqual(self.world.fill_slot_data()["goal_level"], 30)
                self.assertTrue(all(zone.min_level <= 30 for zone in self.world.allowed_zones))
                zone_items = {zone.item_name for zone in self.world.data.zones if zone.min_level > 30}
                self.assertFalse(zone_items & set(self.pool_names()))
                for spec in self.world.location_specs:
                    if spec.kind is LocationKind.QUEST:
                        self.assertLessEqual(self.world.data.quests_by_id[spec.quest_id].effective_level, 30)
                    if spec.kind is LocationKind.BOSS:
                        instance = self.world.data.instances_by_id[
                            self.world.data.encounters_by_id[spec.native].instance_id]
                        self.assertLessEqual(instance.min_level, 30)
                    if spec.kind is LocationKind.REPUTATION:
                        self.assertLessEqual(self.world.data.reputations_by_native[spec.native].required_level, 30)
                    if spec.kind is LocationKind.PVP:
                        self.assertLessEqual(self.world.data.pvp_by_id[spec.native].required_level, 30)
                self.assertTrue(self.multiworld.can_beat_game(self.multiworld.get_all_state()))

    def test_the_highest_level_check_is_the_goal_level(self):
        self.generate(goal_level=30)
        levels = {int(name.rsplit(" ", 1)[1]) for name in self.location_names() if name.startswith("Reach Level")}
        self.assertEqual(levels, set(range(2, 31)))

    def test_the_goal_level_is_a_check_even_off_the_step(self):
        self.generate(goal_level=25, level_milestone_step=10)
        levels = {int(name.rsplit(" ", 1)[1]) for name in self.location_names() if name.startswith("Reach Level")}
        self.assertEqual(levels, {11, 21, 25})

    def test_the_pool_still_matches_the_locations(self):
        self.generate(goal_level=30)
        self.assertEqual(len(self.pool_names()), len(self.location_names()))

    def test_professions_follow_the_allowed_tiers(self):
        self.generate(goal_level=40, professions=["alchemy", "mining"])
        self.assertEqual([tier.tier for tier in self.world.allowed_tiers], [1, 2, 3])
        pool = self.pool_names()
        self.assertEqual(pool.count("Progressive Alchemy"), 3)
        self.assertEqual(pool.count("Progressive Mining"), 3)
        top_skill = self.world.allowed_tiers[-1].max_skill
        skills = [spec.skill for spec in self.world.location_specs if spec.kind is LocationKind.PROFESSION_SKILL]
        self.assertTrue(skills)
        self.assertEqual(max(skills), top_skill)
        self.assertNotIn("Alchemy 300", self.location_names())

    def test_a_goal_of_10_leaves_one_tier(self):
        self.generate(goal_level=10, professions=["alchemy"])
        self.assertEqual(self.pool_names().count("Progressive Alchemy"), 1)
        alchemy = {n for n in self.location_names() if n.startswith("Alchemy")}
        self.assertEqual(alchemy, {"Alchemy 25", "Alchemy 50", "Alchemy 75"})


class TestLowestGoalLevel(GoalWorldBase):
    def test_goal_level_10_generates_for_both_factions(self):
        for faction in ("alliance", "horde"):
            with self.subTest(faction=faction):
                self.generate(faction=faction, goal_level=options.GoalLevel.range_start)
                self.assertTrue(self.multiworld.can_beat_game(self.multiworld.get_all_state()))
                self.assertEqual(len(self.pool_names()), len(self.location_names()))
                self.assertIn("Reach Level 10", self.location_names())
                self.assertNotIn("Reach Level 11", self.location_names())


class TestGoalRule(GoalWorldBase):
    options = {"faction": "alliance", "start_zone": "elwynn_forest", "goal_level": 30}

    def goal_reachable(self, zone_items: list[str]) -> bool:
        state = CollectionState(self.multiworld)
        for name in zone_items:
            state.collect(self.world.create_item(name))
        return self.multiworld.get_location("Goal", self.player).access_rule(state)

    def test_the_brackets_are_the_ones_below_the_goal(self):
        self.assertEqual(sorted(self.world.bracket_zone_ids), [1, 6, 11, 16, 21, 26])

    def test_the_goal_needs_exactly_the_brackets_below_the_goal_level(self):
        every_zone = [zone.item_name for zone in self.world.allowed_zones]
        self.assertTrue(self.goal_reachable(every_zone))
        without_26 = [zone.item_name for zone in self.world.allowed_zones if zone.max_level < 26]
        self.assertFalse(self.goal_reachable(without_26))
        self.assertFalse(self.goal_reachable([]))


class TestAllowedTiers(unittest.TestCase):
    data = load_game_data()

    def tiers(self, goal_level: int, data=None, release: int = 1) -> list[int]:
        return [tier.tier for tier in locations.allowed_tiers(data or self.data, release, goal_level)]

    def test_the_shipped_tiers_per_goal_level(self):
        # tier needs: trainer level 5/10/20/35, material bracket level 1/15/30/45
        for goal_level, expected in ((60, [1, 2, 3, 4]), (45, [1, 2, 3, 4]), (44, [1, 2, 3]), (40, [1, 2, 3]),
                                     (30, [1, 2, 3]), (29, [1, 2]), (20, [1, 2]), (15, [1, 2]), (14, [1]),
                                     (10, [1]), (5, [1]), (4, [])):
            with self.subTest(goal_level=goal_level):
                self.assertEqual(self.tiers(goal_level), expected)

    def test_a_tier_that_fails_stops_the_prefix_even_when_a_later_one_passes(self):
        files = read_shipped_files()
        old = "2,Journeyman,150,10,1"
        assert old in files["profession_tiers.csv"], "fixture drift"
        files["profession_tiers.csv"] = files["profession_tiers.csv"].replace(old, "2,Journeyman,150,50,1")
        data = parse_game_data(files)
        self.assertEqual(self.tiers(40, data), [1])  # tier 3 alone would pass at 40
        self.assertEqual(self.tiers(60, data), [1, 2, 3, 4])

    def test_the_material_bracket_of_a_tier_can_stop_the_prefix(self):
        files = read_shipped_files()
        old = "225,30"
        assert old in files["material_brackets.csv"], "fixture drift"
        files["material_brackets.csv"] = files["material_brackets.csv"].replace(old, "225,55")
        self.assertEqual(self.tiers(50, parse_game_data(files)), [1, 2])

    def test_tiers_of_a_later_release_are_not_allowed(self):
        files = read_shipped_files()
        files["releases.csv"] += "2,later,Later,2027-01-01\n"
        files["profession_tiers.csv"] += "5,Master,375,50,2\n"
        files["material_brackets.csv"] += "375,55\n"
        data = parse_game_data(files)
        self.assertEqual(self.tiers(60, data, release=1), [1, 2, 3, 4])
        self.assertEqual(self.tiers(60, data, release=2), [1, 2, 3, 4, 5])
        self.assertEqual(self.tiers(54, data, release=2), [1, 2, 3, 4])


class TestMilestoneLevels(unittest.TestCase):
    def test_the_goal_level_is_added_when_it_is_off_the_step(self):
        self.assertEqual(locations.milestone_levels(10, 25), [11, 21, 25])

    def test_step_one_gives_every_level_up_to_the_goal(self):
        self.assertEqual(locations.milestone_levels(1, 10), list(range(2, 11)))

    def test_the_goal_is_not_repeated_when_it_is_on_the_step(self):
        self.assertEqual(locations.milestone_levels(10, 51), [11, 21, 31, 41, 51])
        self.assertEqual(locations.milestone_levels(5, 56)[-2:], [51, 56])


class TestSelectionUnderACap(unittest.TestCase):
    data = load_game_data()
    zones = frozenset(zone.ui_map_id for zone in data.zones)

    def select(self, goal_level: int, **kwargs):
        return locations.select_locations(
            1, "alliance", self.zones, frozenset({171}), 1, 25, self.data,
            {"boss": 100, "discovery": 100, "reputation": 100, "pvp": 100}, None, 100,
            goal_level=goal_level, **kwargs)

    def test_quests_above_the_goal_are_dropped(self):
        specs = self.select(20)
        quests = [spec for spec in specs if spec.kind is LocationKind.QUEST]
        self.assertTrue(quests)
        self.assertTrue(all(self.data.quests_by_id[spec.quest_id].effective_level <= 20 for spec in quests))
        self.assertLess(len(quests), len(self.select(60)))

    def test_the_default_keyword_keeps_everything(self):
        explicit = locations.select_locations(
            1, "alliance", self.zones, frozenset({171}), 1, 25, self.data,
            {"boss": 100, "discovery": 100, "reputation": 100, "pvp": 100}, None, 100)
        self.assertEqual(explicit, self.select(60))

    def test_reputation_and_pvp_above_the_goal_are_dropped(self):
        files = read_shipped_files()
        files["reputations.csv"] += "9000,5,Fixture Late,alliance,40,1429,1\n9001,6,Fixture Early,alliance,12,1429,1\n"
        files["pvp.csv"] += "99,hk_total,5000,5000 Honorable Kills,60,1\n"
        data = parse_game_data(files)

        def names(goal_level: int) -> set[str]:
            specs = locations.select_locations(
                1, "alliance", self.zones, frozenset(), 1, 25, data, {"reputation": 100, "pvp": 100}, None, 100,
                goal_level=goal_level)
            return {spec.name for spec in specs}

        low, high = names(30), names(60)
        self.assertNotIn("Fixture Late: Friendly", low)
        self.assertIn("Fixture Early: Honored", low)
        self.assertIn("Fixture Late: Friendly", high)
        self.assertNotIn("PvP: 5000 Honorable Kills", low)
        self.assertIn("PvP: 5000 Honorable Kills", high)

    def test_bosses_of_an_instance_above_the_goal_are_dropped(self):
        files = read_shipped_files()
        files["instances.csv"] += "9100,Low Dungeon,dungeon,1436,15,5,both,1\n9101,High Raid,raid,1434,40,40,both,1\n"
        files["encounters.csv"] += "9001,Low Boss,9100,1\n9002,High Boss,9101,1\n"
        data = parse_game_data(files)

        def names(goal_level: int) -> set[str]:
            specs = locations.select_locations(
                1, "alliance", self.zones, frozenset(), 1, 25, data, {"boss": 100}, None, 100, goal_level=goal_level)
            return {spec.name for spec in specs if spec.kind is LocationKind.BOSS}

        self.assertEqual(names(30), {"Low Dungeon: Low Boss"})
        self.assertEqual(names(60), {"Low Dungeon: Low Boss", "High Raid: High Boss"})

    def test_profession_skills_stop_at_the_top_allowed_tier(self):
        skills = {spec.skill for spec in self.select(40) if spec.kind is LocationKind.PROFESSION_SKILL}
        self.assertEqual(skills, {25, 50, 75, 100, 125, 150, 175, 200, 225})
        # a goal below every tier's trainer level leaves no skill checks
        self.assertFalse([s for s in self.select(4) if s.kind is LocationKind.PROFESSION_SKILL])
