import pytest
from worlds.wow_forever import data_loader
from worlds.wow_forever.data_loader import DataError, load_game_data, parse_game_data, read_shipped_files

QUEST_HEADER = "quest_id,name,zone_ui_map_id,req_level,faction,release,prereq_quest_ids,extra_zone_ids,name_suffix\n"


def shipped(**overrides: str) -> dict[str, str]:
    """Shipped CSV texts with whole files replaced, keyed by file name without extension."""
    files = read_shipped_files()
    for name, text in overrides.items():
        files[f"{name}.csv"] = text
    return files


def replace_in(file_name: str, old: str, new: str) -> dict[str, str]:
    files = read_shipped_files()
    assert old in files[file_name], f"fixture drift: '{old}' not in {file_name}"
    files[file_name] = files[file_name].replace(old, new, 1)
    return files


def line_of(file_name: str, prefix: str) -> int:
    for number, line in enumerate(read_shipped_files()[file_name].splitlines(), start=1):
        if line.startswith(prefix):
            return number
    raise AssertionError(prefix)


def assert_error(files: dict[str, str], file: str, line: int | None, fragment: str) -> None:
    with pytest.raises(DataError) as error:
        parse_game_data(files)
    assert error.value.file == file
    assert error.value.line == line
    assert fragment in str(error.value)
    assert file in str(error.value)


# --- shipped data ---------------------------------------------------------------------------

def test_shipped_data_loads_and_is_cached():
    data = load_game_data()
    assert load_game_data() is data
    assert data.zones and data.quests and data.professions and data.profession_tiers and data.misc_items


def test_shipped_data_has_launch_release_and_start_zones_for_both_factions():
    data = load_game_data()
    assert data.releases_by_id[1].key == "launch"
    starts = {zone.faction for zone in data.zones if zone.is_start}
    assert {"alliance", "horde"} <= starts


def test_shipped_quests_sit_in_zones_of_their_faction_or_both():
    data = load_game_data()
    for quest in data.quests:
        zone = data.zones_by_id[quest.zone_ui_map_id]
        assert zone.faction in (quest.faction, "both"), quest.location_name


def test_ap_names_follow_the_plan():
    data = load_game_data()
    assert data.zones_by_id[1429].item_name == "Zone: Elwynn Forest"
    assert data.professions_by_id[171].item_name == "Progressive Alchemy"
    assert data.quests_by_id[783].location_name == "Elwynn Forest: A Threat Within"
    assert data.quests_by_id[457].location_name == "Teldrassil: The Balance of Nature (2)"


def test_shipped_prerequisite_chain_stays_in_the_start_zone():
    data = load_game_data()
    assert data.quests_by_id[33].effective_zones == (1429,)
    assert data.quests_by_id[33].effective_level == 1


# --- derived fields on fixtures --------------------------------------------------------------

def test_effective_zones_and_level_include_prerequisites():
    quests = (
        QUEST_HEADER
        + "1,First,1429,3,both,1,,,\n"
        + "2,Second,1436,12,both,1,1,1426,\n"
        + "3,Third,1426,5,both,1,2,,\n"
    )
    data = parse_game_data(shipped(quests=quests))
    assert data.quests_by_id[1].effective_zones == (1429,)
    assert data.quests_by_id[2].effective_zones == (1426, 1429, 1436)
    assert data.quests_by_id[2].effective_level == 12
    assert data.quests_by_id[3].effective_zones == (1426, 1429, 1436)
    assert data.quests_by_id[3].effective_level == 12  # own level 5, prerequisite needs 12


# --- failure paths: each names file and line --------------------------------------------------

def test_duplicate_primary_key_names_file_and_line():
    line = line_of("zones.csv", "1426,")
    files = replace_in("zones.csv", "1426,Dun Morogh", "1429,Dun Morogh")
    assert_error(files, "zones.csv", line, "duplicate ui_map_id 1429")


def test_dangling_zone_foreign_key():
    line = line_of("quests.csv", "783,")
    files = replace_in("quests.csv", "783,A Threat Within,1429", "783,A Threat Within,9999")
    assert_error(files, "quests.csv", line, "unknown zone 9999")


def test_dangling_prerequisite_foreign_key():
    line = line_of("quests.csv", "7,")
    files = replace_in("quests.csv", "Cleanup,1429,1,alliance,1,783", "Cleanup,1429,1,alliance,1,55555")
    assert_error(files, "quests.csv", line, "unknown prerequisite quest 55555")


def test_unknown_release():
    line = line_of("zones.csv", "1429,")
    files = replace_in("zones.csv", "1429,Elwynn Forest,1,10,alliance,1,1", "1429,Elwynn Forest,1,10,alliance,1,7")
    assert_error(files, "zones.csv", line, "unknown release 7")


def test_prerequisite_cycle():
    quests = (
        QUEST_HEADER
        + "1,One,1429,1,both,1,3,,\n"
        + "2,Two,1429,1,both,1,1,,\n"
        + "3,Three,1429,1,both,1,2,,\n"
    )
    with pytest.raises(DataError, match="prerequisite cycle") as error:
        parse_game_data(shipped(quests=quests))
    assert error.value.file == "quests.csv"
    assert error.value.line is not None


def test_duplicate_ap_name_after_suffix():
    line = line_of("quests.csv", "457,")
    files = replace_in(
        "quests.csv",
        "457,The Balance of Nature,1438,1,alliance,1,456,,(2)",
        "457,The Balance of Nature,1438,1,alliance,1,456,,",
    )
    assert_error(files, "quests.csv", line, "duplicate AP location name")


def test_min_level_above_max_level():
    line = line_of("zones.csv", "1436,")
    files = replace_in("zones.csv", "1436,Westfall,10,20", "1436,Westfall,21,20")
    assert_error(files, "zones.csv", line, "min_level 21 is above max_level 20")


def test_native_id_out_of_range():
    quests = QUEST_HEADER + "99999999999,Huge,1429,1,both,1,,,\n"
    assert_error(shipped(quests=quests), "quests.csv", 2, "out of range")


def test_wrong_header_and_column_count():
    with pytest.raises(DataError, match="header must be"):
        parse_game_data(shipped(releases="id,key\n1,launch\n"))
    line = line_of("releases.csv", "1,launch")
    files = replace_in("releases.csv", "1,launch,Launch,2026-11-04", "1,launch,Launch")
    assert_error(files, "releases.csv", line, "expected 4 columns")


def test_non_integer_and_bad_choice_values():
    line = line_of("zones.csv", "1429,")
    assert_error(replace_in("zones.csv", "1429,Elwynn Forest,1,10", "1429,Elwynn Forest,x,10"), "zones.csv", line,
                 "min_level must be an integer")
    assert_error(replace_in("zones.csv", "10,alliance,1,1\n1426", "10,neutral,1,1\n1426"), "zones.csv", line,
                 "faction must be one of")


def test_bad_release_date():
    files = replace_in("releases.csv", "Launch,2026-11-04", "Launch,04.11.2026")
    assert_error(files, "releases.csv", line_of("releases.csv", "1,launch"), "date must be YYYY-MM-DD")


def test_tier_gap_and_bracket_coverage():
    tiers = "tier,name,max_skill,required_level,release\n1,A,75,1,1\n3,C,225,1,1\n"
    with pytest.raises(DataError, match="without gaps"):
        parse_game_data(shipped(profession_tiers=tiers))
    brackets = "max_skill,required_level\n75,1\n"
    with pytest.raises(DataError, match="cover every skill"):
        parse_game_data(shipped(material_brackets=brackets))


def test_largest_bracket_must_reach_the_highest_profession_tier():
    # shipped data: tiers end at 300; a bracket table ending exactly at 300 is the boundary that is allowed
    # (the bracket limits stay the ones profession_materials.csv refers to)
    exact = "max_skill,required_level\n75,1\n150,15\n225,30\n300,50\n"
    assert parse_game_data(shipped(material_brackets=exact)).material_brackets[-1].max_skill == 300
    short = "max_skill,required_level\n150,15\n299,45\n"
    with pytest.raises(DataError) as error:
        parse_game_data(shipped(material_brackets=short))
    assert error.value.file == "material_brackets.csv"
    assert "material_brackets.csv" in str(error.value)
    assert "up to 300" in str(error.value)
    assert "largest max_skill is 299" in str(error.value)


def test_a_higher_tier_than_any_bracket_fails_even_when_the_bracket_file_is_unchanged():
    tiers = "tier,name,max_skill,required_level,release\n1,A,75,1,1\n2,B,150,1,1\n3,C,400,1,1\n"
    with pytest.raises(DataError, match="largest max_skill is 300") as error:
        parse_game_data(shipped(profession_tiers=tiers))
    assert error.value.file == "material_brackets.csv"


def test_empty_bracket_table_fails_with_the_same_check():
    with pytest.raises(DataError, match="largest max_skill is 0"):
        parse_game_data(shipped(material_brackets="max_skill,required_level\n"))


def test_missing_filler_and_missing_header():
    with pytest.raises(DataError, match="filler"):
        parse_game_data(shipped(misc_items="native_id,kind,name,release\n"))
    with pytest.raises(DataError, match="missing header"):
        parse_game_data(shipped(releases="# only a comment\n"))


def test_duplicate_item_name_across_files():
    files = replace_in("misc_items.csv", "1,filler,Traveler's Tale,1", "1,filler,Zone: Westfall,1")
    with pytest.raises(DataError, match="duplicate AP item name"):
        parse_game_data(files)


def test_comment_and_blank_lines_are_ignored_but_line_numbers_stay_physical():
    files = shipped(releases="# comment\n\nid,key,label,date\n1,launch,Launch,not-a-date\n")
    assert_error(files, "releases.csv", 4, "date must be")


def test_data_files_constant_matches_shipped_files():
    assert set(read_shipped_files()) == set(data_loader.DATA_FILES)


# --- profession materials and care package ----------------------------------------------------

MATERIALS_HEADER = ("crafting_skill_line_id,max_skill,source,gather_skill_line_id,gather_skill,required_level,"
                    "release\n")


def materials(*rows: str) -> dict[str, str]:
    return shipped(profession_materials=MATERIALS_HEADER + "".join(f"{row}\n" for row in rows))


def test_shipped_materials_cover_every_bracket_of_every_crafting_profession():
    data = load_game_data()
    crafting = {row.crafting_skill_line_id for row in data.profession_materials}
    brackets = {bracket.max_skill for bracket in data.material_brackets}
    assert crafting == {164, 165, 171, 185, 197, 202, 333, 129}  # no gathering profession and no fishing
    for line in crafting:
        covered = {row.max_skill for row in data.profession_materials if row.crafting_skill_line_id == line}
        assert covered == brackets, data.professions_by_id[line].name


def test_shipped_gather_rows_name_gathering_professions_and_valid_tiers():
    data = load_game_data()
    for row in data.profession_materials:
        if row.source == "gather":
            assert data.professions_by_id[row.gather_skill_line_id].key in ("mining", "herbalism", "skinning")
        else:
            assert (row.gather_skill_line_id, row.gather_skill) == (None, 0)


def test_valid_material_rows_parse_with_all_three_sources():
    data = parse_game_data(materials("171,75,gather,182,1,1,1", "171,75,vendor,,0,1,1", "171,150,drops,,0,15,1"))
    assert [row.source for row in data.profession_materials] == ["gather", "vendor", "drops"]
    assert data.profession_materials[0].gather_skill_line_id == 182
    assert data.profession_materials[1].gather_skill_line_id is None


@pytest.mark.parametrize("row, fragment", [
    ("171,75,buy,,0,1,1", "source must be one of"),
    ("999,75,drops,,0,1,1", "crafting_skill_line_id 999 is not in professions.csv"),
    ("171,75,gather,999,1,1,1", "gather_skill_line_id 999 is not in professions.csv"),
    ("171,80,drops,,0,1,1", "max_skill 80 is not a max_skill of material_brackets.csv"),
    ("171,75,gather,,1,1,1", "needs a gather_skill_line_id"),
    ("171,75,gather,171,1,1,1", "cannot gather its own material"),
    ("171,75,gather,182,0,1,1", "gather_skill must be 1..300"),
    ("171,75,gather,182,301,1,1", "gather_skill must be 1..300"),
    ("171,75,drops,182,0,1,1", "must have an empty gather_skill_line_id"),
    ("171,75,vendor,,5,1,1", "must have an empty gather_skill_line_id"),
    ("171,75,drops,,0,1,7", "unknown release 7"),
    ("171,75,drops,,0,x,1", "required_level must be an integer"),
])
def test_invalid_material_rows_name_file_and_line(row, fragment):
    assert_error(materials(row), "profession_materials.csv", 2, fragment)  # line 1 is the header


def test_duplicate_material_row_is_rejected_but_another_gatherer_is_an_alternative():
    assert_error(materials("171,75,drops,,0,1,1", "171,75,drops,,0,1,1"), "profession_materials.csv", 3,
                 "duplicate material source")
    data = parse_game_data(materials("164,75,gather,186,1,1,1", "164,75,gather,182,1,1,1"))
    assert len(data.profession_materials) == 2


def test_care_package_is_one_misc_item_in_category_4_that_may_share_a_native_id_with_the_filler():
    data = load_game_data()
    assert data.care_package.name == "Care Package"
    assert data.care_package.category == data_loader.ids.ItemCat.CARE_PACKAGE
    assert data.care_package.native_id == 1 and any(i.kind == "filler" and i.native_id == 1 for i in data.misc_items)


def test_a_second_care_package_or_none_is_rejected():
    two = "native_id,kind,name,release\n1,filler,Traveler's Tale,1\n1,care_package,A,1\n2,care_package,B,1\n"
    none = "native_id,kind,name,release\n1,filler,Traveler's Tale,1\n"
    for text, found in ((two, 2), (none, 0)):
        with pytest.raises(DataError, match=f"exactly one care_package item is required, found {found}"):
            parse_game_data(shipped(misc_items=text))


def test_duplicate_native_id_within_one_kind_is_rejected():
    files = replace_in("misc_items.csv", "1,care_package,Care Package,1",
                       "1,care_package,Care Package,1\n1,care_package,Other Package,1")
    with pytest.raises(DataError, match="duplicate native_id"):
        parse_game_data(files)


# --- extra check categories (plan 004) --------------------------------------------------------

INSTANCE_HEADER = "instance_id,name,kind,entrance_ui_map_id,min_level,group_size,faction,release\n"
ENCOUNTER_HEADER = "encounter_id,name,instance_id,release\n"
DISCOVERY_HEADER = "area_id,name,ui_map_id,release\n"
REPUTATION_HEADER = "faction_id,standing,name,faction_side,required_level,required_ui_map_ids,release\n"
PVP_HEADER = "pvp_id,kind,param,name,required_level,release\n"
TEST_INSTANCE = "36,Test Mines,dungeon,1436,10,5,both,1"


def with_rows(file: str, header: str, *rows: str, **extra: str) -> dict[str, str]:
    return shipped(**{file: header + "".join(f"{row}\n" for row in rows)}, **extra)


def test_shipped_category_files_load_and_every_foreign_key_resolves():
    data = load_game_data()
    assert data.instances and data.discoveries and data.reputations and data.pvp_milestones
    assert all(instance.entrance_ui_map_id in data.zones_by_id for instance in data.instances)
    assert all(discovery.ui_map_id in data.zones_by_id for discovery in data.discoveries)
    for reputation in data.reputations:
        assert set(reputation.required_ui_map_ids) <= set(data.zones_by_id)
    assert all(encounter.instance_id in data.instances_by_id for encounter in data.encounters)


def test_shipped_raids_are_left_out_until_their_release_is_confirmed():
    data = load_game_data()
    assert not [instance for instance in data.instances if instance.kind == "raid"]
    assert {release.id for release in data.releases} == {1}


def test_shipped_battleground_rows_use_the_classic_battleground_map_ids():
    data = load_game_data()
    wins = {milestone.name: milestone.param for milestone in data.pvp_milestones if milestone.kind == "bg_win"}
    assert wins == {"Win Warsong Gulch": 489, "Win Arathi Basin": 529, "Win Alterac Valley": 30}


def test_shipped_reputation_standings_are_friendly_to_exalted_for_every_faction():
    data = load_game_data()
    by_faction: dict[int, set[int]] = {}
    for reputation in data.reputations:
        by_faction.setdefault(reputation.faction_id, set()).add(reputation.standing)
    assert all(standings == {5, 6, 7, 8} for standings in by_faction.values())
    # a higher standing never needs a lower level than the one below it
    for faction_id in by_faction:
        levels = [data.reputations_by_native[faction_id * 10 + standing].required_level for standing in (5, 6, 7, 8)]
        assert levels == sorted(levels), faction_id


def test_category_ap_names_and_native_ids_follow_the_plan():
    data = parse_game_data(with_rows(
        "instances", INSTANCE_HEADER, TEST_INSTANCE,
        encounters=ENCOUNTER_HEADER + "593,Edwin Test,36,1\n"))
    assert data.encounters_by_id[593].location_name == "Test Mines: Edwin Test"
    stormwind = data_loader.Reputation(72, 6, "Stormwind", "alliance", 20, (1429,), 1)
    assert (stormwind.native_id, stormwind.location_name) == (726, "Stormwind: Honored")
    shipped_data = load_game_data()
    assert shipped_data.discoveries_by_id[18].location_name == "Discover Elwynn Forest: Crystal Lake"
    assert shipped_data.reputations_by_native[728].location_name == "Stormwind: Exalted"
    assert shipped_data.pvp_by_id[10].location_name == "PvP: Win Warsong Gulch"


def test_an_instance_may_be_a_raid_and_encounters_may_be_empty():
    raid = "409,Molten Core,raid,1434,50,40,both,1\n"
    data = parse_game_data(with_rows("instances", INSTANCE_HEADER, TEST_INSTANCE, raid))
    assert [instance.kind for instance in data.instances] == ["dungeon", "raid"]
    assert not parse_game_data(shipped(encounters=ENCOUNTER_HEADER)).encounters


@pytest.mark.parametrize("row, fragment", [
    ("36,Test Mines,cave,1436,10,5,both,1", "kind must be one of dungeon, raid"),
    ("36,Test Mines,dungeon,9999,10,5,both,1", "unknown zone 9999"),
    ("36,Test Mines,dungeon,1436,0,5,both,1", "min_level must be 1..60, got 0"),
    ("36,Test Mines,dungeon,1436,61,5,both,1", "min_level must be 1..60, got 61"),
    ("36,Test Mines,dungeon,1436,10,0,both,1", "group_size must be at least 1"),
    ("36,Test Mines,dungeon,1436,10,5,neutral,1", "faction must be one of"),
    ("36,Test Mines,dungeon,1436,10,5,both,7", "unknown release 7"),
    ("36,,dungeon,1436,10,5,both,1", "name must not be empty"),
])
def test_invalid_instance_rows_name_file_and_line(row, fragment):
    assert_error(with_rows("instances", INSTANCE_HEADER, row), "instances.csv", 2, fragment)


def test_duplicate_instance_id():
    files = with_rows("instances", INSTANCE_HEADER, TEST_INSTANCE, TEST_INSTANCE)
    assert_error(files, "instances.csv", 3, "duplicate instance_id 36")


@pytest.mark.parametrize("row, fragment", [
    ("593,Edwin Test,999,1", "unknown instance 999"),
    ("593,Edwin Test,36,7", "unknown release 7"),
    ("-5,Edwin Test,36,1", "out of range"),
    ("10000000,Edwin Test,36,1", "out of range"),
    ("593,,36,1", "name must not be empty"),
])
def test_invalid_encounter_rows_name_file_and_line(row, fragment):
    files = with_rows("encounters", ENCOUNTER_HEADER, row, instances=INSTANCE_HEADER + TEST_INSTANCE + "\n")
    assert_error(files, "encounters.csv", 2, fragment)


def test_duplicate_encounter_id_and_the_largest_valid_native_id():
    instances = INSTANCE_HEADER + TEST_INSTANCE + "\n"
    files = with_rows("encounters", ENCOUNTER_HEADER, "593,A,36,1", "593,B,36,1", instances=instances)
    assert_error(files, "encounters.csv", 3, "duplicate encounter_id 593")
    edge = with_rows("encounters", ENCOUNTER_HEADER, "9999999,Last,36,1", instances=instances)
    assert parse_game_data(edge).encounters_by_id[9999999].instance_id == 36


@pytest.mark.parametrize("row, fragment", [
    ("18,Crystal Lake,9999,1", "unknown zone 9999"),
    ("18,Crystal Lake,1429,7", "unknown release 7"),
    ("x,Crystal Lake,1429,1", "area_id must be an integer"),
    ("18,,1429,1", "name must not be empty"),
])
def test_invalid_discovery_rows_name_file_and_line(row, fragment):
    assert_error(with_rows("discoveries", DISCOVERY_HEADER, row), "discoveries.csv", 2, fragment)


def test_duplicate_discovery_area():
    files = with_rows("discoveries", DISCOVERY_HEADER, "18,Crystal Lake,1429,1", "18,Other,1436,1")
    assert_error(files, "discoveries.csv", 3, "duplicate area_id 18")


@pytest.mark.parametrize("row, fragment", [
    ("72,4,Stormwind,alliance,8,1429,1", "standing must be one of 5, 6, 7, 8, got 4"),
    ("72,9,Stormwind,alliance,8,1429,1", "standing must be one of 5, 6, 7, 8, got 9"),
    ("72,5,Stormwind,elves,8,1429,1", "faction_side must be one of"),
    ("72,5,Stormwind,alliance,0,1429,1", "required_level must be 1..60, got 0"),
    ("72,5,Stormwind,alliance,8,1429;9999,1", "unknown zone 9999"),
    ("72,5,Stormwind,alliance,8,1429,7", "unknown release 7"),
    ("999999999,5,Stormwind,alliance,8,1429,1", "out of range"),
])
def test_invalid_reputation_rows_name_file_and_line(row, fragment):
    assert_error(with_rows("reputations", REPUTATION_HEADER, row), "reputations.csv", 2, fragment)


def test_reputation_key_is_faction_and_standing_and_several_required_zones_are_kept():
    rows = ("72,5,Stormwind,alliance,8,1429;1436,1", "72,6,Stormwind,alliance,20,1429,1")
    data = parse_game_data(with_rows("reputations", REPUTATION_HEADER, *rows))
    assert data.reputations_by_native[725].required_ui_map_ids == (1429, 1436)
    assert_error(with_rows("reputations", REPUTATION_HEADER, rows[0], rows[0]), "reputations.csv", 3,
                 "duplicate faction_id/standing (72, 5)")


@pytest.mark.parametrize("row, fragment", [
    ("1,kills,100,100 Kills,20,1", "kind must be one of hk_total, bg_win"),
    ("1,hk_total,0,Zero Kills,20,1", "param must be at least 1"),
    ("1,hk_total,100,100 Kills,0,1", "required_level must be 1..60, got 0"),
    ("1,hk_total,100,100 Kills,61,1", "required_level must be 1..60, got 61"),
    ("1,hk_total,100,100 Kills,20,7", "unknown release 7"),
    ("10000000,hk_total,100,100 Kills,20,1", "out of range"),
])
def test_invalid_pvp_rows_name_file_and_line(row, fragment):
    assert_error(with_rows("pvp", PVP_HEADER, row), "pvp.csv", 2, fragment)


def test_duplicate_pvp_id():
    files = with_rows("pvp", PVP_HEADER, "1,hk_total,100,100 Kills,20,1", "1,hk_total,200,200 Kills,30,1")
    assert_error(files, "pvp.csv", 3, "duplicate pvp_id 1")


def test_location_names_must_be_unique_across_categories():
    clash = with_rows("pvp", PVP_HEADER, "1,hk_total,100,Friendly,20,1",
                      reputations=REPUTATION_HEADER + "72,5,PvP,alliance,8,1429,1\n")
    with pytest.raises(DataError, match=r"duplicate AP location name 'PvP: Friendly' \(also in reputations.csv\)"):
        parse_game_data(clash)
    quest_clash = with_rows("reputations", REPUTATION_HEADER, "72,5,Elwynn Forest,alliance,8,1429,1",
                            quests=QUEST_HEADER + "783,Friendly,1429,1,both,1,,,\n")
    with pytest.raises(DataError, match=r"duplicate AP location name 'Elwynn Forest: Friendly' \(also in quests.csv\)"):
        parse_game_data(quest_clash)
