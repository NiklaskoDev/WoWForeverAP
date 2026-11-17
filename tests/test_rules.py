from unittest import mock

import worlds.wow_forever as wow_world
from BaseClasses import CollectionState
from test.bases import WorldTestBase
from worlds.wow_forever import rules
from worlds.wow_forever.data_loader import parse_game_data, read_shipped_files

GAME = "World of Warcraft Forever"
ALCHEMY = 171


class RulesTestBase(WorldTestBase):
    game = GAME
    options = {"faction": "alliance", "start_zone": "elwynn_forest"}  # Elwynn Forest covers levels 1-10

    def fresh_state(self) -> CollectionState:
        return CollectionState(self.multiworld)

    def with_items(self, *names: str) -> CollectionState:
        state = self.fresh_state()
        for name in names:
            state.collect(self.world.create_item(name))
        return state


class TestLevelRule(RulesTestBase):
    def test_level_one_needs_nothing(self):
        self.assertTrue(rules.can_reach_level(self.fresh_state(), self.world, 1))

    def test_start_zone_alone_reaches_level_11_but_not_12(self):
        state = self.fresh_state()
        self.assertTrue(rules.can_reach_level(state, self.world, 11))
        self.assertFalse(rules.can_reach_level(state, self.world, 12))

    def test_adding_a_10_to_20_zone_reaches_21_but_not_22(self):
        state = self.with_items("Zone: Westfall")
        self.assertTrue(rules.can_reach_level(state, self.world, 21))
        self.assertFalse(rules.can_reach_level(state, self.world, 22))

    def test_a_gap_in_the_level_brackets_blocks_everything_above_it(self):
        state = self.with_items("Zone: Ashenvale")  # 18-30 does not cover bracket 11 or 16
        self.assertFalse(rules.can_reach_level(state, self.world, 17))
        self.assertFalse(rules.can_reach_level(state, self.world, 31))

    def test_goal_level_needs_a_zone_for_every_bracket(self):
        zone_items = [zone.item_name for zone in self.world.allowed_zones]
        self.assertTrue(rules.can_reach_level(self.with_items(*zone_items), self.world, 60))
        without_top = [zone.item_name for zone in self.world.allowed_zones if zone.max_level < 56]  # bracket 56
        self.assertFalse(rules.can_reach_level(self.with_items(*without_top), self.world, 60))

    def test_has_zone_accepts_start_zone_without_item_and_others_only_with_it(self):
        state = self.fresh_state()
        self.assertTrue(rules.has_zone(state, self.world, 1429))
        self.assertFalse(rules.has_zone(state, self.world, 1436))
        state.collect(self.world.create_item("Zone: Westfall"))
        self.assertTrue(rules.has_zone(state, self.world, 1436))


class TestProfessionRules(RulesTestBase):
    def test_tier_and_bracket_boundaries(self):
        self.assertEqual(rules.tier_for(self.world, 75).tier, 1)
        self.assertEqual(rules.tier_for(self.world, 76).tier, 2)
        self.assertEqual(rules.tier_for(self.world, 300).tier, 4)
        self.assertEqual(rules.bracket_for(self.world, 75).required_level, 1)
        self.assertEqual(rules.bracket_for(self.world, 76).required_level, 15)
        with self.assertRaises(ValueError):
            rules.tier_for(self.world, 301)
        with self.assertRaises(ValueError):
            rules.bracket_for(self.world, 301)

    def test_skill_76_needs_two_tiers(self):
        one = self.with_items("Progressive Alchemy")
        two = self.with_items("Progressive Alchemy", "Progressive Alchemy")
        self.assertFalse(rules.has_profession_tier(one, self.world, ALCHEMY, 76))
        self.assertTrue(rules.has_profession_tier(two, self.world, ALCHEMY, 76))

    def test_skill_75_needs_one_tier(self):
        self.assertFalse(rules.has_profession_tier(self.fresh_state(), self.world, ALCHEMY, 75))
        self.assertTrue(rules.has_profession_tier(self.with_items("Progressive Alchemy"), self.world, ALCHEMY, 75))

    def test_top_tier_also_needs_the_tier_required_level(self):
        four = ["Progressive Alchemy"] * 4
        self.assertFalse(rules.has_profession_tier(self.with_items(*four), self.world, ALCHEMY, 300))
        # tier 4 needs level 35: brackets 11, 16, 21, 26, 31 must be covered
        zones = ["Zone: Westfall", "Zone: Redridge Mountains", "Zone: Duskwood", "Zone: Hillsbrad Foothills",
                 "Zone: Thousand Needles", "Zone: Arathi Highlands"]
        self.assertTrue(rules.has_profession_tier(self.with_items(*four, *zones), self.world, ALCHEMY, 300))

    def test_material_access_needs_the_bracket_level_and_is_independent_of_tier_items(self):
        self.assertTrue(rules.has_material_access(self.fresh_state(), self.world, ALCHEMY, 75))
        self.assertFalse(rules.has_material_access(self.fresh_state(), self.world, ALCHEMY, 76))  # level 15
        self.assertTrue(rules.has_material_access(self.with_items("Zone: Westfall"), self.world, ALCHEMY, 76))

    def test_profession_location_needs_tier_item_and_material_level(self):
        self.assertFalse(self.can_reach_location("Alchemy 25"))
        state = self.with_items("Progressive Alchemy")
        self.assertTrue(state.can_reach("Alchemy 25", "Location", self.player))
        self.assertFalse(state.can_reach("Alchemy 100", "Location", self.player))  # tier 2, bracket level 15
        state = self.with_items("Progressive Alchemy", "Progressive Alchemy", "Zone: Westfall")
        self.assertTrue(state.can_reach("Alchemy 100", "Location", self.player))


class TestQuestAndGoalRules(RulesTestBase):
    def test_start_zone_quest_needs_nothing(self):
        self.assertTrue(self.can_reach_location("Elwynn Forest: A Threat Within"))

    def test_other_zone_quest_needs_its_zone_item(self):
        self.assertFalse(self.can_reach_location("Dun Morogh: Dwarven Outfitters"))

    def test_goal_needs_level_60_logic(self):
        self.assertFalse(self.can_reach_location("Goal"))
        zone_items = [zone.item_name for zone in self.world.allowed_zones]
        self.assertTrue(self.with_items(*zone_items).can_reach("Goal", "Location", self.player))

    def test_reach_level_locations_follow_can_reach_level(self):
        self.assertTrue(self.can_reach_location("Reach Level 11"))  # brackets 1 and 6: the start zone covers both
        self.assertFalse(self.can_reach_location("Reach Level 12"))  # bracket 11 needs a 10+ zone
        self.assertTrue(self.with_items("Zone: Westfall").can_reach("Reach Level 12", "Location", self.player))


class TestQuestWithPrerequisiteInAnotherZone(WorldTestBase):
    game = GAME
    auto_construct = False
    options = {"faction": "alliance", "start_zone": "elwynn_forest"}

    def setUp(self) -> None:
        files = read_shipped_files()
        files["quests.csv"] += (
            "900000,Fixture Opener,1426,1,alliance,1,,,\n"
            "900001,Fixture Follow-up,1436,12,alliance,1,900000,,\n"
        )
        with mock.patch.object(wow_world, "load_game_data", return_value=parse_game_data(files)):
            self.world_setup()

    def collect_zones(self, *names: str) -> CollectionState:
        state = CollectionState(self.multiworld)
        for name in names:
            state.collect(self.world.create_item(name))
        return state

    def test_quest_needs_its_own_zone_and_the_prerequisites_zone(self):
        name = "Westfall: Fixture Follow-up"
        for zones, expected in (((), False), (("Zone: Westfall",), False), (("Zone: Dun Morogh",), False),
                                (("Zone: Westfall", "Zone: Dun Morogh"), True)):
            with self.subTest(zones=zones):
                self.assertEqual(self.collect_zones(*zones).can_reach(name, "Location", self.player), expected)

    def test_quest_uses_the_highest_level_along_the_chain(self):
        quest = self.world.data.quests_by_id[900001]
        self.assertEqual(quest.effective_level, 12)
        self.assertEqual(quest.effective_zones, (1426, 1436))
