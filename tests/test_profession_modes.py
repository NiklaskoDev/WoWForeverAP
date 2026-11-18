"""The profession_mode and team_size options (plan 009) and the start info of the apworld."""
import io
import unittest

from Options import OptionError
from test.bases import WorldTestBase
from worlds.wow_forever import options
from worlds.wow_forever.data_loader import load_game_data
from worlds.wow_forever.start_info import start_info_lines

GAME = "World of Warcraft Forever"
SELF_FOUND = {"allow_auction_house": 0, "allow_trading": 0, "allow_mail": 0, "allow_shared_banks": 0}
PRIMARIES = {"alchemy", "blacksmithing", "enchanting", "engineering", "herbalism", "leatherworking", "mining",
             "skinning", "tailoring"}
SECONDARIES = {"cooking", "first_aid", "fishing"}
SEEDS = range(1, 9)


class ModeWorldBase(WorldTestBase):
    game = GAME
    options = {"faction": "alliance"}  # non-empty switches on the generic fill and beatability tests

    def generate(self, seed: int | None = None, **world_options) -> None:
        self.options = {"faction": "alliance", "start_zone": "elwynn_forest", **world_options}
        self.world_setup(seed)

    def chosen(self) -> set[str]:
        return {profession.key for profession in self.world.selected_professions}

    def chosen_primaries(self) -> set[str]:
        return self.chosen() & PRIMARIES


class TestPrimaryLimit(unittest.TestCase):
    @staticmethod
    def limit(**values) -> int | None:
        # primary_limit only reads these two options, so the real option classes stand in for a full dataclass.
        class Stub:
            profession_mode = options.ProfessionMode.from_any(values.get("mode", "all"))
            team_size = options.TeamSize(values.get("size", options.TeamSize.default))

        return options.primary_limit(Stub())

    def test_all_is_unlimited_solo_is_two_and_team_is_two_per_member(self):
        self.assertIsNone(self.limit(mode="all"))
        self.assertEqual(self.limit(mode="solo"), 2)
        self.assertEqual(self.limit(mode="team", size=3), 6)
        self.assertEqual(self.limit(mode="team"), 4)

    def test_team_size_is_ignored_outside_team_mode(self):
        self.assertIsNone(self.limit(mode="all", size=4))
        self.assertEqual(self.limit(mode="solo", size=4), 2)

    def test_defaults_and_ranges(self):
        self.assertEqual(options.ProfessionMode.default, options.ProfessionMode.option_all)
        self.assertEqual((options.TeamSize.range_start, options.TeamSize.range_end, options.TeamSize.default),
                         (2, 4, 2))
        self.assertEqual(options.ProfessionMode.display_name, "Profession Mode")
        self.assertEqual(options.TeamSize.display_name, "Team Size")


class TestDefaultMode(ModeWorldBase):
    def test_default_options_select_every_profession_in_data_order_without_drawing_random_numbers(self):
        self.assertEqual([p.key for p in self.world.selected_professions],
                         [p.key for p in load_game_data().professions])
        state = self.world.random.getstate()
        self.assertEqual(self.world._select_professions(), self.world.selected_professions)
        self.assertEqual(self.world.random.getstate(), state)

    def test_a_limit_the_professions_stay_under_draws_nothing_either(self):
        self.generate(profession_mode="solo", professions=["mining", "tailoring", "cooking"])
        state = self.world.random.getstate()
        self.world._select_professions()
        self.assertEqual(self.world.random.getstate(), state)


class TestSolo(ModeWorldBase):
    def test_all_twelve_professions_give_two_primaries_and_every_secondary(self):
        for seed in SEEDS:
            with self.subTest(seed=seed):
                self.generate(seed, profession_mode="solo")
                self.assertEqual(len(self.chosen_primaries()), 2)
                self.assertEqual(self.chosen() - PRIMARIES, SECONDARIES)

    def test_the_pick_is_deterministic_per_seed_and_differs_between_seeds(self):
        picks = {}
        for seed in (*SEEDS, *SEEDS):
            self.generate(seed, profession_mode="solo")
            self.assertEqual(picks.setdefault(seed, self.chosen_primaries()), self.chosen_primaries())
        self.assertGreater(len(set(map(frozenset, picks.values()))), 1)

    def test_exactly_two_primaries_listed_are_used_as_listed(self):
        self.generate(profession_mode="solo", professions=["tailoring", "enchanting", "fishing"])
        self.assertEqual(self.chosen(), {"tailoring", "enchanting", "fishing"})

    def test_deselected_secondaries_stay_out(self):
        for seed in SEEDS:
            with self.subTest(seed=seed):
                self.generate(seed, profession_mode="solo", professions=sorted(PRIMARIES | {"cooking"}))
                self.assertEqual(self.chosen() - PRIMARIES, {"cooking"})
                self.assertEqual(len(self.chosen_primaries()), 2)

    def test_only_selected_professions_have_progressive_items_and_skill_locations(self):
        self.generate(profession_mode="solo")
        pool = {item.name for item in self.multiworld.itempool}
        for profession in load_game_data().professions:
            with self.subTest(profession=profession.key):
                self.assertEqual(profession.item_name in pool, profession.key in self.chosen())
        slot_ids = self.world.fill_slot_data()["professions"]
        self.assertEqual({load_game_data().professions_by_id[i].key for i in slot_ids}, self.chosen())

    def test_generation_succeeds_for_both_factions(self):
        for faction, start in (("alliance", "elwynn_forest"), ("horde", "durotar")):
            with self.subTest(faction=faction):
                self.generate(faction=faction, start_zone=start, profession_mode="solo")
                self.assertTrue(self.multiworld.can_beat_game(self.multiworld.get_all_state()))


class TestTeam(ModeWorldBase):
    def test_team_size_three_gives_six_primaries_and_all_secondaries(self):
        self.generate(profession_mode="team", team_size=3)
        self.assertEqual(len(self.chosen_primaries()), 6)
        self.assertEqual(self.chosen() - PRIMARIES, SECONDARIES)

    def test_default_team_size_is_two_members(self):
        self.generate(profession_mode="team")
        self.assertEqual(len(self.chosen_primaries()), 4)

    def test_a_limit_above_the_available_primaries_keeps_them_all(self):
        self.generate(profession_mode="team", team_size=4, professions=["mining", "alchemy", "herbalism"])
        self.assertEqual(self.chosen(), {"mining", "alchemy", "herbalism"})
        self.generate(profession_mode="team", team_size=4)
        self.assertEqual(len(self.chosen_primaries()), 8)

    def test_generation_succeeds_for_both_factions(self):
        for faction, start in (("alliance", "elwynn_forest"), ("horde", "durotar")):
            with self.subTest(faction=faction):
                self.generate(faction=faction, start_zone=start, profession_mode="team", team_size=3)
                self.assertTrue(self.multiworld.can_beat_game(self.multiworld.get_all_state()))


class TestSelfFoundRule(ModeWorldBase):
    def test_a_crafter_is_never_picked_without_its_gatherer(self):
        for seed in SEEDS:
            with self.subTest(seed=seed):
                self.generate(seed, profession_mode="solo", **SELF_FOUND,
                              professions=["blacksmithing", "tailoring", "mining"])
                if "blacksmithing" in self.chosen():
                    self.assertIn("mining", self.chosen())
                self.assertEqual(len(self.chosen()), 2)

    def test_no_pair_that_can_get_its_materials_is_an_option_error(self):
        with self.assertRaises(OptionError) as error:
            self.generate(profession_mode="solo", **SELF_FOUND,
                          professions=["blacksmithing", "engineering", "leatherworking"])
        message = str(error.exception)
        self.assertIn("no 2 primary professions", message)
        self.assertIn("Auction House, trading, mail and shared banks all off", message)

    def test_market_access_lifts_the_rule(self):
        self.generate(profession_mode="solo", professions=["blacksmithing", "engineering", "leatherworking"])
        self.assertEqual(len(self.chosen_primaries()), 2)


class TestStartInfoLines(unittest.TestCase):
    data = load_game_data()
    full = {"faction": "alliance", "start_zone": 1429, "goal_level": 60,
            "professions": [186, 171, 185, 129, 356]}

    def test_full_slot_data_gives_the_five_lines(self):
        self.assertEqual(start_info_lines(self.full, self.data), [
            "Faction: Alliance", "Start zone: Elwynn Forest", "Goal level: 60",
            "Primary professions: Mining, Alchemy", "Secondary professions: Cooking, First Aid, Fishing"])

    def test_the_faction_is_capitalised(self):
        self.assertEqual(start_info_lines({**self.full, "faction": "horde"}, self.data)[0], "Faction: Horde")

    def test_an_empty_list_shows_none(self):
        lines = start_info_lines({**self.full, "professions": [171]}, self.data)
        self.assertEqual(lines[3:], ["Primary professions: Alchemy", "Secondary professions: none"])
        lines = start_info_lines({**self.full, "professions": []}, self.data)
        self.assertEqual(lines[3:], ["Primary professions: none", "Secondary professions: none"])

    def test_unknown_ids_get_a_fallback(self):
        lines = start_info_lines({**self.full, "start_zone": 1234, "professions": [123, 171]}, self.data)
        self.assertEqual(lines[1], "Start zone: zone 1234")
        self.assertEqual(lines[3], "Primary professions: profession 123, Alchemy")

    def test_missing_keys_show_unknown(self):
        self.assertEqual(start_info_lines({}, self.data), [
            "Faction: unknown", "Start zone: unknown", "Goal level: unknown",
            "Primary professions: unknown", "Secondary professions: unknown"])


class TestSpoilerHeader(ModeWorldBase):
    def test_the_spoiler_log_names_the_start_zone_and_professions_of_the_slot(self):
        self.generate(profession_mode="solo", professions=["mining", "tailoring", "cooking"])
        handle = io.StringIO()
        self.world.write_spoiler_header(handle)
        lines = handle.getvalue().splitlines()
        player = self.multiworld.player_name[self.player]
        self.assertEqual(lines[1], f"{player}: Start zone: {self.world.start_zone.name}")
        self.assertIn(f"{player}: Primary professions: Mining, Tailoring", lines)
        self.assertIn(f"{player}: Secondary professions: Cooking", lines)
        self.assertEqual(len(lines), 5)
