"""Generates apworld/wow_forever/data/quests.csv from the Forever database of AllTheThings (dev-time only).

    bash scripts/fetch_att.sh
    python tools/import_att.py [--att-root DIR] [--out FILE] [--report FILE] [--check]

ATT (github.com/ATTWoWAddon/AllTheThings, MIT) is cloned at the commit in tools/att_version.txt. Its Lua is parsed as
data by tools/att_lua.py, never executed. Every quest that is left out is listed with its reason in the review report
(data_capture/att_report.txt), which also cross-checks zones.csv levels and the profession tiers against ATT. Neither
check changes any CSV other than quests.csv. See docs/plans/005-att-quest-import.md for the rules.
"""
import argparse
import csv
import io
import re
import statistics
import sys
from collections import Counter, defaultdict
from collections.abc import Iterable, Iterator, Mapping
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Any

import att_lua
from _apworld import ROOT, apworld_module
from _csvout import QUEST_COLUMNS, render_csv

data_loader = apworld_module("data_loader")

ATT_VERSION_FILE = ROOT / "tools" / "att_version.txt"
DEFAULT_ATT_ROOT = ROOT / ".att" / "AllTheThings" / ".contrib" / ".db" / "forever"
DEFAULT_OUT = ROOT / "apworld" / "wow_forever" / "data" / "quests.csv"
DEFAULT_REPORT = ROOT / "data_capture" / "att_report.txt"

FIRST_RELEASE = 1
MAX_LEVEL = 60
MAX_NAME_LENGTH = 100
LEVEL_TOLERANCE = 2  # zones.csv levels are flagged when they differ from ATT's quest levels by more than this

# Race identifiers of ATT's races constants. A new race must be added here deliberately (it decides the faction).
ALLIANCE_RACES = frozenset({"HUMAN", "DWARF", "NIGHTELF", "GNOME", "SKYBORNE_ALLIANCE"})
HORDE_RACES = frozenset({"ORC", "UNDEAD", "TAUREN", "TROLL", "SKYBORNE_HORDE"})
FACTION_ONLY_NAMES = {"ALLIANCE_ONLY": "alliance", "HORDE_ONLY": "horde"}
# Quests that ATT stores once with one id per faction: {allianceQuestData = q(..), hordeQuestData = q(..), shared...}
FACTION_DATA_KEYS = {"allianceQuestData": "alliance", "hordeQuestData": "horde"}

REPEATABLE_FIELDS = ("repeatable", "isDaily", "isWeekly", "isMonthly", "isYearly")
DROPPED_EDGE_REASONS = frozenset({"repeatable", "breadcrumb"})
RANK_NAMES = ("Apprentice", "Journeyman", "Expert", "Artisan", "Master", "Grand Master")

_MAP_LINE = re.compile(r"^\s*([A-Z0-9_]+)\s*=\s*(\d+)\s*[;,]", re.MULTILINE)
_TIMELINE_MARKER = re.compile(r"^(ADDED|REMOVED|CREATED|DELETED)_(\d+)_(\d+)_(\d+)$")
_WAGO_BUILD = re.compile(r"\.(\d+\.\d+\.\d+\.\d+)\.csv$")
_SKILL_RANK_LINE = re.compile(
    r"^\s*\[(\d+)\]\s*=\s*(\d+),?\s*--\s*(.+?)\s*\((" + "|".join(RANK_NAMES) + r")\)\s*$")
_SHA = re.compile(r"[0-9a-f]{40}")

MapRef = int | str  # a map id, or the name of a map this tool cannot resolve to an id


class AttImportError(RuntimeError):
    """The ATT data cannot be imported; the message says why."""


@dataclass(frozen=True)
class RawAttQuest:
    quest_id: int
    name: str | None
    path: str
    line: int
    zone_id: MapRef | None  # map of the enclosing maproot (a name when ATT gives no id); None outside any maproot
    local_maps: frozenset[MapRef]
    fields: Mapping[str, Any]
    forced_faction: str | None = None


@dataclass(frozen=True)
class AttQuestRow:
    quest_id: int
    name: str
    zone_id: int
    req_level: int
    faction: str
    prereq_ids: tuple[int, ...]
    extra_zone_ids: tuple[int, ...]
    att_level: int | None  # the level ATT gives, None when it has none (req_level is then the zone's minimum)
    name_suffix: str = ""


@dataclass(frozen=True)
class Exclusion:
    quest_id: int
    name: str
    reason: str
    zone_id: MapRef | None = None

    @property
    def category(self) -> str:
        return self.reason.split(":", 1)[0]


@dataclass
class Context:
    zones: Mapping[int, Any]  # ui_map_id -> data_loader.Zone
    parents: Mapping[int, int]  # UiMap id -> parent id
    maps: Mapping[str, int]  # ATT MAP constants
    nyi_ids: frozenset[int]
    version: tuple[int, int, int]
    seen: set[int] = field(default_factory=set)
    unresolved: Counter = field(default_factory=Counter)  # map ref -> number of quests that use it


@dataclass
class ImportResult:
    rows: list[AttQuestRow]
    exclusions: list[Exclusion]
    unresolved: Counter
    sha: str
    build: str


# --- reading ATT inputs ---------------------------------------------------------------------------------------

def load_maps(text: str) -> dict[str, int]:
    """``NAME = id;`` lines of ATT's maps.lua; one name with two values is an error."""
    maps: dict[str, int] = {}
    for name, value in _MAP_LINE.findall(text):
        if maps.setdefault(name, int(value)) != int(value):
            raise AttImportError(f"maps.lua: MAP.{name} has two different values")
    return maps


def load_ui_map_parents(text: str) -> dict[int, int]:
    return {int(row["ID"]): int(row["ParentUiMapID"]) for row in csv.DictReader(io.StringIO(text))}


def _read_csv_column(text: str, column: str) -> set[int]:
    return {int(row[column]) for row in csv.DictReader(io.StringIO(text)) if row[column].isdigit()}


def wago_build(att_root: Path) -> str:
    """The one build the .wago exports are for (``1.60.1.70959``); several builds are an error."""
    builds = {match.group(1) for path in (att_root / ".config" / ".wago").glob("*.csv")
              if (match := _WAGO_BUILD.search(path.name))}
    if len(builds) != 1:
        raise AttImportError(f".config/.wago holds {len(builds)} builds ({', '.join(sorted(builds)) or 'none'}), need 1")
    return builds.pop()


def build_version(build: str) -> tuple[int, int, int]:
    major, minor, patch = (int(part) for part in build.split(".")[:3])
    return major, minor, patch


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8-sig")
    except OSError as error:
        raise AttImportError(f"cannot read {path}: {error.strerror or error}") from None


def read_nyi_ids(text: str) -> frozenset[int]:
    return frozenset(call.args[0] for node in att_lua.parse_chunk(text, ".nyi/quests.lua")
                     for call in att_lua.iter_calls(node, "q") if call.args and isinstance(call.args[0], int))


# --- collecting quests ----------------------------------------------------------------------------------------

def _map_ref(value: Any, maps: Mapping[str, int]) -> MapRef | None:
    """The map a value names: an id, ``MAP.NAME`` or a bare legacy name (the same id as ``MAP.NAME``)."""
    if isinstance(value, int) and not isinstance(value, bool):
        return value
    if isinstance(value, att_lua.AttName):
        name = value.dotted
        if name.startswith("MAP."):
            short = name[len("MAP."):]
            if short not in maps:
                raise AttImportError(f"unknown map constant {name}")
            return maps[short]
        return maps.get(name, name)
    return None


def _leading_maps(args: list, maps: Mapping[str, int]) -> list[MapRef]:
    """Map arguments before the table in ``maproot(continent, zone, {...})`` / ``m(zone, {...})``."""
    found = []
    for arg in args:
        if isinstance(arg, (dict, list)):
            break
        ref = _map_ref(arg, maps)
        if ref is not None:
            found.append(ref)
    return found


def _quest_calls(node: Any, forced: str | None = None, shared: Mapping | None = None) -> Iterator[tuple]:
    """``(q call, forced faction, shared fields)`` for every quest below ``node``."""
    if isinstance(node, att_lua.AttCall):
        if node.name == "q" and node.args and isinstance(node.args[0], int):
            yield node, forced, shared
        children: Iterable = node.args
    elif isinstance(node, dict):
        if FACTION_DATA_KEYS.keys() & node.keys():
            common = {key: value for key, value in node.items() if key not in FACTION_DATA_KEYS}
            for key, faction in FACTION_DATA_KEYS.items():
                yield from _quest_calls(node.get(key), faction, common)
            yield from _quest_calls(list(common.values()))
            return
        children = node.values()
    elif isinstance(node, att_lua.AttAssign):
        children = node.values
    elif isinstance(node, list):
        children = node
    else:
        return
    for child in children:
        yield from _quest_calls(child)


def _raw_quest(call: att_lua.AttCall, forced: str | None, shared: Mapping | None, path: str,
               zone_id: int | None, local_maps: frozenset[MapRef]) -> RawAttQuest:
    own = call.args[1] if len(call.args) > 1 and isinstance(call.args[1], dict) else {}
    name = " ".join((call.comment or "").split())[:MAX_NAME_LENGTH] or None
    return RawAttQuest(call.args[0], name, path, call.line, zone_id, local_maps, {**(shared or {}), **own}, forced)


def collect_quests(files: Iterable[Path], maps: Mapping[str, int], root: Path | None = None) -> list[RawAttQuest]:
    """Every quest of the given zone files, in file order. Quests outside a ``maproot`` get ``zone_id`` None."""
    quests: list[RawAttQuest] = []
    for file in files:
        shown = str(file.relative_to(root)) if root else str(file)
        try:
            nodes = att_lua.parse_file(file)
        except att_lua.AttParseError as error:
            raise AttImportError(str(error)) from None
        found_maproot = False
        for node in nodes:
            is_maproot = isinstance(node, att_lua.AttCall) and node.name == "maproot"
            found_maproot = found_maproot or is_maproot
            zone_id: MapRef | None = None
            local_maps: frozenset[MapRef] = frozenset()
            if is_maproot:
                leading = _leading_maps(node.args, maps)
                if not leading:
                    raise AttImportError(f"{shown}: line {node.line}: maproot names no known map")
                zone_id = leading[-1]
                local_maps = frozenset(
                    ref for sub in att_lua.iter_calls(node, "m") for ref in _leading_maps(sub.args, maps))
            for call, forced, shared in _quest_calls(node):
                quests.append(_raw_quest(call, forced, shared, shown, zone_id, local_maps))
        if not found_maproot and any(quest.path == shown for quest in quests):
            raise AttImportError(f"{shown}: quests but no maproot call")
    return quests


# --- classifying quests ---------------------------------------------------------------------------------------

def resolve_zone(map_ref: MapRef, root_zone: int | None, local_maps: frozenset[MapRef], ctx: Context) -> int | None:
    """The zones.csv zone a map belongs to, or None (a city, dungeon, continent or unknown map)."""
    if map_ref in ctx.zones:
        return map_ref
    if map_ref in local_maps:
        return root_zone
    if isinstance(map_ref, int):
        seen = set()
        current = ctx.parents.get(map_ref)
        while current and current not in seen:
            if current in ctx.zones:
                return current
            seen.add(current)
            current = ctx.parents.get(current)
    return None


def _quest_map_refs(fields: Mapping[str, Any], maps: Mapping[str, int]) -> list[MapRef]:
    """Maps of the quest-level ``coord``, ``coords`` and ``maps`` fields (objectives in ``groups`` are not read)."""
    refs: list[MapRef] = []

    def add_coord(coord: Any) -> None:
        if isinstance(coord, list) and len(coord) >= 3:
            ref = _map_ref(coord[2], maps)
            if ref is not None:
                refs.append(ref)

    add_coord(fields.get("coord"))
    coords = fields.get("coords")
    if isinstance(coords, list):
        if coords and not isinstance(coords[0], list):
            add_coord(coords)  # a single flat coordinate
        else:
            for coord in coords:
                add_coord(coord)
    listed = fields.get("maps")
    if isinstance(listed, list):
        refs.extend(ref for ref in (_map_ref(item, maps) for item in listed) if ref is not None)
    return refs


def _race_faction(races: Any) -> str:
    """alliance / horde, or ``restricted`` when only some races of a faction (or both factions' odd mix) can do it."""
    if isinstance(races, att_lua.AttName) and races.dotted in FACTION_ONLY_NAMES:
        return FACTION_ONLY_NAMES[races.dotted]
    if isinstance(races, att_lua.AttName):
        races = [races]  # a single race written without braces
    if isinstance(races, att_lua.AttCall):
        return "restricted"  # exclude(...) narrows a set
    if isinstance(races, list) and all(isinstance(race, att_lua.AttName) for race in races):
        names = {race.dotted for race in races}
        unknown = names - ALLIANCE_RACES - HORDE_RACES
        if unknown:
            raise AttImportError(f"unknown race identifier {', '.join(sorted(unknown))}: add it to import_att.py")
        if names == ALLIANCE_RACES:
            return "alliance"
        if names == HORDE_RACES:
            return "horde"
        return "restricted"
    return "restricted"


def timeline_exclusion(markers: Any, version: tuple[int, int, int]) -> str | None:
    """``future``, ``created`` or ``removed`` when the timeline puts the quest out of the game at ``version``."""
    found = []
    for index, marker in enumerate(markers if isinstance(markers, list) else []):
        if isinstance(marker, att_lua.AttName):
            match = _TIMELINE_MARKER.match(marker.dotted.rsplit(".", 1)[-1])
            if match:
                found.append(((int(match[2]), int(match[3]), int(match[4])), index, match[1]))
    if not found:
        return None
    applying = sorted(item for item in found if item[0] <= version)
    if not applying:
        return "future"
    state = applying[-1][2]
    return {"ADDED": None, "CREATED": "created", "REMOVED": "removed", "DELETED": "removed"}[state]


def _level(fields: Mapping[str, Any]) -> int | None:
    value = fields.get("lvl")
    if isinstance(value, att_lua.AttCall):
        value = next((arg for arg in value.args if isinstance(arg, int)), None)
    if isinstance(value, int) and not isinstance(value, bool):
        return min(max(value, 1), MAX_LEVEL)
    return None


def _first_reason(raw: RawAttQuest, ctx: Context) -> str | None:
    """Why a quest is not wanted, checked in the order of the plan; None when it is kept (zone aside)."""
    fields = raw.fields
    if raw.quest_id in ctx.nyi_ids:
        return "nyi"
    if "u" in fields:
        return "unobtainable"
    timeline = timeline_exclusion(fields.get("timeline"), ctx.version)
    if timeline:
        return timeline
    if any(fields.get(key) for key in REPEATABLE_FIELDS):
        return "repeatable"
    if fields.get("isBreadcrumb"):
        return "breadcrumb"
    if "classes" in fields:
        return "class-restricted"
    return None


def _quest_faction(raw: RawAttQuest) -> str | None:
    """The faction of an unrestricted quest, or None when races narrow it below a faction."""
    if "races" in raw.fields:
        faction = _race_faction(raw.fields["races"])
        return None if faction == "restricted" else faction
    return raw.forced_faction or "both"


def classify(raw: RawAttQuest, ctx: Context) -> AttQuestRow | Exclusion:
    """The row a quest becomes, or the reason it is left out. Prerequisites are resolved later."""
    def excluded(reason: str) -> Exclusion:
        return Exclusion(raw.quest_id, raw.name or "", reason, raw.zone_id)

    duplicate = raw.quest_id in ctx.seen
    ctx.seen.add(raw.quest_id)
    if raw.zone_id is None:
        return excluded("outside-maproot")
    zone = ctx.zones.get(raw.zone_id)
    if zone is None:
        return excluded("zone-not-in-data")
    if not raw.name:
        return excluded("no-name")
    reason = _first_reason(raw, ctx)
    if reason:
        return excluded(reason)
    faction = _quest_faction(raw)
    if faction is None:
        return excluded("race-restricted")
    fields = raw.fields
    if "requireSkill" in fields:
        return excluded("profession")
    if "minReputation" in fields or "maxReputation" in fields:
        return excluded("reputation")
    if "lockCriteria" in fields or "altQuests" in fields:
        return excluded("lockable")
    extra: set[int] = set()
    for ref in _quest_map_refs(fields, ctx.maps):
        resolved = resolve_zone(ref, raw.zone_id, raw.local_maps, ctx)
        if resolved is None:
            ctx.unresolved[ref] += 1
            return excluded(f"map-outside-zones:{ref}")
        extra.add(resolved)
    if zone.faction not in ("both", faction) and faction != "both":
        return excluded("faction-mismatch")
    if raw.quest_id >= data_loader.ids.CATEGORY_SIZE:
        return excluded("id-out-of-range")
    if duplicate:
        return excluded("duplicate")
    att_level = _level(fields)
    prereqs = {value for key in ("sourceQuest", "sourceQuests")
               for value in (fields[key] if isinstance(fields.get(key), list) else [fields.get(key)])
               if isinstance(value, int) and value != raw.quest_id}
    return AttQuestRow(raw.quest_id, raw.name, raw.zone_id, att_level or zone.min_level, faction,
                       tuple(sorted(prereqs)), tuple(sorted(extra - {raw.zone_id})), att_level)


def resolve_prereqs(rows: list[AttQuestRow], exclusions: list[Exclusion]) -> tuple[list[AttQuestRow], list[Exclusion]]:
    """Drop quests whose prerequisites are gone, until nothing changes.

    A prerequisite that is repeatable or a breadcrumb only loses its edge. A faction-less quest whose prerequisite
    belongs to one faction becomes that faction's quest; two different factions exclude the quest.
    """
    kept = {row.quest_id: row for row in rows}
    reasons = {item.quest_id: item.category for item in exclusions if item.reason != "duplicate"}
    added: list[Exclusion] = []
    changed = True
    while changed:
        changed = False
        for quest_id in sorted(kept):
            row = kept[quest_id]
            prereqs, faction, problem = [], row.faction, None
            for prereq in row.prereq_ids:
                if prereq in kept:
                    prereq_faction = kept[prereq].faction
                    if prereq_faction != "both":
                        if faction == "both":
                            faction = prereq_faction
                        elif faction != prereq_faction:
                            problem = problem or f"prereq-faction:{prereq}"
                    prereqs.append(prereq)
                elif reasons.get(prereq) not in DROPPED_EDGE_REASONS:
                    problem = problem or f"prereq-excluded:{prereq}"
            if problem:
                del kept[quest_id]
                reasons[quest_id] = problem.split(":", 1)[0]
                added.append(Exclusion(quest_id, row.name, problem, row.zone_id))
                changed = True
            elif tuple(prereqs) != row.prereq_ids or faction != row.faction:
                kept[quest_id] = replace(row, prereq_ids=tuple(prereqs), faction=faction)
                changed = True
    return [kept[quest_id] for quest_id in sorted(kept)], added


def assign_suffixes(rows: list[AttQuestRow], zones: Mapping[int, Any]) -> list[AttQuestRow]:
    """``(#id)`` for every quest that shares its AP location name (``zone: name``) with another."""
    names = Counter((zones[row.zone_id].name, row.name) for row in rows)
    return [replace(row, name_suffix=f"(#{row.quest_id})") if names[(zones[row.zone_id].name, row.name)] > 1 else row
            for row in rows]


def build_rows(raws: list[RawAttQuest], ctx: Context) -> tuple[list[AttQuestRow], list[Exclusion]]:
    classified = [classify(raw, ctx) for raw in raws]
    rows = [item for item in classified if isinstance(item, AttQuestRow)]
    exclusions = [item for item in classified if isinstance(item, Exclusion)]
    rows, dropped = resolve_prereqs(rows, exclusions)
    return assign_suffixes(rows, ctx.zones), exclusions + dropped


# --- output ---------------------------------------------------------------------------------------------------

def render_quests_csv(rows: Iterable[AttQuestRow], zones: Mapping[int, Any], sha: str, build: str) -> str:
    """The text of quests.csv: zones in zones.csv order, then quest id."""
    zone_order = {zone_id: index for index, zone_id in enumerate(zones)}
    ordered = sorted(rows, key=lambda row: (zone_order[row.zone_id], row.quest_id))
    comments = [
        "GENERATED by tools/import_att.py - do not edit; re-run the import instead.",
        f"Source: AllTheThings (github.com/ATTWoWAddon/AllTheThings, MIT), .contrib/.db/forever, commit {sha}, build {build}.",
        "req_level is ATT's lvl (minimum level); release is 1 for every row. "
        "Exclusions are listed in data_capture/att_report.txt.",
    ]
    return render_csv(comments, QUEST_COLUMNS, [
        (row.quest_id, row.name, row.zone_id, row.req_level, row.faction, FIRST_RELEASE,
         ";".join(map(str, row.prereq_ids)), ";".join(map(str, row.extra_zone_ids)), row.name_suffix)
        for row in ordered])


def _zone_level_lines(rows: list[AttQuestRow], zones: Mapping[int, Any]) -> list[str]:
    levels: dict[int, list[int]] = defaultdict(list)
    for row in rows:
        if row.att_level is not None:
            levels[row.zone_id].append(row.att_level)
    lines = ["zone                   zones.csv  ATT quest lvl (min / median / max)  flag"]
    for zone_id, zone in zones.items():
        found = levels.get(zone_id)
        if not found:
            lines.append(f"{zone.name:<22} {zone.min_level:>3}-{zone.max_level:<3}    no quest levels")
            continue
        low, high = min(found), max(found)
        flagged = abs(zone.min_level - low) > LEVEL_TOLERANCE or zone.max_level < high
        lines.append(f"{zone.name:<22} {zone.min_level:>3}-{zone.max_level:<3}    {low:>3} / {statistics.median(found):>5g} / "
                     f"{high:>3}{'':<14}{'FLAG' if flagged else ''}")
    return lines


def parse_skill_ranks(text: str) -> dict[str, dict[str, int]]:
    """Profession name -> rank name -> the lowest skill at which ATT lists the rank as learnable."""
    ranks: dict[str, dict[str, int]] = defaultdict(dict)
    for line in text.splitlines():
        match = _SKILL_RANK_LINE.match(line)
        if match:
            known = ranks[match[3]]
            known[match[4]] = min(int(match[2]), known.get(match[4], int(match[2])))
    return ranks


def _profession_lines(game_data: Any, skill_lines: set[int], ranks: Mapping[str, Mapping[str, int]]) -> list[str]:
    lines = []
    tiers = game_data.profession_tiers
    by_name = {name.lower(): value for name, value in ranks.items()}
    for profession in game_data.professions:
        flags = []
        if profession.skill_line_id not in skill_lines:
            flags.append(f"skill line {profession.skill_line_id} is not in ATT's SkillLineAbility")
        found = by_name.get(profession.name.lower())
        if found is None:
            flags.append("no rank data in ATT's Skill Level Requirements")
        else:
            att_order = sorted(found, key=lambda rank: RANK_NAMES.index(rank))
            if att_order != [tier.name for tier in tiers]:
                flags.append(f"ATT ranks {att_order}, profession_tiers.csv {[tier.name for tier in tiers]}")
            for before, after in zip(tiers, tiers[1:], strict=False):
                learned = found.get(after.name)
                if learned is not None and learned > before.max_skill:
                    flags.append(f"{after.name} is learnable at {learned}, above {before.name} max_skill {before.max_skill}")
        lines.append(f"{profession.name:<16} " + ("; ".join(flags) if flags else "ok"))
    return lines


def build_report(result: ImportResult, game_data: Any, skill_lines: set[int], ranks: Mapping[str, Mapping[str, int]],
                 raw_count: int) -> str:
    zones = game_data.zones_by_id
    lines = [f"ATT import report: commit {result.sha}, build {result.build}",
             f"{raw_count} quests read, {len(result.rows)} kept, {len(result.exclusions)} excluded.", "",
             "1. Exclusions by reason"]
    by_reason: dict[str, list[Exclusion]] = defaultdict(list)
    for item in result.exclusions:
        by_reason[item.category].append(item)
    for reason, items in sorted(by_reason.items(), key=lambda pair: (-len(pair[1]), pair[0])):
        lines.append(f"  {reason}: {len(items)}")
    for reason, items in sorted(by_reason.items()):
        lines += ["", f"  [{reason}]"]
        lines += [f"    {item.quest_id}  {item.name}" + (f"  ({item.reason})" if ":" in item.reason else "")
                  for item in sorted(items, key=lambda item: item.quest_id)]
    lines += ["", "2. Unresolved maps (map id or name: quests using it)"]
    lines += [f"  {ref}: {count}" for ref, count in sorted(result.unresolved.items(), key=lambda pair: (-pair[1], str(pair[0])))]
    lines += ["", "3. Kept quests per zone and faction"]
    per_zone: dict[int, Counter] = defaultdict(Counter)
    for row in result.rows:
        per_zone[row.zone_id][row.faction] += 1
    for zone_id, zone in zones.items():
        counts = per_zone.get(zone_id, Counter())
        lines.append(f"  {zone.name:<22} alliance {counts['alliance']:>4}  horde {counts['horde']:>4}  both {counts['both']:>4}")
    defaulted = [row for row in result.rows if row.att_level is None]
    lines += ["", f"  {len(defaulted)} kept quests have no lvl in ATT and use the zone's min_level: "
              + ", ".join(str(row.quest_id) for row in defaulted)]
    lines += ["", "4. Zone level cross-check (flag: min differs by more than "
              f"{LEVEL_TOLERANCE}, or max_level is below the highest quest lvl)"]
    lines += ["  " + line for line in _zone_level_lines(result.rows, zones)]
    lines += ["", "5. Profession cross-check"]
    lines += ["  " + line for line in _profession_lines(game_data, skill_lines, ranks)]
    lines += ["  ATT has no character-level requirement for profession tiers and no material data: "
              "required_level and the material tables stay design values."]
    return "\n".join(lines) + "\n"


# --- driver ---------------------------------------------------------------------------------------------------

def pinned_sha() -> str:
    return _read(ATT_VERSION_FILE).strip()


def check_checkout(sha: str, checkout: Path = ROOT / ".att" / "AllTheThings") -> None:
    head = checkout / ".git" / "HEAD"
    current = _read(head).strip() if head.is_file() else ""
    if current != sha:
        raise AttImportError(f"the ATT checkout is at '{current or 'unknown'}', tools/att_version.txt pins {sha}: "
                             "run scripts/fetch_att.sh")


def zone_files(att_root: Path) -> list[Path]:
    return sorted((att_root / "zones").glob("**/*.lua"), key=lambda path: path.relative_to(att_root).as_posix())


def shipped_data_files() -> dict[str, str]:
    """The shipped CSV texts with an empty quests.csv: the quests are what is being generated."""
    files = data_loader.read_shipped_files()
    files["quests.csv"] = render_csv([], QUEST_COLUMNS, [])
    return files


def run_import(att_root: Path, data_files: dict[str, str], sha: str) -> tuple[ImportResult, Any, int]:
    """Read ATT, build and validate the quest rows. Returns the result, the game data and the number of quests read."""
    if not att_root.is_dir():
        raise AttImportError(f"{att_root} not found: run scripts/fetch_att.sh")
    config = att_root / ".config"
    game_data = data_loader.parse_game_data(data_files)
    build = wago_build(att_root)
    maps = load_maps(_read(config / "constants" / "maps.lua"))
    ctx = Context(game_data.zones_by_id, load_ui_map_parents(_read(config / ".wago" / f"UiMap.{build}.csv")), maps,
                  read_nyi_ids(_read(att_root / ".nyi" / "quests.lua")), build_version(build))
    raws = collect_quests(zone_files(att_root), maps, att_root)
    rows, exclusions = build_rows(raws, ctx)
    result = ImportResult(rows, exclusions, ctx.unresolved, sha, build)
    try:
        data_loader.parse_game_data({**data_files, "quests.csv": render_quests_csv(rows, game_data.zones_by_id, sha, build)})
    except data_loader.DataError as error:
        raise AttImportError(f"the generated quests fail validation: {error}") from None
    return result, game_data, len(raws)


def _read_report_inputs(att_root: Path, build: str) -> tuple[set[int], dict[str, dict[str, int]]]:
    skill_lines = _read_csv_column(_read(att_root / ".config" / ".wago" / f"SkillLineAbility.{build}.csv"), "SkillLine")
    ranks = parse_skill_ranks(_read(att_root / ".config" / "exports" / "Skill Level Requirements.lua"))
    return skill_lines, ranks


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--att-root", type=Path, help=f"ATT's forever database (default {DEFAULT_ATT_ROOT.relative_to(ROOT)})")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="quests.csv to write or, with --check, to compare")
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT, help="review report to write")
    parser.add_argument("--check", action="store_true", help="write nothing; exit 1 if --out differs from the import")
    args = parser.parse_args(argv)
    try:
        sha = pinned_sha()
        if not _SHA.fullmatch(sha):
            raise AttImportError(f"{ATT_VERSION_FILE} must hold a 40-character commit hash")
        if args.att_root is None:
            check_checkout(sha)
        att_root = args.att_root or DEFAULT_ATT_ROOT
        result, game_data, raw_count = run_import(att_root, shipped_data_files(), sha)
        text = render_quests_csv(result.rows, game_data.zones_by_id, sha, result.build)
        if args.check:
            current = args.out.read_text(encoding="utf-8") if args.out.is_file() else None
            if current != text:
                print(f"error: {args.out} differs from the ATT import; run tools/import_att.py", file=sys.stderr)
                return 1
            print(f"{args.out} matches the ATT import")
            return 0
        skill_lines, ranks = _read_report_inputs(att_root, result.build)
        report = build_report(result, game_data, skill_lines, ranks, raw_count)
    except (AttImportError, data_loader.DataError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    args.out.write_text(text, encoding="utf-8", newline="")
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(report, encoding="utf-8")
    print(f"{len(result.rows)} quests written to {args.out}, {len(result.exclusions)} excluded; report in {args.report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
