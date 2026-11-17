from unittest import mock

import worlds.wow_forever as wow_world
from BaseClasses import CollectionState
from Options import OptionError
from test.bases import WorldTestBase
from worlds.wow_forever import rules
from worlds.wow_forever.data_loader import parse_game_data, read_shipped_files

GAME = "World of Warcraft Forever"
BLACKSMITHING, TAILORING, MINING, ALCHEMY = 164, 197, 186, 171
SELF_FOUND = {"allow_auction_house": 0, "allow_trading": 0, "allow_mail": 0, "allow_shared_banks": 0}
MARKET_OPTIONS = ("allow_auction_house", "allow_trading", "allow_mail", "allow_shared_banks")


class EconomyTestBase(WorldTestBase):
    """Elwynn start (levels 1-10); helpers to own every zone, so only the material rule is in the way."""
    game = GAME
    options = {"faction": "alliance", "start_zone": "elwynn_forest"}

    def fresh_state(self) -> CollectionState:
        return CollectionState(self.multiworld)

    def with_items(self, *names: str) -> CollectionState:
        state = self.fresh_state()
        for name in names:
            state.collect(self.world.create_item(name))
        return state

    def all_zones(self) -> list[str]:
        return [zone.item_name for zone in self.world.allowed_zones]


class TestWithMarketAccess(EconomyTestBase):
    def test_default_options_have_market_access(self):
        self.assertTrue(rules.has_market_access(self.world))

    def test_blacksmithing_200_needs_only_the_bracket_level(self):
        state = self.with_items(*self.all_zones())  # no Mining at all
        self.assertTrue(rules.has_material_access(state, self.world, BLACKSMITHING, 200))
        self.assertFalse(rules.has_material_access(self.fresh_state(), self.world, BLACKSMITHING, 200))  # level 30

    def test_every_single_market_option_alone_is_market_access(self):
        for option in MARKET_OPTIONS:
            with self.subTest(option=option):
                self.options = {"faction": "alliance", "start_zone": "elwynn_forest", **SELF_FOUND, option: 1}
                self.world_setup()
                self.assertTrue(rules.has_market_access(self.world))
                self.assertFalse(rules.unreachable_material_sources(self.world))


class TestSelfFoundMaterials(EconomyTestBase):
    options = {"faction": "alliance", "start_zone": "elwynn_forest", **SELF_FOUND}

    def test_no_market_access(self):
        self.assertFalse(rules.has_market_access(self.world))

    def test_blacksmithing_200_needs_mining_at_tier_3_and_the_level(self):
        zones = self.all_zones()
        self.assertFalse(rules.has_material_access(self.with_items(*zones), self.world, BLACKSMITHING, 200))
        two = self.with_items(*zones, *["Progressive Mining"] * 2)
        self.assertFalse(rules.has_material_access(two, self.world, BLACKSMITHING, 200))  # needs tier 3 (skill 175)
        three = self.with_items(*zones, *["Progressive Mining"] * 3)
        self.assertTrue(rules.has_material_access(three, self.world, BLACKSMITHING, 200))
        no_level = self.with_items(*["Progressive Mining"] * 3)
        self.assertFalse(rules.has_material_access(no_level, self.world, BLACKSMITHING, 200))

    def test_bracket_boundaries_use_the_gather_skill_of_their_own_bracket(self):
        zones = self.all_zones()
        one_mining = self.with_items(*zones, "Progressive Mining")
        self.assertTrue(rules.has_material_access(one_mining, self.world, BLACKSMITHING, 75))  # copper: skill 1
        self.assertFalse(rules.has_material_access(one_mining, self.world, BLACKSMITHING, 76))  # iron: skill 125
        self.assertTrue(rules.has_material_access(self.with_items(*zones, *["Progressive Mining"] * 2),
                                                  self.world, BLACKSMITHING, 150))

    def test_alchemy_needs_herbalism_not_mining(self):
        zones = self.all_zones()
        self.assertFalse(rules.has_material_access(self.with_items(*zones, *["Progressive Mining"] * 4),
                                                   self.world, ALCHEMY, 76))
        self.assertTrue(rules.has_material_access(self.with_items(*zones, *["Progressive Herbalism"] * 2),
                                                  self.world, ALCHEMY, 76))

    def test_tailoring_drops_need_only_the_level(self):
        self.assertTrue(rules.has_material_access(self.fresh_state(), self.world, TAILORING, 75))
        self.assertFalse(rules.has_material_access(self.fresh_state(), self.world, TAILORING, 200))
        self.assertTrue(rules.has_material_access(self.with_items(*self.all_zones()), self.world, TAILORING, 200))

    def test_a_gathering_profession_itself_keeps_the_level_only_rule(self):
        self.assertFalse(rules.has_material_access(self.fresh_state(), self.world, MINING, 200))
        self.assertTrue(rules.has_material_access(self.with_items(*self.all_zones()), self.world, MINING, 200))

    def test_profession_locations_follow_the_material_rule(self):
        items = [*self.all_zones(), *["Progressive Blacksmithing"] * 3]
        self.assertFalse(self.with_items(*items).can_reach("Blacksmithing 200", "Location", self.player))
        state = self.with_items(*items, *["Progressive Mining"] * 3)
        self.assertTrue(state.can_reach("Blacksmithing 200", "Location", self.player))

    def test_world_is_beatable_and_every_location_reachable_with_all_items(self):
        self.assertBeatable(False)
        state = self.multiworld.get_all_state(False)
        self.assertTrue(self.multiworld.can_beat_game(state))
        for location in self.multiworld.get_locations(self.player):
            self.assertTrue(location.can_reach(state), location.name)


class TestSelfFoundValidation(WorldTestBase):
    game = GAME
    options = {"faction": "alliance"}

    def generate(self, **options) -> None:
        self.options = {"faction": "alliance", "start_zone": "elwynn_forest", **options}
        self.world_setup()

    def test_blacksmithing_without_mining_is_an_option_error_naming_both(self):
        with self.assertRaises(OptionError) as error:
            self.generate(**SELF_FOUND, professions=["blacksmithing"])
        self.assertIn("Blacksmithing needs Mining", str(error.exception))
        self.assertNotIn("Herbalism", str(error.exception))

    def test_every_missing_gathering_profession_is_named(self):
        with self.assertRaises(OptionError) as error:
            self.generate(**SELF_FOUND, professions=["blacksmithing", "alchemy"])
        message = str(error.exception)
        self.assertIn("Blacksmithing needs Mining", message)
        self.assertIn("Alchemy needs Herbalism", message)

    def test_alchemy_without_herbalism_is_an_option_error(self):
        with self.assertRaises(OptionError) as error:
            self.generate(**SELF_FOUND, professions=["alchemy", "mining"])
        self.assertIn("Alchemy needs Herbalism", str(error.exception))

    def test_the_gathering_profession_selected_generates(self):
        self.generate(**SELF_FOUND, professions=["blacksmithing", "mining"])
        self.assertTrue(self.multiworld.can_beat_game(self.multiworld.get_all_state()))

    def test_professions_without_gathering_need_generate_fine_in_self_found(self):
        self.generate(**SELF_FOUND, professions=["tailoring", "cooking", "first_aid", "enchanting"])
        self.assertTrue(self.multiworld.can_beat_game(self.multiworld.get_all_state()))

    def test_market_access_makes_the_missing_gatherer_fine(self):
        for option in MARKET_OPTIONS:
            with self.subTest(option=option):
                self.generate(**{**SELF_FOUND, option: 1}, professions=["blacksmithing"])

    def test_a_drops_alternative_in_the_same_bracket_removes_the_error(self):
        files = read_shipped_files()
        brackets = ((75, 1), (150, 15), (225, 30), (300, 45))
        files["profession_materials.csv"] += "".join(
            f"{BLACKSMITHING},{limit},drops,,0,{level},1\n" for limit, level in brackets)
        with mock.patch.object(wow_world, "load_game_data", return_value=parse_game_data(files)):
            self.generate(**SELF_FOUND, professions=["blacksmithing"])
            state = self.multiworld.get_all_state()
            self.assertTrue(rules.has_material_access(self.multiworld.state, self.world, BLACKSMITHING, 75))
            self.assertTrue(rules.has_material_access(state, self.world, BLACKSMITHING, 300))

    def test_rows_of_a_later_release_are_ignored_for_a_launch_seed(self):
        files = read_shipped_files()
        files["releases.csv"] += "2,later,Later,2027-01-01\n"
        files["profession_materials.csv"] += f"{BLACKSMITHING},300,drops,,0,45,2\n"
        data = parse_game_data(files)
        self.assertEqual(len(rules.compute_material_sources(data, 1)[(BLACKSMITHING, 300)]), 1)
        self.assertEqual(len(rules.compute_material_sources(data, 2)[(BLACKSMITHING, 300)]), 2)
