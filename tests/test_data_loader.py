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
