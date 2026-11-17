import csv
import shutil
from pathlib import Path

import import_att as tool
import pytest
from import_att import AttImportError, AttQuestRow, Exclusion
from worlds.wow_forever import data_loader

FIXTURE = Path(__file__).parent / "fixtures" / "att"
SHA = "8352616d2359e8595d4c1ac26769a067020826a7"


@pytest.fixture(scope="module")
def imported():
    return tool.run_import(FIXTURE, tool.shipped_data_files(), SHA)


@pytest.fixture
def rows(imported):
    return {row.quest_id: row for row in imported[0].rows}


@pytest.fixture
def reasons(imported):
    return {item.quest_id: item.reason for item in imported[0].exclusions if item.reason != "duplicate"}


@pytest.fixture
def att_copy(tmp_path):
    root = tmp_path / "att"
    shutil.copytree(FIXTURE, root)
    return root


def add_quest(root: Path, text: str) -> None:
    """Append a quest to the Elwynn Forest fixture, inside its maproot."""
    path = root / "zones" / "eastern kingdoms" / "elwynn forest.lua"
    content = path.read_text(encoding="utf-8")
    path.write_text(content.replace("\t\tn(QUESTS, {\n\t\t\tq(102,", f"\t\tn(QUESTS, {{\n{text}\n\t\t\tq(102,"),
                    encoding="utf-8")


# --- exclusion reasons ----------------------------------------------------------------------------------------

@pytest.mark.parametrize("quest_id, reason", [
    (104, "nyi"),
    (105, "unobtainable"),
    (106, "future"),
    (108, "removed"),
    (110, "created"),
    (111, "repeatable"),
    (112, "repeatable"),
    (113, "breadcrumb"),
    (115, "class-restricted"),
    (118, "race-restricted"),
    (138, "race-restricted"),
    (119, "profession"),
    (120, "reputation"),
    (121, "lockable"),
    (122, "lockable"),
    (103, "map-outside-zones:1453"),
    (123, "faction-mismatch"),
    (142, "faction-mismatch"),
    (174, "prereq-faction:173"),
    (20000000, "id-out-of-range"),
    (125, "no-name"),
    (150, "outside-maproot"),
    (160, "zone-not-in-data"),
    (116, "prereq-excluded:115"),
    (117, "prereq-excluded:116"),
    (130, "prereq-excluded:99999"),
])
def test_each_exclusion_reason(reasons, rows, quest_id, reason):
    assert reasons[quest_id] == reason
    assert quest_id not in rows


def test_the_first_occurrence_of_a_duplicate_id_wins(imported, rows):
    assert [item.reason for item in imported[0].exclusions if item.quest_id == 100] == ["duplicate"]
    assert rows[100].req_level == 5  # the Elwynn Forest one, not the Westfall copy (level 12)
    assert rows[100].zone_id == 1429


def test_timeline_markers_use_the_state_at_the_build_version(rows):
    assert 107 in rows  # added in 1.60.1
    assert 109 in rows  # removed in 1.4.0, added again in 1.60.1
    assert rows[109].faction == "alliance"


@pytest.mark.parametrize("markers, expected", [
    (None, None),
    ([], None),
    (["TIMELINE.ADDED_1_60_1"], None),
    (["TIMELINE.ADDED_1_60_2"], "future"),
    (["TIMELINE.ADDED_1_61_0"], "future"),
    (["TIMELINE.ADDED_2_0_0", "TIMELINE.REMOVED_3_0_0"], "future"),
    (["ADDED_1_4_0", "REMOVED_1_7_0"], "removed"),
    (["REMOVED_1_4_0", "ADDED_1_60_1"], None),
    (["ADDED_1_60_1", "REMOVED_1_4_0"], None),  # the order of the list does not matter, the versions do
    (["ADDED_1_4_0", "REMOVED_1_7_0", "ADDED_1_60_1"], None),
    (["TIMELINE.CREATED_1_60_1"], "created"),
    (["CREATED_1_60_1", "ADDED_1_60_1"], None),
    (["DELETED_1_5_0"], "removed"),
    (["TIMELINE.SOMETHING_ELSE"], None),
])
def test_timeline_exclusion(markers, expected):
    nodes = None if markers is None else [tool.att_lua.AttName(marker) for marker in markers]
    assert tool.timeline_exclusion(nodes, (1, 60, 1)) == expected


def add_westfall_quest(root: Path, text: str) -> None:
    path = root / "zones" / "eastern kingdoms" / "westfall.lua"
    content = path.read_text(encoding="utf-8")
    path.write_text(content.replace("\t\t\tq(143,", f"{text}\n\t\t\tq(143,"), encoding="utf-8")


def quest_block(quest_id: int, name: str, body: str = "lvl = 12,") -> str:
    return f"\t\t\tq({quest_id}, {{\t-- {name}\n\t\t\t\t{body}\n\t\t\t}}),"


def test_an_excluded_first_occurrence_does_not_hide_a_later_valid_one(att_copy):
    add_quest(att_copy, quest_block(400, "Excluded First", "u = 1,"))
    add_westfall_quest(att_copy, quest_block(400, "Valid Later"))
    result = tool.run_import(att_copy, tool.shipped_data_files(), SHA)[0]
    kept = {row.quest_id: row for row in result.rows}
    assert (kept[400].name, kept[400].zone_id) == ("Valid Later", 1436)
    assert [item.reason for item in result.exclusions if item.quest_id == 400] == ["unobtainable"]


def test_of_two_valid_occurrences_the_first_wins_and_the_later_is_a_duplicate(att_copy):
    add_quest(att_copy, quest_block(401, "First One"))
    add_westfall_quest(att_copy, quest_block(401, "Second One"))
    result = tool.run_import(att_copy, tool.shipped_data_files(), SHA)[0]
    assert {row.quest_id: row.name for row in result.rows}[401] == "First One"
    assert [(item.reason, item.name) for item in result.exclusions if item.quest_id == 401] == [
        ("duplicate", "Second One")]


def test_a_duplicate_does_not_count_as_an_unresolved_map(att_copy):
    add_quest(att_copy, quest_block(402, "Kept Here"))
    add_westfall_quest(att_copy, quest_block(402, "Copy In The City", "coord = { 1.0, 2.0, MAP.STORMWIND_CITY },"))
    result = tool.run_import(att_copy, tool.shipped_data_files(), SHA)[0]
    assert dict(result.unresolved) == {1453: 1}  # only quest 103
    assert [item.reason for item in result.exclusions if item.quest_id == 402] == ["duplicate"]


def test_an_occurrence_that_is_excluded_for_its_map_does_not_make_a_later_one_a_duplicate(att_copy):
    add_quest(att_copy, quest_block(403, "City First", "coord = { 1.0, 2.0, MAP.STORMWIND_CITY },"))
    add_westfall_quest(att_copy, quest_block(403, "Westfall Later"))
    result = tool.run_import(att_copy, tool.shipped_data_files(), SHA)[0]
    assert {row.quest_id: row.name for row in result.rows}[403] == "Westfall Later"


# --- zones, maps, levels --------------------------------------------------------------------------------------

def test_a_sub_zone_map_resolves_to_the_root_zone(rows):
    assert rows[101].extra_zone_ids == ()
    assert rows[136].extra_zone_ids == ()  # a bare local name declared by m(...) in the same maproot


def test_a_map_resolves_through_its_parent_map(rows):
    assert rows[102].extra_zone_ids == (1436,)


def test_flat_coords_maps_and_bare_legacy_names_give_extra_zones(rows):
    assert rows[134].extra_zone_ids == (1436,)
    assert rows[135].extra_zone_ids == (1436,)


def test_the_unresolved_map_is_counted(imported):
    assert dict(imported[0].unresolved) == {1453: 1}


def test_missing_level_uses_the_zone_minimum_and_clamps_and_calls(rows):
    assert rows[127].req_level == 1 and rows[127].att_level is None
    assert rows[132].req_level == 60
    assert rows[133].req_level == 12
    assert rows[143].req_level == 14


# --- factions -------------------------------------------------------------------------------------------------

def test_factions_come_from_the_races(rows):
    assert rows[100].faction == "alliance"
    assert rows[171].faction == "alliance"
    assert rows[173].faction == "horde"
    assert rows[140].faction == "alliance"  # allianceQuestData of a container, shared fields applied
    assert rows[140].req_level == 9


def test_a_quest_without_races_takes_the_faction_of_its_zone(rows):
    assert rows[102].faction == "alliance"  # Elwynn Forest
    assert rows[143].faction == "alliance"  # Westfall
    assert rows[170].faction == "both"  # Ashenvale is open to both


def test_a_faction_less_quest_takes_the_faction_of_its_prerequisite(rows):
    assert rows[172].faction == "alliance"


def test_an_unknown_race_is_an_error_naming_it(att_copy, capsys):
    add_quest(att_copy, "\t\t\tq(300, {\t-- New Race\n\t\t\t\traces = { SKYBORNE_ALLIANCE, SOME_NEW_RACE },\n\t\t\t}),")
    assert tool.main(["--att-root", str(att_copy), "--out", str(att_copy / "q.csv"),
                      "--report", str(att_copy / "r.txt")]) == 1
    assert "SOME_NEW_RACE" in capsys.readouterr().err


def test_the_alliance_and_horde_race_sets_map_to_their_factions():
    def names(*race_names):
        return [tool.att_lua.AttName(name) for name in race_names]

    assert tool._race_faction(names(*tool.ALLIANCE_RACES)) == "alliance"
    assert tool._race_faction(names(*tool.HORDE_RACES)) == "horde"
    assert tool._race_faction(names("HUMAN")) == "restricted"
    assert tool._race_faction(names("SKYBORNE_ALLIANCE", "SKYBORNE_HORDE")) == "restricted"
    assert tool._race_faction(tool.att_lua.AttName("SKYBORNE_HORDE")) == "restricted"


# --- prerequisites --------------------------------------------------------------------------------------------

def test_a_prerequisite_that_is_a_breadcrumb_or_repeatable_only_loses_its_edge(rows):
    assert rows[114].prereq_ids == ()


def test_prerequisites_are_the_union_of_source_quest_and_source_quests(rows):
    assert rows[131].prereq_ids == (100, 101)
    assert rows[101].prereq_ids == (100,)


def row(quest_id, faction="both", prereqs=()):
    return AttQuestRow(quest_id, f"Quest {quest_id}", 1429, 5, faction, tuple(prereqs), (), 5)


def test_prerequisite_faction_conflict_excludes_the_quest():
    kept, dropped = tool.resolve_prereqs([row(1, "horde"), row(2, "alliance", [1]), row(3, "both", [2])], [])
    assert [item.quest_id for item in kept] == [1]
    assert {item.quest_id: item.reason for item in dropped} == {2: "prereq-faction:1", 3: "prereq-excluded:2"}


def test_faction_narrowing_follows_a_chain():
    kept, dropped = tool.resolve_prereqs([row(1, "horde"), row(2, "both", [1]), row(3, "both", [2])], [])
    assert {item.quest_id: item.faction for item in kept} == {1: "horde", 2: "horde", 3: "horde"}
    assert dropped == []


@pytest.mark.parametrize("reasons, kept", [
    (["breadcrumb", "repeatable"], True),
    (["repeatable", "breadcrumb"], True),
    (["breadcrumb", "class-restricted"], False),
    (["class-restricted", "breadcrumb"], False),  # the order of the records must not matter
    (["repeatable", "zone-not-in-data", "breadcrumb"], False),
])
def test_a_prerequisite_id_only_loses_its_edge_when_every_exclusion_of_it_allows_that(reasons, kept):
    gone = [Exclusion(9, "Gone", reason, 1429) for reason in reasons]
    rows, dropped = tool.resolve_prereqs([row(1, prereqs=[9])], gone)
    assert [item.quest_id for item in rows] == ([1] if kept else [])
    assert [item.reason for item in dropped] == ([] if kept else ["prereq-excluded:9"])


def test_exclusions_cascade_in_any_order():
    gone = [Exclusion(9, "Gone", "class-restricted", 1429)]
    kept, dropped = tool.resolve_prereqs([row(3, prereqs=[2]), row(2, prereqs=[9]), row(1)], gone)
    assert [item.quest_id for item in kept] == [1]
    assert sorted(item.quest_id for item in dropped) == [2, 3]


# --- names ----------------------------------------------------------------------------------------------------

def test_quests_with_the_same_ap_name_get_their_id_as_suffix(rows):
    assert rows[128].name_suffix == "(#128)"
    assert rows[129].name_suffix == "(#129)"
    assert rows[100].name_suffix == ""


def test_the_same_title_in_different_zones_needs_no_suffix():
    zones = {1: type("Zone", (), {"name": "A"})(), 2: type("Zone", (), {"name": "B"})()}
    rows = [AttQuestRow(1, "Same", 1, 1, "both", (), (), 1), AttQuestRow(2, "Same", 2, 1, "both", (), (), 1)]
    assert [item.name_suffix for item in tool.assign_suffixes(rows, zones)] == ["", ""]


def test_names_are_one_line_and_capped():
    call = tool.att_lua.AttCall("q", [1, {}], 1, "  Two   words  " + "x" * 200)
    name = tool._raw_quest(call, None, None, "f", 1429, frozenset()).name
    assert name.startswith("Two words xxx") and len(name) == tool.MAX_NAME_LENGTH
    assert tool._raw_quest(tool.att_lua.AttCall("q", [1], 1, None), None, None, "f", 1429, frozenset()).name is None


# --- output ---------------------------------------------------------------------------------------------------

def test_the_generated_csv_loads_with_the_data_loader(imported):
    result, game_data, _ = imported
    text = tool.render_quests_csv(result.rows, game_data.zones_by_id, SHA, result.build)
    data = data_loader.parse_game_data({**tool.shipped_data_files(), "quests.csv": text})
    quest = data.quests_by_id[100]
    assert quest.location_name == "Elwynn Forest: Kept Simple"
    assert data.quests_by_id[128].location_name == "Elwynn Forest: Twin Name (#128)"
    assert data.quests_by_id[139].name == 'Tricky Name -- with a dash, a "quote" and a, comma'
    assert data.quests_by_id[102].effective_zones == (1429, 1436)


def test_the_header_names_the_commit_and_build_and_rows_follow_the_zone_order(imported):
    result, game_data, _ = imported
    text = tool.render_quests_csv(result.rows, game_data.zones_by_id, SHA, result.build)
    lines = text.splitlines()
    assert lines[0].startswith("# GENERATED by tools/import_att.py")
    assert f"commit {SHA}, build 1.60.1.70959" in lines[1]
    cells = [next(csv.reader([line])) for line in lines if line[0].isdigit()]
    assert [int(cell[0]) for cell in cells[:3]] == [100, 101, 102]  # Elwynn Forest rows come first, by id
    zone_order = list(game_data.zones_by_id)
    positions = [zone_order.index(int(cell[2])) for cell in cells]
    assert positions == sorted(positions)
    assert {int(cell[2]) for cell in cells} == {1429, 1436, 1440}


def test_rows_that_fail_validation_are_an_error(att_copy):
    zone_path = att_copy / "zones" / "eastern kingdoms" / "elwynn forest.lua"
    text = zone_path.read_text(encoding="utf-8")  # 101 already needs 100: make 100 need 101
    cyclic = text.replace("q(100, {\t-- Kept Simple", "q(100, {\t-- Kept Simple\n\t\t\t\t\t\tsourceQuest = 101,")
    zone_path.write_text(cyclic, encoding="utf-8")
    with pytest.raises(AttImportError, match="fail validation.*cycle"):
        tool.run_import(att_copy, tool.shipped_data_files(), SHA)


def test_the_report_lists_reasons_zones_and_profession_flags(imported):
    result, game_data, raw_count = imported
    skill_lines, ranks = tool._read_report_inputs(FIXTURE, result.build)
    report = tool.build_report(result, game_data, skill_lines, ranks, raw_count)
    assert f"{raw_count} quests read, {len(result.rows)} kept, {len(result.exclusions)} excluded." in report
    assert "  nyi: 1" in report
    assert "    104  Never Implemented" in report
    assert "    103  Stormwind Giver  (map-outside-zones:1453)" in report
    assert "  1453: 1" in report
    assert "Elwynn Forest" in report and "FLAG" in report  # quest level 60 in a 1-10 zone
    assert "Journeyman is learnable at 80, above Apprentice max_skill 75" in report
    assert "ATT ranks ['Apprentice', 'Journeyman']" in report
    assert "skill line 202 is not in ATT's SkillLineAbility" in report
    assert "Alchemy          ok" in report
    assert "no character-level requirement for profession tiers" in report


def test_zone_levels_flag_a_minimum_gap_and_a_too_low_maximum():
    zones = data_loader.parse_game_data(tool.shipped_data_files()).zones_by_id
    rows = [AttQuestRow(1, "A", 1429, 5, "both", (), (), 5), AttQuestRow(2, "B", 1429, 6, "both", (), (), 6),
            AttQuestRow(3, "C", 1436, 11, "both", (), (), 11), AttQuestRow(4, "D", 1436, 21, "both", (), (), 21),
            AttQuestRow(5, "E", 1426, 3, "both", (), (), 3), AttQuestRow(6, "F", 1426, 8, "both", (), (), 8)]
    lines = {line.split("  ")[0]: line for line in tool._zone_level_lines(rows, zones)}
    assert lines["Elwynn Forest"].endswith("FLAG")  # min 5 vs 1: more than 2 apart
    assert lines["Westfall"].endswith("FLAG")  # max 21 above max_level 20
    assert not lines["Dun Morogh"].endswith("FLAG")


def test_skill_ranks_keep_the_lowest_skill_per_rank():
    text = ("\t[1] = 0,\t-- Alchemy (Apprentice)\r\n\t[2] = 0,\t-- Alchemy (Apprentice)\n"
            "\t[3] = 50,\t-- Alchemy (Journeyman)\n\t[4] = 12,\t-- Elixir of Minor Force\n"
            "\t[5] = 300,\t-- Tailoring (Grand Master)\n")
    assert tool.parse_skill_ranks(text) == {"Alchemy": {"Apprentice": 0, "Journeyman": 50},
                                            "Tailoring": {"Grand Master": 300}}


# --- inputs and the command line ------------------------------------------------------------------------------

def test_maps_with_two_values_for_one_name_are_an_error():
    with pytest.raises(AttImportError, match="MAP.X has two different values"):
        tool.load_maps("\tX = 1;\n\tX = 2;\n")
    assert tool.load_maps("\tA = 1;\n\t\tB\t= 2;\n\tC = 1,\n") == {"A": 1, "B": 2, "C": 1}


def test_two_builds_are_an_error(att_copy):
    wago = att_copy / ".config" / ".wago"
    shutil.copy(wago / "UiMap.1.60.1.70959.csv", wago / "UiMap.1.61.0.71000.csv")
    with pytest.raises(AttImportError, match="2 builds"):
        tool.wago_build(att_copy)
    assert tool.wago_build(FIXTURE) == "1.60.1.70959"
    assert tool.build_version("1.60.1.70959") == (1, 60, 1)


def test_a_map_constant_missing_from_maps_lua_is_an_error(att_copy):
    add_quest(att_copy, "\t\t\tq(301, {\t-- Odd Map\n\t\t\t\tcoord = { 1.0, 2.0, MAP.NOT_THERE },\n\t\t\t}),")
    with pytest.raises(AttImportError, match="MAP.NOT_THERE"):
        tool.run_import(att_copy, tool.shipped_data_files(), SHA)


def test_a_syntax_error_in_a_zone_file_is_an_error_with_its_path(att_copy, capsys):
    (att_copy / "zones" / "eastern kingdoms" / "westfall.lua").write_text("maproot(MAP.WESTFALL, {\n", encoding="utf-8")
    assert tool.main(["--att-root", str(att_copy), "--out", str(att_copy / "q.csv"),
                      "--report", str(att_copy / "r.txt")]) == 1
    error = capsys.readouterr().err
    assert error.startswith("error: ") and "westfall.lua" in error


def test_quests_in_a_file_without_maproot_are_an_error(att_copy):
    (att_copy / "zones" / "stray.lua").write_text("n(QUESTS, { q(1, {\t-- Stray\n}) })\n", encoding="utf-8")
    with pytest.raises(AttImportError, match="stray.lua: quests but no maproot"):
        tool.run_import(att_copy, tool.shipped_data_files(), SHA)


def test_a_missing_att_root_points_at_the_fetch_script(tmp_path, capsys):
    assert tool.main(["--att-root", str(tmp_path / "nothing")]) == 1
    assert "scripts/fetch_att.sh" in capsys.readouterr().err


def test_the_checkout_must_be_at_the_pinned_commit(tmp_path):
    checkout = tmp_path / "AllTheThings"
    (checkout / ".git").mkdir(parents=True)
    (checkout / ".git" / "HEAD").write_text("ref: refs/heads/master\n")
    with pytest.raises(AttImportError, match="pins " + SHA):
        tool.check_checkout(SHA, checkout)
    (checkout / ".git" / "HEAD").write_text(SHA + "\n")
    tool.check_checkout(SHA, checkout)
    with pytest.raises(AttImportError, match="fetch_att.sh"):
        tool.check_checkout(SHA, tmp_path / "missing")


def test_the_pin_file_holds_a_full_commit_hash():
    assert tool._SHA.fullmatch(tool.pinned_sha())


def test_main_writes_the_csv_and_the_report_and_check_compares(tmp_path, capsys):
    out, report = tmp_path / "quests.csv", tmp_path / "out" / "report.txt"
    args = ["--att-root", str(FIXTURE), "--out", str(out), "--report", str(report)]
    assert tool.main(args) == 0
    assert out.read_text(encoding="utf-8").startswith("# GENERATED by tools/import_att.py")
    assert "ATT import report" in report.read_text(encoding="utf-8")
    assert tool.main([*args, "--check"]) == 0
    out.write_text(out.read_text(encoding="utf-8") + "999999,Extra,1429,1,both,1,,,\n", encoding="utf-8")
    capsys.readouterr()
    assert tool.main([*args, "--check"]) == 1
    assert "differs from the ATT import" in capsys.readouterr().err
    out.unlink()
    assert tool.main([*args, "--check"]) == 1  # a missing file differs too


def test_check_writes_nothing(tmp_path):
    out, report = tmp_path / "quests.csv", tmp_path / "report.txt"
    tool.main(["--att-root", str(FIXTURE), "--out", str(out), "--report", str(report), "--check"])
    assert not out.exists() and not report.exists()


def test_a_deeply_nested_zone_file_is_an_error_line_not_a_traceback(att_copy, capsys):
    (att_copy / "zones" / "eastern kingdoms" / "westfall.lua").write_text(
        "maproot(MAP.WESTFALL, { x = " + "not " * 5000 + "1 })\n", encoding="utf-8")
    assert tool.main(["--att-root", str(att_copy), "--out", str(att_copy / "q.csv"),
                      "--report", str(att_copy / "r.txt")]) == 1
    error = capsys.readouterr().err
    assert error.startswith("error: ") and "westfall.lua" in error and "deeper" in error


@pytest.mark.parametrize("relative", [
    "zones/eastern kingdoms/westfall.lua", ".nyi/quests.lua", ".config/constants/maps.lua",
    ".config/exports/Skill Level Requirements.lua", ".config/.wago/UiMap.1.60.1.70959.csv",
])
def test_a_file_that_is_not_utf8_is_an_error_naming_it(att_copy, capsys, relative):
    (att_copy / relative).write_bytes(b"maproot(\xff\xfe broken")
    assert tool.main(["--att-root", str(att_copy), "--out", str(att_copy / "q.csv"),
                      "--report", str(att_copy / "r.txt")]) == 1
    error = capsys.readouterr().err
    assert error.startswith("error: ") and "not valid UTF-8" in error and Path(relative).name in error
    assert "Traceback" not in error
