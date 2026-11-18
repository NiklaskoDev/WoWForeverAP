import shutil

import gen_addon_data as gen
import pytest
from worlds.wow_forever import data_loader, ids
from worlds.wow_forever.client.lua_table import parse_assignments
from worlds.wow_forever.data_loader import load_game_data, parse_game_data, read_shipped_files
from worlds.wow_forever.items import ITEM_NAME_TO_ID

DATA_PREFIX = "ns.Data = "


@pytest.fixture
def output_paths(tmp_path, monkeypatch):
    """Redirect the generator's output files into a temporary folder."""
    generated = tmp_path / "Data" / "Generated.lua"
    fixture = tmp_path / "fixtures" / "ids.lua"
    monkeypatch.setattr(gen, "GENERATED_FILE", generated)
    monkeypatch.setattr(gen, "IDS_FIXTURE_FILE", fixture)
    monkeypatch.setattr(gen, "INBOX_FIXTURE_FILE", tmp_path / "fixtures" / "inbox_from_client.lua")
    guide = tmp_path / "docs" / "guide.md"
    guide.parent.mkdir()
    shutil.copyfile(gen.GUIDE_FILE, guide)
    monkeypatch.setattr(gen, "GUIDE_FILE", guide)
    return generated, fixture


@pytest.fixture
def guide_file(output_paths):
    return gen.GUIDE_FILE


def generated_data() -> dict:
    """The tables of Generated.lua, parsed back with the project's own Lua parser."""
    text = gen.build_generated(load_game_data())
    assert DATA_PREFIX in text
    return parse_assignments("DATA = " + text.split(DATA_PREFIX, 1)[1])["DATA"]


def test_shipped_generated_files_are_up_to_date():
    assert gen.main(["--check"]) == 0


def test_generated_tables_match_the_csv_data():
    data, tables = load_game_data(), generated_data()
    assert tables["levelGoal"] == data_loader.MAX_GOAL_LEVEL == 60
    assert set(tables["zones"]) == {zone.ui_map_id for zone in data.zones}
    assert tables["zones"][1429] == {"name": "Elwynn Forest", "min": 1, "max": 10, "faction": "alliance",
                                     "release": 1}
    assert tables["quests"] == {quest.quest_id: quest.zone_ui_map_id for quest in data.quests}
    assert set(tables["quests"].values()) <= set(tables["zones"])
    assert tables["professions"][171] == {"key": "alchemy", "name": "Alchemy", "kind": "primary", "release": 1}
    assert [tier["maxSkill"] for tier in tables["tiers"]] == [75, 150, 225, 300]
    # the parser turns a table keyed exactly 1..n into a list
    assert tables["fillers"] == [{"name": "Traveler's Tale", "release": 1}]  # the care package is not a filler
    assert tables["carePackageItemId"] == ids.item_id(ids.ItemCat.CARE_PACKAGE, 1) == 5_140_000_001


def test_generated_category_tables_match_the_csv_data():
    data, tables = load_game_data(), generated_data()
    assert set(tables["areas"]) == {area.area_id for area in data.discoveries}
    assert tables["areas"][18] == {"name": "Crystal Lake", "zone": 1429}
    assert all(area["zone"] in tables["zones"] for area in tables["areas"].values())
    assert tables["factions"][72] == "Stormwind"
    assert set(tables["factions"]) == {reputation.faction_id for reputation in data.reputations}
    assert tables["pvp"][10] == {"kind": "bg_win", "param": 489, "name": "Win Warsong Gulch"}
    assert tables["pvp"][1] == {"kind": "hk_total", "param": 100, "name": "100 Honorable Kills"}
    assert set(tables["pvp"]) == {milestone.pvp_id for milestone in data.pvp_milestones}


def test_generated_boss_table_follows_instances_and_encounters():
    files = read_shipped_files()
    files["instances.csv"] += "9100,Fixture Dungeon,dungeon,1436,15,5,both,1\n"
    files["encounters.csv"] += "9001,Boss A,9100,1\n"
    text = gen.build_generated(parse_game_data(files))
    tables = parse_assignments("DATA = " + text.split(DATA_PREFIX, 1)[1])["DATA"]
    assert tables["bosses"] == {9001: {"name": "Boss A", "instance": "Fixture Dungeon", "zone": 1436}}
    assert generated_data()["bosses"] == {}  # the shipped data has no boss rows yet


def test_inbox_fixture_carries_the_category_switches():
    slot = parse_assignments(gen.build_inbox_fixture())["WoWForeverAP_Inbox"]["slots"]["AP_1234:Wow"]
    assert slot["options"]["categories"] == {"boss": True, "discovery": True, "reputation": False, "pvp": False}


def test_generation_is_deterministic():
    assert gen.build_generated(load_game_data()) == gen.build_generated(load_game_data())
    assert gen.build_ids_fixture() == gen.build_ids_fixture()


def test_ids_fixture_covers_every_category_with_python_ids():
    text = gen.build_ids_fixture()
    fixture = parse_assignments("FIXTURE = " + text.split("return ", 1)[1])["FIXTURE"]
    assert fixture["constants"]["base"] == ids.BASE
    assert fixture["constants"]["categorySize"] == ids.CATEGORY_SIZE
    assert fixture["constants"]["professionSkill"] == {"skillLineId": 171, "skill": 75, "native": 171_075}
    seen = {(case["kind"], case["category"]) for case in fixture["cases"]}
    assert seen == ({("location", int(c)) for c in ids.LocCat} | {("item", int(c)) for c in ids.ItemCat})
    builders = {"location": ids.location_id, "item": ids.item_id}
    for case in fixture["cases"]:
        assert case["id"] == builders[case["kind"]](case["category"], case["native"])


def test_inbox_fixture_is_what_the_client_writes_and_survives_hostile_names():
    text = gen.build_inbox_fixture()
    inbox = parse_assignments(text)["WoWForeverAP_Inbox"]
    slot = inbox["slots"]["AP_1234:Wow"]
    assert inbox["schema"] == 1
    assert slot["items"][0]["sender"] == 'Anna "The Tank"'
    assert slot["options"]["goalLevel"] == 60
    assert slot["options"]["economy"]["carePackages"] == 5 and slot["options"]["economy"]["mail"] is False
    assert slot["checked"] == {ids.location_id(ids.LocCat.LEVEL, 2): True}
    assert ids.location_id(ids.LocCat.QUEST, 783) in slot["locations"]


def test_check_fails_for_missing_files_and_write_creates_them(output_paths, capsys):
    generated, fixture = output_paths
    assert gen.main(["--check"]) == 1
    assert not generated.exists()
    assert "out of date" in capsys.readouterr().err
    assert gen.main([]) == 0
    assert generated.read_text(encoding="utf-8") == gen.build_generated(load_game_data())
    assert fixture.read_text(encoding="utf-8") == gen.build_ids_fixture()
    assert gen.main(["--check"]) == 0


def test_check_fails_when_a_csv_changed_and_the_lua_was_not_regenerated(output_paths, monkeypatch, capsys):
    generated, _ = output_paths
    assert gen.main([]) == 0
    files = read_shipped_files()
    files["zones.csv"] = files["zones.csv"].replace("Elwynn Forest", "Elwynn Forest Renamed", 1)
    monkeypatch.setattr(gen.data_loader, "load_game_data", lambda: parse_game_data(files))
    assert gen.main(["--check"]) == 1
    assert "Generated.lua" in capsys.readouterr().err
    assert "Elwynn Forest Renamed" not in generated.read_text(encoding="utf-8")
    assert gen.main([]) == 0
    assert "Elwynn Forest Renamed" in generated.read_text(encoding="utf-8")
    assert gen.main(["--check"]) == 0


GUIDE_TEXT = f"intro\n\n{gen.GUIDE_BEGIN}\nold\n{gen.GUIDE_END}\n\noutro\n"


def test_guide_section_names_every_item_and_the_rank_and_material_rows():
    section = gen.build_guide_section(load_game_data())
    for name in ITEM_NAME_TO_ID:
        assert name in section
    assert "| 1 | Apprentice | 75 | 5 | 5 | Launch |" in section
    assert "| 4 | Artisan | 300 | 35 | 45 | Launch |" in section
    assert "| Progressive Alchemy | primary | Herbalism |" in section
    assert "| Progressive Mining | primary | supplies Blacksmithing and Engineering |" in section
    assert "| Zone: Westfall | Alliance | 10-20 |  | The Deadmines | Launch |" in section
    assert "| Zone: Elwynn Forest | Alliance | 1-10 | yes |  | Launch |" in section
    assert gen.GUIDE_BEGIN not in section and gen.GUIDE_END not in section


def test_the_guide_section_is_deterministic():
    assert gen.build_guide_section(load_game_data()) == gen.build_guide_section(load_game_data())


def test_splice_replaces_only_between_the_markers_and_is_idempotent():
    once = gen.splice_guide(GUIDE_TEXT, "NEW")
    assert once == f"intro\n\n{gen.GUIDE_BEGIN}\n\nNEW\n\n{gen.GUIDE_END}\n\noutro\n"
    assert once.startswith("intro\n\n" + gen.GUIDE_BEGIN) and once.endswith(gen.GUIDE_END + "\n\noutro\n")
    assert gen.splice_guide(once, "NEW") == once
    assert gen.splice_guide(once, "NEWER").count("NEWER") == 1 and "NEW\n" not in gen.splice_guide(once, "NEWER")


@pytest.mark.parametrize("text", [
    "no markers",
    f"{gen.GUIDE_BEGIN}\nonly begin",
    f"only end\n{gen.GUIDE_END}",
    f"{gen.GUIDE_END}\n{gen.GUIDE_BEGIN}",
    f"{gen.GUIDE_BEGIN}\n{gen.GUIDE_BEGIN}\n{gen.GUIDE_END}",
    f"{gen.GUIDE_BEGIN}\n{gen.GUIDE_END}\n{gen.GUIDE_END}",
])
def test_splice_refuses_missing_doubled_or_misordered_markers(text):
    with pytest.raises(gen.GuideMarkerError, match="exactly once|BEGIN|must contain"):
        gen.splice_guide(text, "NEW")


def test_check_reports_a_guide_without_markers_and_leaves_it_alone(guide_file, capsys):
    guide_file.write_text("# No markers here\n", encoding="utf-8")
    assert gen.main(["--check"]) == 1
    assert "error:" in capsys.readouterr().err
    assert gen.main([]) == 1
    assert guide_file.read_text(encoding="utf-8") == "# No markers here\n"


def test_a_missing_guide_is_a_marker_error(guide_file):
    guide_file.unlink()
    with pytest.raises(gen.GuideMarkerError, match="missing"):
        gen.expected_outputs()


def test_check_fails_for_a_stale_guide_and_write_fixes_only_the_section(guide_file, monkeypatch, capsys):
    assert gen.main([]) == 0
    before = guide_file.read_text(encoding="utf-8")
    prefix, rest = before.split(gen.GUIDE_BEGIN)
    suffix = rest.split(gen.GUIDE_END)[1]
    files = read_shipped_files()
    files["zones.csv"] = files["zones.csv"].replace("Elwynn Forest", "Elwynn Forest Renamed", 1)
    monkeypatch.setattr(gen.data_loader, "load_game_data", lambda: parse_game_data(files))
    assert gen.main(["--check"]) == 1
    assert gen.display_path(guide_file) in capsys.readouterr().err
    assert guide_file.read_text(encoding="utf-8") == before
    assert gen.main([]) == 0
    after = guide_file.read_text(encoding="utf-8")
    assert "Zone: Elwynn Forest Renamed" in after
    assert after.startswith(prefix + gen.GUIDE_BEGIN) and after.endswith(gen.GUIDE_END + suffix)
    assert gen.main(["--check"]) == 0


def test_the_stale_message_names_the_guide(guide_file, capsys):
    assert gen.main([]) == 0
    guide_file.write_text(guide_file.read_text(encoding="utf-8").replace("| Zone: Westfall |", "| Zone: Old |"),
                          encoding="utf-8")
    assert gen.main(["--check"]) == 1
    assert gen.display_path(guide_file) in capsys.readouterr().err


def test_cell_escapes_pipes_so_a_table_row_keeps_its_columns():
    assert gen._cell("a|b") == "a\\|b"
    files = read_shipped_files()
    files["zones.csv"] = files["zones.csv"].replace("Westfall", "West|fall", 1)
    section = gen.build_guide_section(parse_game_data(files))
    assert "| Zone: West\\|fall | Alliance |" in section
