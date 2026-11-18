"""Builds the release artefacts into dist/ (nothing is published or tagged).

    python tools/build.py [--out dist] [--version X.Y.Z[-prN]]

  dist/wow_forever.apworld            the apworld, root folder wow_forever/, world_version stamped
  dist/WoWForeverAP-<version>.zip     the WoWForeverAP and WoWForeverAP_Inbox addon folders, @version@ replaced

The version comes from the VERSION file unless --version is given. The sources are never modified: the
version is stamped into the zip contents only. Zips are byte-for-byte reproducible.
"""
import argparse
import json
import re
import sys
import zipfile
from pathlib import Path

import gen_addon_data
from _apworld import APWORLD_DIR, ROOT

VERSION_FILE = ROOT / "VERSION"
ADDON_DIR = ROOT / "addon"
ADDON_FOLDERS = ("WoWForeverAP", "WoWForeverAP_Inbox")
APWORLD_FOLDER = "wow_forever"
MANIFEST_NAME = "archipelago.json"
VERSION_PLACEHOLDER = "@version@"
VERSION_PATTERN = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-pr[1-9]\d*)?$")
PRERELEASE_SUFFIX = re.compile(r"-pr\d+$")
SKIPPED_DIRS = {"__pycache__"}
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)  # fixed, so equal sources give equal zips

Entry = tuple[str, bytes]  # (path inside the zip, content)


class BuildError(RuntimeError):
    """The build cannot continue; the message says what to fix."""


def read_version(path: Path = VERSION_FILE) -> str:
    return path.read_text(encoding="utf-8").strip()


def check_version(version: str) -> str:
    """The version as given, or BuildError when it is not {major}.{minor}.{hotfix}[-prN]."""
    if not VERSION_PATTERN.fullmatch(version):
        raise BuildError(f"version '{version}' must look like 1.2.3 or 1.2.3-pr1")
    return version


def world_version(version: str) -> str:
    """Archipelago compares world versions as numbers, so the pre-release suffix is left out."""
    return PRERELEASE_SUFFIX.sub("", version)


def _source_files(folder: Path) -> list[Path]:
    return sorted(
        path for path in folder.rglob("*")
        if path.is_file() and not SKIPPED_DIRS.intersection(path.relative_to(folder).parts) and path.suffix != ".pyc"
    )


def _stamp_manifest(content: bytes, version: str) -> bytes:
    manifest = json.loads(content)
    manifest["world_version"] = world_version(version)
    return (json.dumps(manifest, indent=4, ensure_ascii=False) + "\n").encode("utf-8")


def _stamp_toc(path: Path, content: bytes, version: str) -> bytes:
    text = content.decode("utf-8")
    if VERSION_PLACEHOLDER not in text:
        raise BuildError(f"{gen_addon_data.display_path(path)} has no {VERSION_PLACEHOLDER} to replace")
    return text.replace(VERSION_PLACEHOLDER, version).encode("utf-8")


def apworld_entries(version: str) -> list[Entry]:
    entries = []
    for path in _source_files(APWORLD_DIR):
        content = path.read_bytes()
        relative = path.relative_to(APWORLD_DIR)
        if relative == Path(MANIFEST_NAME):
            content = _stamp_manifest(content, version)
        entries.append((f"{APWORLD_FOLDER}/{relative.as_posix()}", content))
    return entries


def addon_entries(version: str) -> list[Entry]:
    entries = []
    for folder in ADDON_FOLDERS:
        for path in _source_files(ADDON_DIR / folder):
            content = path.read_bytes()
            if path.suffix == ".toc":
                content = _stamp_toc(path, content, version)
            entries.append((f"{folder}/{path.relative_to(ADDON_DIR / folder).as_posix()}", content))
    return entries


def write_zip(path: Path, entries: list[Entry]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, content in entries:
            info = zipfile.ZipInfo(name, ZIP_TIMESTAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, content)


def ensure_generated_data_is_current() -> None:
    """Refuse to package an addon whose generated data lags behind the CSVs."""
    try:
        outputs = gen_addon_data.expected_outputs()
    except gen_addon_data.GuideMarkerError as error:
        raise BuildError(str(error)) from None
    stale = [path for path, text in outputs.items()
             if not path.exists() or path.read_text(encoding="utf-8") != text]
    if stale:
        names = ", ".join(gen_addon_data.display_path(path) for path in stale)
        raise BuildError(f"generated files out of date: {names}. Run: python tools/gen_addon_data.py")


def build(out_dir: Path, version: str) -> list[Path]:
    """Write the apworld and the addon zip into ``out_dir``; returns their paths."""
    check_version(version)
    ensure_generated_data_is_current()
    apworld_path = out_dir / f"{APWORLD_FOLDER}.apworld"
    addon_path = out_dir / f"WoWForeverAP-{version}.zip"
    write_zip(apworld_path, apworld_entries(version))
    write_zip(addon_path, addon_entries(version))
    return [apworld_path, addon_path]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, default=ROOT / "dist", help="output folder (default: dist/)")
    parser.add_argument("--version", help="version to stamp (default: the VERSION file)")
    args = parser.parse_args(argv)
    try:
        paths = build(args.out, args.version or read_version())
    except BuildError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    for path in paths:
        print(f"built {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
