"""Release checks for the release workflow and scripts/release_dry_run.sh (nothing is published or tagged).

    python tools/release_check.py tag <tag>
    python tools/release_check.py verify <version> [--dist DIR]
    python tools/release_check.py notes <version> [--changelog FILE] [--out FILE]

  tag      the tag is vX.Y.Z[-prN] and equals VERSION; prints version=... and prerelease=true|false
  verify   dist/ holds exactly the built files, stamped with <version>; writes dist/SHA256SUMS
  notes    writes the CHANGELOG.md section of <version> to dist/notes.md; a final version needs content
"""
import argparse
import hashlib
import json
import sys
import zipfile
from pathlib import Path

import build
from _apworld import ROOT

CHECKSUMS_NAME = "SHA256SUMS"
NOTES_NAME = "notes.md"
CHUNK_SIZE = 1 << 20


class ReleaseError(RuntimeError):
    """The release must not go ahead; the message says what to fix."""


def version_from_tag(tag: str) -> str:
    if not tag.startswith("v"):
        raise ReleaseError(f"tag '{tag}' must start with 'v'")
    try:
        return build.check_version(tag[1:])
    except build.BuildError as error:
        raise ReleaseError(f"tag '{tag}': {error}") from error


def ensure_tag_matches_version_file(tag: str, version_file: Path = build.VERSION_FILE) -> str:
    version = version_from_tag(tag)
    file_version = build.read_version(version_file)
    if version != file_version:
        raise ReleaseError(f"tag v{version} does not match VERSION {file_version}")
    return version


def is_prerelease(version: str) -> bool:
    return build.PRERELEASE_SUFFIX.search(version) is not None


def expected_artifacts(dist: Path, version: str) -> list[Path]:
    return [dist / f"{build.APWORLD_FOLDER}.apworld", dist / f"WoWForeverAP-{version}.zip"]


def _read_zip_text(path: Path, name: str) -> str:
    with zipfile.ZipFile(path) as archive:
        try:
            return archive.read(name).decode("utf-8")
        except KeyError:
            raise ReleaseError(f"{path.name} has no {name}") from None


def _check_apworld(apworld: Path, version: str) -> None:
    manifest = json.loads(_read_zip_text(apworld, f"{build.APWORLD_FOLDER}/{build.MANIFEST_NAME}"))
    expected = build.world_version(version)
    if manifest.get("world_version") != expected:
        raise ReleaseError(f"{apworld.name} has world_version {manifest.get('world_version')}, expected {expected}")


def _check_addon_zip(addon_zip: Path, version: str) -> None:
    for folder in build.ADDON_FOLDERS:
        toc_name = f"{folder}/{folder}.toc"
        if f"## Version: {version}" not in _read_zip_text(addon_zip, toc_name).splitlines():
            raise ReleaseError(f"{addon_zip.name}: {toc_name} lacks the line '## Version: {version}'")
    with zipfile.ZipFile(addon_zip) as archive:
        for name in archive.namelist():
            if name.endswith(".toc") and build.VERSION_PLACEHOLDER in archive.read(name).decode("utf-8"):
                raise ReleaseError(f"{addon_zip.name}: {name} still contains {build.VERSION_PLACEHOLDER}")


def verify_artifacts(dist: Path, version: str) -> list[Path]:
    expected = expected_artifacts(dist, version)
    for path in expected:
        if not path.is_file():
            raise ReleaseError(f"missing build output {path}")
    allowed = {path.name for path in expected} | {CHECKSUMS_NAME, NOTES_NAME}
    stray = sorted(path.name for path in dist.iterdir() if path.name not in allowed)
    if stray:
        raise ReleaseError(f"unexpected files in {dist}: {', '.join(stray)}")
    _check_apworld(expected[0], version)
    _check_addon_zip(expected[1], version)
    return expected


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(CHUNK_SIZE):
            digest.update(chunk)
    return digest.hexdigest()


def write_checksums(paths: list[Path], out: Path) -> Path:
    """Writes `sha256sum -c` compatible lines (two spaces, basename only)."""
    out.write_text("".join(f"{_sha256(path)}  {path.name}\n" for path in paths), encoding="utf-8")
    return out


def release_notes(changelog_text: str, version: str) -> str:
    """The lines under the '## [version]' heading, up to the next '## [' heading."""
    heading = f"## [{version}]"
    lines: list[str] = []
    inside = False
    for line in changelog_text.splitlines(keepends=True):
        if line.startswith("## ["):
            inside = line.startswith(heading)
        elif inside:
            lines.append(line)
    return "".join(lines)


def ensure_notes(notes: str, version: str) -> None:
    """A final release needs its changelog section (docs/ai/versioning.md, Release step 4)."""
    if not is_prerelease(version) and not notes.strip():
        raise ReleaseError(f"CHANGELOG.md has no '## [{version}]' section with content")


def _run_tag(args: argparse.Namespace) -> None:
    version = ensure_tag_matches_version_file(args.tag, build.VERSION_FILE)
    print(f"version={version}")
    print(f"prerelease={'true' if is_prerelease(version) else 'false'}")


def _run_verify(args: argparse.Namespace) -> None:
    paths = verify_artifacts(args.dist, build.check_version(args.version))
    for path in paths:
        print(f"verified {path}")
    print(f"wrote {write_checksums(paths, args.dist / CHECKSUMS_NAME)}")


def _run_notes(args: argparse.Namespace) -> None:
    version = build.check_version(args.version)
    changelog = args.changelog.read_text(encoding="utf-8") if args.changelog.is_file() else ""
    notes = release_notes(changelog, version)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(notes, encoding="utf-8")
    ensure_notes(notes, version)
    print(f"wrote {args.out}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    tag = commands.add_parser("tag", help="check a tag against VERSION")
    tag.add_argument("tag")
    tag.set_defaults(run=_run_tag)
    verify = commands.add_parser("verify", help="check the built files and write SHA256SUMS")
    verify.add_argument("version")
    verify.add_argument("--dist", type=Path, default=ROOT / "dist")
    verify.set_defaults(run=_run_verify)
    notes = commands.add_parser("notes", help="extract the release notes from the changelog")
    notes.add_argument("version")
    notes.add_argument("--changelog", type=Path, default=ROOT / "CHANGELOG.md")
    notes.add_argument("--out", type=Path, default=ROOT / "dist" / NOTES_NAME)
    notes.set_defaults(run=_run_notes)
    args = parser.parse_args(argv)
    try:
        args.run(args)
    except (ReleaseError, build.BuildError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
