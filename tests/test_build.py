import json
import zipfile

import build
import gen_addon_data
import pytest
from worlds.wow_forever.data_loader import load_game_data, parse_game_data

VERSION = "1.2.3"


@pytest.fixture(scope="module")
def built(tmp_path_factory):
    out = tmp_path_factory.mktemp("dist")
    apworld, addon = build.build(out, VERSION)
    return apworld, addon


def names(path):
    with zipfile.ZipFile(path) as archive:
        return archive.namelist()


def read(path, name):
    with zipfile.ZipFile(path) as archive:
        return archive.read(name)


def test_output_names(built):
    apworld, addon = built
    assert apworld.name == "wow_forever.apworld"
    assert addon.name == f"WoWForeverAP-{VERSION}.zip"


def test_apworld_has_a_single_root_folder_with_the_world_files(built):
    entries = names(built[0])
    assert all(entry.startswith("wow_forever/") for entry in entries)
    for expected in ("wow_forever/__init__.py", "wow_forever/archipelago.json", "wow_forever/data/zones.csv",
                     "wow_forever/data/quests.csv", "wow_forever/client/wow_client.py",
                     "wow_forever/client/lua_table.py"):
        assert expected in entries
    assert not [entry for entry in entries if "__pycache__" in entry or entry.endswith(".pyc")]


def test_apworld_carries_the_third_party_notices_with_the_full_mit_text(built):
    packed = read(built[0], "wow_forever/THIRD_PARTY_NOTICES.md").decode("utf-8")
    assert packed == (build.APWORLD_DIR / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
    assert "Copyright (c) 2026 AllTheThings WoW Addon" in packed
    assert "Permission is hereby granted, free of charge" in packed
    assert 'THE SOFTWARE IS PROVIDED "AS IS"' in packed


def test_apworld_data_files_are_the_shipped_data(built):
    from worlds.wow_forever.data_loader import DATA_FILES

    texts = {name: read(built[0], f"wow_forever/data/{name}").decode("utf-8") for name in DATA_FILES}
    packed = parse_game_data(texts)
    assert packed.zones == load_game_data().zones
    assert packed.quests == load_game_data().quests


def test_world_version_is_stamped_into_the_manifest_but_not_into_the_source(built):
    manifest = json.loads(read(built[0], "wow_forever/archipelago.json"))
    assert manifest["world_version"] == VERSION
    assert manifest["game"] == "World of Warcraft Forever"
    source = json.loads((build.APWORLD_DIR / "archipelago.json").read_text(encoding="utf-8"))
    assert source["world_version"] == "0.0.0"


def test_addon_zip_holds_both_addon_folders_and_no_specs(built):
    entries = names(built[1])
    for expected in ("WoWForeverAP/WoWForeverAP.toc", "WoWForeverAP/Main.lua", "WoWForeverAP/Data/Generated.lua",
                     "WoWForeverAP/Locales/deDE.lua", "WoWForeverAP_Inbox/WoWForeverAP_Inbox.toc",
                     "WoWForeverAP_Inbox/Inbox.lua"):
        assert expected in entries
    assert all(entry.startswith(("WoWForeverAP/", "WoWForeverAP_Inbox/")) for entry in entries)
    assert not [entry for entry in entries if "spec" in entry]


def test_version_placeholder_is_replaced_in_both_tocs_and_nowhere_left(built):
    addon = built[1]
    for toc in ("WoWForeverAP/WoWForeverAP.toc", "WoWForeverAP_Inbox/WoWForeverAP_Inbox.toc"):
        text = read(addon, toc).decode("utf-8")
        assert f"## Version: {VERSION}\n" in text
        assert "## Interface: 16001\n" in text
    for entry in names(addon):
        assert b"@version@" not in read(addon, entry), entry


def test_the_source_tocs_keep_the_placeholder():
    for toc in ("WoWForeverAP/WoWForeverAP.toc", "WoWForeverAP_Inbox/WoWForeverAP_Inbox.toc"):
        assert "@version@" in (build.ADDON_DIR / toc).read_text(encoding="utf-8")


def test_a_prerelease_keeps_its_suffix_in_the_names_and_tocs_but_not_in_world_version(tmp_path):
    apworld, addon = build.build(tmp_path, "2.0.0-pr3")
    assert addon.name == "WoWForeverAP-2.0.0-pr3.zip"
    assert "## Version: 2.0.0-pr3" in read(addon, "WoWForeverAP/WoWForeverAP.toc").decode("utf-8")
    assert json.loads(read(apworld, "wow_forever/archipelago.json"))["world_version"] == "2.0.0"


def test_zips_are_reproducible(tmp_path):
    first = build.build(tmp_path / "one", VERSION)
    second = build.build(tmp_path / "two", VERSION)
    for left, right in zip(first, second, strict=True):
        assert left.read_bytes() == right.read_bytes()


@pytest.mark.parametrize("version", ["", "1.2", "v1.2.3", "01.2.3", "1.2.3-pr", "1.2.3-pr0", "1.2.3-rc1", "1.2.3.4"])
def test_invalid_versions_are_refused_and_nothing_is_written(tmp_path, version):
    with pytest.raises(build.BuildError, match="must look like"):
        build.build(tmp_path, version)
    assert not list(tmp_path.iterdir())


def test_main_uses_the_version_file_by_default(tmp_path, capsys):
    assert build.main(["--out", str(tmp_path)]) == 0
    version = build.read_version()
    assert (tmp_path / f"WoWForeverAP-{version}.zip").exists()
    assert "built" in capsys.readouterr().out


def test_main_reports_a_bad_version(tmp_path, capsys):
    assert build.main(["--out", str(tmp_path), "--version", "nope"]) == 1
    assert "must look like" in capsys.readouterr().err


def test_stale_generated_data_stops_the_build(tmp_path, monkeypatch):
    stale = tmp_path / "Generated.lua"
    stale.write_text("-- old\n", encoding="utf-8")
    monkeypatch.setattr(gen_addon_data, "GENERATED_FILE", stale)
    with pytest.raises(build.BuildError, match="out of date"):
        build.build(tmp_path / "dist", VERSION)
    assert not (tmp_path / "dist").exists()


def test_a_guide_without_markers_stops_the_build_naming_the_file(tmp_path, monkeypatch):
    guide = tmp_path / "guide.md"
    guide.write_text("# No markers\n", encoding="utf-8")
    monkeypatch.setattr(gen_addon_data, "GUIDE_FILE", guide)
    with pytest.raises(build.BuildError, match="guide.md"):
        build.build(tmp_path / "dist", VERSION)
    assert not (tmp_path / "dist").exists()


def test_a_toc_without_the_placeholder_is_an_error(tmp_path, monkeypatch):
    fake_addon = tmp_path / "addon"
    (fake_addon / "WoWForeverAP").mkdir(parents=True)
    (fake_addon / "WoWForeverAP_Inbox").mkdir()
    (fake_addon / "WoWForeverAP" / "WoWForeverAP.toc").write_text("## Version: 1.0.0\n", encoding="utf-8")
    monkeypatch.setattr(build, "ADDON_DIR", fake_addon)
    with pytest.raises(build.BuildError, match="@version@"):
        build.addon_entries(VERSION)
