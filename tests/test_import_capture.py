import csv

import import_capture as tool
from worlds.wow_forever.client.lua_table import render
from worlds.wow_forever.data_loader import read_shipped_files

BUILD = {"version": "1.60.1", "build": "70938", "date": "Nov 12 2026", "toc": 16001}


def write_saved_variables(path, capture):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render("WoWForeverAP_DB", {"schema": 1, "characters": {}, "slots": {}, "capture": capture}),
                    encoding="utf-8")
    return path


def read_csv(path):
    with path.open(encoding="utf-8", newline="") as handle:
        lines = [line for line in handle.read().splitlines() if not line.startswith("#")]
    return list(csv.reader(lines))


def shipped_header(name):
    for line in read_shipped_files()[name].splitlines():
        if line and not line.startswith("#"):
            return line.split(",")
    raise AssertionError(name)


CAPTURE = {
    "enabled": True,
    "build": BUILD,
    "locale": "deDE",
    "zones": {
        1429: {"name": "Wald von Elwynn", "minLevel": 1, "maxLevel": 10, "seen": 5},
        1519: {"name": "Sturmwind, Stadt", "seen": 6},  # the game reported no level range
    },
    "quests": {
        783: {"title": "Eine Gefahr, die lauert", "uiMapId": 1429, "level": 4, "faction": "Alliance", "seen": 7},
        99: {"title": 'Tricky, "quoted"\ntitle', "uiMapId": 1519, "level": 9, "faction": "Horde", "seen": 8},
    },
}


def test_review_files_use_the_shipped_schemas_and_hold_the_captured_rows(tmp_path, capsys):
    source = write_saved_variables(tmp_path / "SavedVariables" / "WoWForeverAP.lua", CAPTURE)
    out = tmp_path / "out"
    assert tool.main([str(source), "--out", str(out)]) == 0
    zones, quests = read_csv(out / "zones.csv"), read_csv(out / "quests.csv")
    assert zones[0] == shipped_header("zones.csv")
    assert quests[0] == shipped_header("quests.csv")
    assert zones[1:] == [
        ["1429", "Wald von Elwynn", "1", "10", "both", "0", "1"],
        ["1519", "Sturmwind, Stadt", "", "", "both", "0", "1"],
    ]
    assert quests[1:] == [
        ["99", 'Tricky, "quoted" title', "1519", "9", "horde", "1", "", "", ""],
        ["783", "Eine Gefahr, die lauert", "1429", "4", "alliance", "1", "", "", ""],
    ]
    assert "1.60.1 (70938)" in capsys.readouterr().out


EXTRA_CAPTURE = {
    "zones": {},
    "quests": {},
    "encounters": {
        1000: {"name": "Edwin Test", "difficultyId": 1, "groupSize": 5, "instanceId": 36, "success": True, "seen": 3},
        1001: {"name": "Wipe Only", "instanceId": 36, "success": False},
        1002: {"name": "Outside", "success": True},  # the game reported no instance
        "x": {"name": "Not a number", "success": True},
    },
    "areas": {
        18: {"name": "Crystal Lake", "uiMapId": 1429, "seen": 4},
        19: {"uiMapId": 1429},
        "y": {"name": "Not a number"},
    },
}


def test_encounter_and_area_review_files_hold_kills_and_explored_areas_only(tmp_path, capsys):
    source = write_saved_variables(tmp_path / "WoWForeverAP.lua", EXTRA_CAPTURE)
    out = tmp_path / "out"
    assert tool.main([str(source), "--out", str(out)]) == 0
    encounters, discoveries = read_csv(out / "encounters.csv"), read_csv(out / "discoveries.csv")
    assert encounters[0] == shipped_header("encounters.csv")
    assert discoveries[0] == shipped_header("discoveries.csv")
    assert encounters[1:] == [["1000", "Edwin Test", "36", "1"], ["1002", "Outside", "", "1"]]
    assert discoveries[1:] == [["18", "Crystal Lake", "1429", "1"], ["19", "", "1429", "1"]]
    assert "2 boss kills and 2 areas" in capsys.readouterr().out


def test_review_files_are_written_empty_for_a_capture_without_encounters_or_areas(tmp_path):
    source = write_saved_variables(tmp_path / "WoWForeverAP.lua", {"zones": {}, "quests": {}})
    out = tmp_path / "out"
    assert tool.main([str(source), "--out", str(out)]) == 0
    assert read_csv(out / "encounters.csv") == [shipped_header("encounters.csv")]
    assert read_csv(out / "discoveries.csv") == [shipped_header("discoveries.csv")]


def test_the_first_capture_that_names_an_encounter_or_area_wins():
    first = {"encounters": {5: {"name": "First", "instanceId": 1, "success": True}},
             "areas": {6: {"name": "First", "uiMapId": 1}}}
    second = {"encounters": {5: {"name": "Second", "instanceId": 2, "success": True}},
              "areas": {6: {"name": "Second", "uiMapId": 2}}}
    assert tool.merge_encounters([first, second])[5] == {"name": "First", "instance": 1}
    assert tool.merge_areas([first, second])[6] == {"name": "First", "zone": 1}


def test_a_wow_folder_is_searched_for_every_accounts_file_and_the_lowest_level_wins(tmp_path):
    first = {"zones": {}, "quests": {783: {"title": "A", "uiMapId": 1429, "level": 6, "faction": "Alliance"}}}
    second = {"zones": {}, "quests": {783: {"title": "A", "uiMapId": 1429, "level": 3, "faction": "Alliance"}}}
    write_saved_variables(tmp_path / "WTF" / "Account" / "ONE" / "SavedVariables" / "WoWForeverAP.lua", first)
    write_saved_variables(tmp_path / "WTF" / "Account" / "TWO" / "SavedVariables" / "WoWForeverAP.lua", second)
    out = tmp_path / "out"
    assert tool.main([str(tmp_path), "--out", str(out)]) == 0
    assert read_csv(out / "quests.csv")[1][3] == "3"


def test_first_capture_names_a_zone(tmp_path):
    first = {"zones": {1429: {"name": "First", "minLevel": 1, "maxLevel": 10}}, "quests": {}}
    second = {"zones": {1429: {"name": "Second", "minLevel": 2, "maxLevel": 9}}, "quests": {}}
    merged = tool.merge_zones([first, second])
    assert merged[1429] == {"name": "First", "min": 1, "max": 10}


def test_warns_about_untitled_quests_and_names_that_would_collide(tmp_path, capsys):
    capture = {"zones": {1429: {"name": "Elwynn Forest"}}, "quests": {
        10: {"title": "Same", "uiMapId": 1429, "level": 1},
        11: {"title": "Same", "uiMapId": 1429, "level": 1},
        12: {"uiMapId": 1429, "level": 1},
    }}
    source = write_saved_variables(tmp_path / "WoWForeverAP.lua", capture)
    assert tool.main([str(source), "--out", str(tmp_path / "out")]) == 0
    err = capsys.readouterr().err
    assert "quest 12 has no title" in err
    assert "quest 11 and 10 both become 'Elwynn Forest: Same'" in err


def test_fails_with_a_message_when_there_is_nothing_to_import(tmp_path, capsys):
    no_capture = tmp_path / "a" / "WoWForeverAP.lua"
    no_capture.parent.mkdir()
    no_capture.write_text("WoWForeverAP_DB = { schema = 1 }\n", encoding="utf-8")
    assert tool.main([str(no_capture), "--out", str(tmp_path / "out")]) == 1
    assert "no capture data" in capsys.readouterr().err
    assert tool.main([str(tmp_path / "empty-folder-does-not-exist"), "--out", str(tmp_path / "out")]) == 1
    assert not (tmp_path / "out" / "zones.csv").exists()


def test_fails_with_a_message_on_a_malformed_file(tmp_path, capsys):
    broken = tmp_path / "WoWForeverAP.lua"
    broken.write_text("WoWForeverAP_DB = { schema = ", encoding="utf-8")
    assert tool.main([str(broken), "--out", str(tmp_path / "out")]) == 1
    assert str(broken) in capsys.readouterr().err


def test_a_faction_that_is_not_a_string_counts_as_unknown():
    capture = {"quests": {
        1: {"title": "A", "faction": {"unexpected": "table"}},
        2: {"title": "B", "faction": 7},
        3: {"title": "C", "faction": "Horde"},
        4: {"title": "D"},
    }}
    quests = tool.merge_quests([capture])
    assert [quests[quest_id]["faction"] for quest_id in (1, 2, 3, 4)] == ["both", "both", "horde", "both"]
