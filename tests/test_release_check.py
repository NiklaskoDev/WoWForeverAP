import hashlib
import json
import shutil
import zipfile

import build
import pytest
import release_check
from release_check import ReleaseError

VERSION = "1.2.3"


@pytest.fixture(scope="module")
def built(tmp_path_factory):
    out = tmp_path_factory.mktemp("dist")
    build.build(out, VERSION)
    return out


@pytest.fixture
def dist(built, tmp_path):
    """A private copy of the built files that a test may tamper with."""
    copy = tmp_path / "dist"
    shutil.copytree(built, copy)
    return copy


def rewrite_zip(path, change):
    """Replaces the zip with the result of ``change(name, content) -> content``."""
    with zipfile.ZipFile(path) as archive:
        entries = [(name, change(name, archive.read(name))) for name in archive.namelist()]
    build.write_zip(path, entries)


def test_version_from_tag():
    assert release_check.version_from_tag("v1.2.3") == "1.2.3"
    assert release_check.version_from_tag("v1.2.3-pr2") == "1.2.3-pr2"


@pytest.mark.parametrize("tag", ["1.2.3", "v1.2", "v01.2.3", "v1.2.3-pr0", "v1.2.3-rc1"])
def test_version_from_tag_rejects_malformed_tags(tag):
    with pytest.raises(ReleaseError):
        release_check.version_from_tag(tag)


def test_tag_must_equal_the_version_file(tmp_path):
    version_file = tmp_path / "VERSION"
    version_file.write_text("1.2.3\n", encoding="utf-8")
    assert release_check.ensure_tag_matches_version_file("v1.2.3", version_file) == "1.2.3"
    with pytest.raises(ReleaseError, match=r"v1\.2\.4.*1\.2\.3"):
        release_check.ensure_tag_matches_version_file("v1.2.4", version_file)
    with pytest.raises(ReleaseError):
        release_check.ensure_tag_matches_version_file("v1.2.3-pr1", version_file)


def test_is_prerelease():
    assert not release_check.is_prerelease("1.2.3")
    assert release_check.is_prerelease("1.2.3-pr1")


def test_verify_returns_apworld_then_addon_zip(built):
    paths = release_check.verify_artifacts(built, VERSION)
    assert [path.name for path in paths] == ["wow_forever.apworld", f"WoWForeverAP-{VERSION}.zip"]


def test_verify_fails_when_built_for_another_version(built):
    with pytest.raises(ReleaseError, match="missing"):
        release_check.verify_artifacts(built, "1.2.4")


def test_verify_fails_on_a_wrong_manifest_version(dist):
    def change(name, content):
        if not name.endswith("archipelago.json"):
            return content
        return json.dumps({**json.loads(content), "world_version": "0.0.0"}).encode()

    rewrite_zip(dist / "wow_forever.apworld", change)
    with pytest.raises(ReleaseError, match="world_version"):
        release_check.verify_artifacts(dist, VERSION)


def test_verify_fails_on_an_unstamped_toc(dist):
    def change(name, content):
        if name != "WoWForeverAP_Inbox/WoWForeverAP_Inbox.toc":
            return content
        return content.replace(VERSION.encode(), build.VERSION_PLACEHOLDER.encode())

    rewrite_zip(dist / f"WoWForeverAP-{VERSION}.zip", change)
    with pytest.raises(ReleaseError, match="Version"):
        release_check.verify_artifacts(dist, VERSION)


def test_verify_fails_when_a_toc_keeps_the_placeholder_elsewhere(dist):
    def change(name, content):
        if name != "WoWForeverAP/WoWForeverAP.toc":
            return content
        return content + f"## Notes: {build.VERSION_PLACEHOLDER}\n".encode()

    rewrite_zip(dist / f"WoWForeverAP-{VERSION}.zip", change)
    with pytest.raises(ReleaseError, match=build.VERSION_PLACEHOLDER):
        release_check.verify_artifacts(dist, VERSION)


def test_verify_rejects_stray_files_but_allows_checksums_and_notes(dist):
    (dist / "SHA256SUMS").write_text("", encoding="utf-8")
    (dist / "notes.md").write_text("", encoding="utf-8")
    release_check.verify_artifacts(dist, VERSION)
    (dist / "stray.txt").write_text("x", encoding="utf-8")
    with pytest.raises(ReleaseError, match="stray.txt"):
        release_check.verify_artifacts(dist, VERSION)


def test_prerelease_build_verifies_with_numeric_world_version(tmp_path):
    build.build(tmp_path, "1.2.3-pr1")
    release_check.verify_artifacts(tmp_path, "1.2.3-pr1")
    with zipfile.ZipFile(tmp_path / "wow_forever.apworld") as archive:
        assert json.loads(archive.read("wow_forever/archipelago.json"))["world_version"] == "1.2.3"


def test_write_checksums_uses_the_sha256sum_format(built, tmp_path):
    paths = release_check.expected_artifacts(built, VERSION)
    out = release_check.write_checksums(paths, tmp_path / "SHA256SUMS")
    expected = "".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in paths)
    assert out.read_text(encoding="utf-8") == expected
    names = [line.split("  ")[1] for line in expected.splitlines()]
    assert names == ["wow_forever.apworld", f"WoWForeverAP-{VERSION}.zip"]


CHANGELOG = """# Changelog

## [Unreleased]
### Added
- Next thing.

## [1.2.3-pr1] - 2026-01-01
- Pre-release thing.

## [1.2.3] - 2026-02-01
### Fixed
- Final thing.

## [1.2.2] - 2026-01-01
- Old thing.
"""


def test_release_notes_returns_the_middle_section():
    notes = release_check.release_notes(CHANGELOG, "1.2.3")
    assert "Final thing." in notes
    assert "Old thing." not in notes
    assert "## [" not in notes


def test_release_notes_runs_to_the_end_of_the_file():
    assert release_check.release_notes(CHANGELOG, "1.2.2").strip() == "- Old thing."


def test_release_notes_does_not_mix_up_prerelease_sections():
    notes = release_check.release_notes(CHANGELOG, "1.2.3")
    assert "Pre-release thing." not in notes
    assert release_check.release_notes(CHANGELOG, "1.2.3-pr1").strip() == "- Pre-release thing."


def test_release_notes_of_an_absent_version_are_empty():
    assert release_check.release_notes(CHANGELOG, "9.9.9") == ""


def test_ensure_notes():
    with pytest.raises(ReleaseError, match="1.2.3"):
        release_check.ensure_notes("  \n", "1.2.3")
    release_check.ensure_notes("- Something.\n", "1.2.3")
    release_check.ensure_notes("", "1.2.3-pr1")


def test_main_tag_prints_version_and_prerelease(tmp_path, monkeypatch, capsys):
    version_file = tmp_path / "VERSION"
    version_file.write_text("1.2.3-pr1\n", encoding="utf-8")
    monkeypatch.setattr(build, "VERSION_FILE", version_file)
    assert release_check.main(["tag", "v1.2.3-pr1"]) == 0
    assert capsys.readouterr().out.splitlines() == ["version=1.2.3-pr1", "prerelease=true"]


def test_main_tag_mismatch_returns_one(tmp_path, monkeypatch, capsys):
    version_file = tmp_path / "VERSION"
    version_file.write_text("1.2.3\n", encoding="utf-8")
    monkeypatch.setattr(build, "VERSION_FILE", version_file)
    assert release_check.main(["tag", "v1.2.4"]) == 1
    assert capsys.readouterr().err.startswith("error:")


def test_main_verify_writes_checksums(dist, capsys):
    assert release_check.main(["verify", VERSION, "--dist", str(dist)]) == 0
    assert (dist / "SHA256SUMS").read_text(encoding="utf-8").count("\n") == 2
    assert "verified" in capsys.readouterr().out


def test_main_notes_writes_the_file_then_fails_for_a_final_version_without_section(tmp_path, capsys):
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(CHANGELOG, encoding="utf-8")
    out = tmp_path / "out" / "notes.md"
    assert release_check.main(["notes", "1.2.3", "--changelog", str(changelog), "--out", str(out)]) == 0
    assert "Final thing." in out.read_text(encoding="utf-8")
    assert release_check.main(["notes", "9.9.9", "--changelog", str(changelog), "--out", str(out)]) == 1
    assert out.read_text(encoding="utf-8") == ""
    assert capsys.readouterr().err.startswith("error:")
    assert release_check.main(["notes", "9.9.9-pr1", "--changelog", str(changelog), "--out", str(out)]) == 0
