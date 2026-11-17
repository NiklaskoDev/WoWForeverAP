"""Turns the addon's dev capture (/wfap capture on) into review CSVs; nothing is written into the apworld.

    python tools/import_capture.py <SavedVariables file or WoW folder> [more ...] [--out data_capture]

The review files use the shipped CSV schemas (zones.csv, quests.csv) so rows can be copied over after a
check. Guesses are marked in the header comment: faction of zones, is_start, release, and the quest level
(the character's level at turn-in, an upper bound for the quest's requirement).
"""
import argparse
import csv
import sys
from collections.abc import Iterable, Mapping
from pathlib import Path
from typing import Any

from _apworld import ROOT, apworld_module

lua_table = apworld_module("client.lua_table")
savedvars = apworld_module("client.savedvars")

DEFAULT_OUT = ROOT / "data_capture"
ZONE_COLUMNS = ("ui_map_id", "name", "min_level", "max_level", "faction", "is_start", "release")
QUEST_COLUMNS = ("quest_id", "name", "zone_ui_map_id", "req_level", "faction", "release",
                 "prereq_quest_ids", "extra_zone_ids", "name_suffix")
FACTIONS = {"Alliance": "alliance", "Horde": "horde"}
FIRST_RELEASE = 1
REVIEW_NOTE = "REVIEW FILE written by tools/import_capture.py: check every row against the game before copying it."
ZONE_NOTE = "faction is a guess ('both'), is_start is 0 and release is 1 for every row; empty levels were not reported."
QUEST_NOTE = ("req_level is the character's level at turn-in (an upper bound), release is 1, "
              "prerequisites are not known.")


class CaptureError(RuntimeError):
    """The input cannot be imported; the message says why."""


def _table(value: Any) -> dict:
    return value if isinstance(value, dict) else {}


def _number(value: Any) -> int | None:
    return int(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def _text(value: Any) -> str:
    """CSV cells are single-line: collapse any whitespace run, including newlines, to one space."""
    return " ".join(value.split()) if isinstance(value, str) else ""


def read_captures(paths: Iterable[Path]) -> list[dict]:
    """The ``capture`` tables of the given SavedVariables files or WoW folders."""
    captures = []
    for path in paths:
        files = savedvars.find_files(path) if path.is_dir() else [path]
        if not files:
            raise CaptureError(f"{path}: no WoWForeverAP.lua SavedVariables file found")
        for file in files:
            try:
                database = savedvars.read_file(file)
            except (lua_table.LuaParseError, OSError) as error:
                raise CaptureError(f"{file}: {error}") from None
            capture = _table(database.get("capture"))
            if not capture:
                raise CaptureError(f"{file}: no capture data (use /wfap capture on, play, then /reload or log out)")
            captures.append(capture)
    return captures


def merge_zones(captures: Iterable[Mapping]) -> dict[int, dict]:
    """Zone rows by uiMapID; the first capture that names a zone wins."""
    zones: dict[int, dict] = {}
    for capture in captures:
        for ui_map_id, entry in _table(capture.get("zones")).items():
            if _number(ui_map_id) is None or ui_map_id in zones:
                continue
            entry = _table(entry)
            zones[ui_map_id] = {"name": _text(entry.get("name")), "min": _number(entry.get("minLevel")),
                                "max": _number(entry.get("maxLevel"))}
    return zones


def _faction(value: Any) -> str:
    """Faction cell of a quest; anything that is not a known faction name (including a table) means 'both'."""
    return FACTIONS.get(value, "both") if isinstance(value, str) else "both"


def _is_lower(level: int | None, known: int | None) -> bool:
    return level is not None and (known is None or level < known)


def merge_quests(captures: Iterable[Mapping]) -> dict[int, dict]:
    """Quest rows by questID; the lowest level seen wins, as the best estimate of the requirement."""
    quests: dict[int, dict] = {}
    for capture in captures:
        for quest_id, entry in _table(capture.get("quests")).items():
            if _number(quest_id) is None:
                continue
            entry = _table(entry)
            row = {"title": _text(entry.get("title")), "zone": _number(entry.get("uiMapId")),
                   "level": _number(entry.get("level")), "faction": _faction(entry.get("faction"))}
            known = quests.get(quest_id)
            if known is None or _is_lower(row["level"], known["level"]):
                quests[quest_id] = row
    return quests


def _cell(value: object) -> object:
    return "" if value is None else value


def _write_csv(path: Path, comments: list[str], columns: tuple[str, ...], rows: list[tuple]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        for comment in comments:
            handle.write(f"# {comment}\n")
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(columns)
        writer.writerows(rows)


def duplicate_names(zones: Mapping[int, dict], quests: Mapping[int, dict]) -> list[str]:
    """AP location names ('<zone>: <title>') that more than one quest would get; each needs a name_suffix."""
    seen: dict[str, int] = {}
    duplicates = []
    for quest_id in sorted(quests):
        quest = quests[quest_id]
        zone = zones.get(quest["zone"], {}).get("name", "")
        name = f"{zone}: {quest['title']}"
        if name in seen:
            duplicates.append(f"quest {quest_id} and {seen[name]} both become '{name}'")
        seen.setdefault(name, quest_id)
    return duplicates


def _zone_rows(zones: Mapping[int, dict]) -> list[tuple]:
    return [(ui_map_id, zone["name"], _cell(zone["min"]), _cell(zone["max"]), "both", 0, FIRST_RELEASE)
            for ui_map_id, zone in sorted(zones.items())]


def _quest_rows(quests: Mapping[int, dict]) -> list[tuple]:
    return [(quest_id, quest["title"], _cell(quest["zone"]), _cell(quest["level"]), quest["faction"],
             FIRST_RELEASE, "", "", "")
            for quest_id, quest in sorted(quests.items())]


def _build_summary(captures: list[dict]) -> str:
    builds = sorted({f"{_text(c['build'].get('version'))} ({_text(c['build'].get('build'))})"
                     for c in captures if isinstance(c.get("build"), dict)})
    return f"client build: {', '.join(builds) or 'not recorded'}"


def write_review_files(captures: list[dict], out_dir: Path) -> tuple[list[str], list[str]]:
    """Write zones.csv and quests.csv into ``out_dir``. Returns (summary lines, warnings)."""
    zones, quests = merge_zones(captures), merge_quests(captures)
    out_dir.mkdir(parents=True, exist_ok=True)
    _write_csv(out_dir / "zones.csv", [REVIEW_NOTE, ZONE_NOTE], ZONE_COLUMNS, _zone_rows(zones))
    _write_csv(out_dir / "quests.csv", [REVIEW_NOTE, QUEST_NOTE], QUEST_COLUMNS, _quest_rows(quests))
    summary = [f"{len(zones)} zones and {len(quests)} quests written to {out_dir}", _build_summary(captures)]
    warnings = [f"quest {quest_id} has no title (not in the client cache yet)"
                for quest_id, quest in sorted(quests.items()) if not quest["title"]]
    return summary, warnings + duplicate_names(zones, quests)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="+", type=Path, help="SavedVariables file(s) or WoW folder(s)")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output folder (default: data_capture/)")
    args = parser.parse_args(argv)
    try:
        summary, warnings = write_review_files(read_captures(args.paths), args.out)
    except CaptureError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print("\n".join(summary))
    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
