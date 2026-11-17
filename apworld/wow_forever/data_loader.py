"""Game data: dataclasses, CSV loading and validation. Pure module: no Archipelago imports.

All rows live in ``data/*.csv``. Lines starting with ``#`` are comments (used to cite sources
and to mark provisional rows). Every validation failure raises ``DataError`` naming file and line.
"""
import csv
import pkgutil
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass, field
from datetime import date
from functools import cache

from . import ids

FACTIONS = ("alliance", "horde", "both")
PROFESSION_KINDS = ("primary", "secondary")
MISC_KIND_CATEGORIES = {"filler": ids.ItemCat.FILLER, "care_package": ids.ItemCat.CARE_PACKAGE}
MISC_KINDS = tuple(MISC_KIND_CATEGORIES)
MATERIAL_SOURCES = ("gather", "drops", "vendor")
LIST_SEPARATOR = ";"
RESERVED_LOCATION_NAMES = frozenset({"Goal"})
INSTANCE_KINDS = ("dungeon", "raid")
PVP_KINDS = ("hk_total", "bg_win")
STANDING_NAMES = {5: "Friendly", 6: "Honored", 7: "Revered", 8: "Exalted"}
REPUTATION_FACTOR = 10  # native id of a reputation location: faction_id * 10 + standing
MAX_SKILL_VALUE = ids.PROFESSION_SKILL_FACTOR - 1
GOAL_LEVEL = 60  # the level that wins the game; here (not in locations.py) so the addon generator needs no Archipelago

DATA_FILES = (
    "releases.csv",
    "zones.csv",
    "quests.csv",
    "professions.csv",
    "profession_tiers.csv",
    "material_brackets.csv",
    "profession_materials.csv",
    "misc_items.csv",
    "instances.csv",
    "encounters.csv",
    "discoveries.csv",
    "reputations.csv",
    "pvp.csv",
)


def level_location_name(level: int) -> str:
    return f"Reach Level {level}"


def profession_location_name(profession_name: str, skill: int) -> str:
    return f"{profession_name} {skill}"


class DataError(ValueError):
    """Raised for any invalid game data; the message names the file and line."""

    def __init__(self, file: str, line: int | None, message: str):
        where = file if line is None else f"{file} line {line}"
        super().__init__(f"{where}: {message}")
        self.file = file
        self.line = line


@dataclass(frozen=True)
class Release:
    id: int
    key: str
    label: str
    date: str


@dataclass(frozen=True)
class Zone:
    ui_map_id: int
    name: str
    min_level: int
    max_level: int
    faction: str
    is_start: bool
    release: int

    @property
    def item_name(self) -> str:
        return f"Zone: {self.name}"


@dataclass(frozen=True)
class Quest:
    quest_id: int
    name: str
    zone_ui_map_id: int
    req_level: int
    faction: str
    release: int
    prereq_quest_ids: tuple[int, ...]
    extra_zone_ids: tuple[int, ...]
    name_suffix: str
    location_name: str  # AP location name, unique across quests
    effective_zones: tuple[int, ...]  # own zone, extra zones and everything the prerequisites need
    effective_level: int  # highest req_level along the prerequisite chain


@dataclass(frozen=True)
class Profession:
    skill_line_id: int
    key: str
    name: str
    kind: str
    release: int

    @property
    def item_name(self) -> str:
        return f"Progressive {self.name}"


@dataclass(frozen=True)
class ProfessionTier:
    tier: int
    name: str
    max_skill: int
    required_level: int
    release: int


@dataclass(frozen=True)
class MaterialBracket:
    max_skill: int
    required_level: int


@dataclass(frozen=True)
class ProfessionMaterial:
    """One way to get the main material of a crafting profession for the skills up to ``max_skill``."""
    crafting_skill_line_id: int
    max_skill: int
    source: str
    gather_skill_line_id: int | None  # only for source "gather"
    gather_skill: int  # gathering skill needed, 0 unless source is "gather"
    required_level: int
    release: int


@dataclass(frozen=True)
class MiscItem:
    native_id: int
    kind: str
    name: str
    release: int

    @property
    def category(self) -> ids.ItemCat:
        return MISC_KIND_CATEGORIES[self.kind]


@dataclass(frozen=True)
class Instance:
    instance_id: int
    name: str
    kind: str
    entrance_ui_map_id: int
    min_level: int
    group_size: int
    faction: str
    release: int


@dataclass(frozen=True)
class Encounter:
    encounter_id: int
    name: str
    instance_id: int
    release: int
    location_name: str  # AP location name: "<instance>: <boss>"


@dataclass(frozen=True)
class Discovery:
    area_id: int
    name: str
    ui_map_id: int
    release: int
    location_name: str  # AP location name: "Discover <zone>: <area>"


@dataclass(frozen=True)
class Reputation:
    faction_id: int
    standing: int
    name: str
    faction_side: str
    required_level: int
    required_ui_map_ids: tuple[int, ...]
    release: int

    @property
    def native_id(self) -> int:
        return self.faction_id * REPUTATION_FACTOR + self.standing

    @property
    def location_name(self) -> str:
        return f"{self.name}: {STANDING_NAMES[self.standing]}"


@dataclass(frozen=True)
class PvpMilestone:
    pvp_id: int
    kind: str
    param: int  # kill count for hk_total, battleground map id for bg_win
    name: str
    required_level: int
    release: int

    @property
    def location_name(self) -> str:
        return f"PvP: {self.name}"


@dataclass(frozen=True)
class GameData:
    releases: tuple[Release, ...]
    zones: tuple[Zone, ...]
    quests: tuple[Quest, ...]
    professions: tuple[Profession, ...]
    profession_tiers: tuple[ProfessionTier, ...]
    material_brackets: tuple[MaterialBracket, ...]
    profession_materials: tuple[ProfessionMaterial, ...]
    misc_items: tuple[MiscItem, ...]
    instances: tuple[Instance, ...] = ()
    encounters: tuple[Encounter, ...] = ()
    discoveries: tuple[Discovery, ...] = ()
    reputations: tuple[Reputation, ...] = ()
    pvp_milestones: tuple[PvpMilestone, ...] = ()
    zones_by_id: dict[int, Zone] = field(default_factory=dict)
    quests_by_id: dict[int, Quest] = field(default_factory=dict)
    professions_by_id: dict[int, Profession] = field(default_factory=dict)
    releases_by_id: dict[int, Release] = field(default_factory=dict)
    instances_by_id: dict[int, Instance] = field(default_factory=dict)
    encounters_by_id: dict[int, Encounter] = field(default_factory=dict)
    discoveries_by_id: dict[int, Discovery] = field(default_factory=dict)
    reputations_by_native: dict[int, Reputation] = field(default_factory=dict)
    pvp_by_id: dict[int, PvpMilestone] = field(default_factory=dict)

    @property
    def care_package(self) -> MiscItem:
        """The single care package item (the parser guarantees exactly one)."""
        return next(item for item in self.misc_items if item.kind == "care_package")


# --- CSV reading -----------------------------------------------------------------------------

Row = tuple[int, dict[str, str]]  # (physical line number, column -> text)


def _read_rows(file: str, text: str, columns: tuple[str, ...]) -> list[Row]:
    header: list[str] | None = None
    rows: list[Row] = []
    for line_no, raw in enumerate(text.splitlines(), start=1):
        if not raw.strip() or raw.startswith("#"):
            continue
        cells = next(csv.reader([raw]))
        if header is None:
            if tuple(cells) != columns:
                raise DataError(file, line_no, f"header must be {','.join(columns)}, got {','.join(cells)}")
            header = cells
            continue
        if len(cells) != len(header):
            raise DataError(file, line_no, f"expected {len(header)} columns, got {len(cells)}")
        rows.append((line_no, dict(zip(header, (c.strip() for c in cells), strict=True))))
    if header is None:
        raise DataError(file, None, "missing header row")
    return rows


def _int(file: str, line: int, row: dict[str, str], column: str) -> int:
    try:
        return int(row[column])
    except ValueError:
        raise DataError(file, line, f"{column} must be an integer, got '{row[column]}'") from None


def _text(file: str, line: int, row: dict[str, str], column: str) -> str:
    if not row[column]:
        raise DataError(file, line, f"{column} must not be empty")
    return row[column]


def _choice(file: str, line: int, row: dict[str, str], column: str, allowed: tuple[str, ...]) -> str:
    if row[column] not in allowed:
        raise DataError(file, line, f"{column} must be one of {', '.join(allowed)}, got '{row[column]}'")
    return row[column]


def _id_list(file: str, line: int, row: dict[str, str], column: str) -> tuple[int, ...]:
    if not row[column]:
        return ()
    try:
        return tuple(int(part) for part in row[column].split(LIST_SEPARATOR))
    except ValueError:
        raise DataError(file, line, f"{column} must be {LIST_SEPARATOR}-separated integers") from None


def _native_in_range(file: str, line: int, build: Callable[[int, int], int], category: int, native: int) -> None:
    try:
        build(category, native)
    except ValueError as error:
        raise DataError(file, line, str(error)) from None


class _Unique:
    """Tracks primary keys of one file and reports the line of the first duplicate."""

    def __init__(self, file: str, what: str):
        self._file = file
        self._what = what
        self._seen: dict[object, int] = {}

    def add(self, line: int, key: object) -> None:
        if key in self._seen:
            raise DataError(self._file, line, f"duplicate {self._what} {key!r} (first seen on line {self._seen[key]})")
        self._seen[key] = line


def _require_release(file: str, line: int, release: int, release_ids: Iterable[int]) -> None:
    if release not in release_ids:
        raise DataError(file, line, f"unknown release {release}")


# --- per-file parsers ------------------------------------------------------------------------

def _parse_releases(text: str) -> tuple[Release, ...]:
    file = "releases.csv"
    unique_id, unique_key = _Unique(file, "id"), _Unique(file, "key")
    releases = []
    for line, row in _read_rows(file, text, ("id", "key", "label", "date")):
        release = Release(_int(file, line, row, "id"), _text(file, line, row, "key"),
                          _text(file, line, row, "label"), _text(file, line, row, "date"))
        unique_id.add(line, release.id)
        unique_key.add(line, release.key)
        try:
            date.fromisoformat(release.date)
        except ValueError:
            raise DataError(file, line, f"date must be YYYY-MM-DD, got '{release.date}'") from None
        releases.append(release)
    if not releases:
        raise DataError(file, None, "at least one release is required")
    return tuple(releases)


def _parse_zones(text: str, release_ids: set[int]) -> tuple[Zone, ...]:
    file = "zones.csv"
    unique = _Unique(file, "ui_map_id")
    zones = []
    columns = ("ui_map_id", "name", "min_level", "max_level", "faction", "is_start", "release")
    for line, row in _read_rows(file, text, columns):
        zone = Zone(
            _int(file, line, row, "ui_map_id"), _text(file, line, row, "name"),
            _int(file, line, row, "min_level"), _int(file, line, row, "max_level"),
            _choice(file, line, row, "faction", FACTIONS),
            _choice(file, line, row, "is_start", ("0", "1")) == "1",
            _int(file, line, row, "release"),
        )
        unique.add(line, zone.ui_map_id)
        if zone.min_level > zone.max_level:
            raise DataError(file, line, f"min_level {zone.min_level} is above max_level {zone.max_level}")
        _require_release(file, line, zone.release, release_ids)
        _native_in_range(file, line, ids.item_id, ids.ItemCat.ZONE, zone.ui_map_id)
        zones.append(zone)
    return tuple(zones)


def _parse_professions(text: str, release_ids: set[int]) -> tuple[Profession, ...]:
    file = "professions.csv"
    unique_id, unique_key = _Unique(file, "skill_line_id"), _Unique(file, "key")
    professions = []
    for line, row in _read_rows(file, text, ("skill_line_id", "key", "name", "kind", "release")):
        profession = Profession(
            _int(file, line, row, "skill_line_id"), _text(file, line, row, "key"),
            _text(file, line, row, "name"), _choice(file, line, row, "kind", PROFESSION_KINDS),
            _int(file, line, row, "release"),
        )
        unique_id.add(line, profession.skill_line_id)
        unique_key.add(line, profession.key)
        _require_release(file, line, profession.release, release_ids)
        _native_in_range(file, line, ids.item_id, ids.ItemCat.PROFESSION_TIER, profession.skill_line_id)
        _native_in_range(file, line, ids.location_id, ids.LocCat.PROFESSION_SKILL,
                         profession.skill_line_id * ids.PROFESSION_SKILL_FACTOR + MAX_SKILL_VALUE)
        professions.append(profession)
    return tuple(professions)


def _parse_tiers(text: str, release_ids: set[int]) -> tuple[ProfessionTier, ...]:
    file = "profession_tiers.csv"
    unique = _Unique(file, "tier")
    tiers = []
    for line, row in _read_rows(file, text, ("tier", "name", "max_skill", "required_level", "release")):
        tier = ProfessionTier(
            _int(file, line, row, "tier"), _text(file, line, row, "name"), _int(file, line, row, "max_skill"),
            _int(file, line, row, "required_level"), _int(file, line, row, "release"),
        )
        unique.add(line, tier.tier)
        _require_release(file, line, tier.release, release_ids)
        if not 0 < tier.max_skill <= MAX_SKILL_VALUE:
            raise DataError(file, line, f"max_skill must be 1..{MAX_SKILL_VALUE}, got {tier.max_skill}")
        tiers.append(tier)
    tiers.sort(key=lambda t: t.tier)
    for expected, tier in enumerate(tiers, start=1):
        if tier.tier != expected:
            raise DataError(file, None, f"tiers must be numbered 1..n without gaps, missing {expected}")
        if expected > 1 and tier.max_skill <= tiers[expected - 2].max_skill:
            raise DataError(file, None, f"tier {tier.tier} max_skill must exceed tier {tier.tier - 1}")
    if not tiers:
        raise DataError(file, None, "at least one tier is required")
    return tuple(tiers)


def _parse_brackets(text: str, tiers: tuple[ProfessionTier, ...]) -> tuple[MaterialBracket, ...]:
    file = "material_brackets.csv"
    unique = _Unique(file, "max_skill")
    brackets = []
    for line, row in _read_rows(file, text, ("max_skill", "required_level")):
        bracket = MaterialBracket(_int(file, line, row, "max_skill"), _int(file, line, row, "required_level"))
        unique.add(line, bracket.max_skill)
        brackets.append(bracket)
    brackets.sort(key=lambda b: b.max_skill)
    top_skill = max(tier.max_skill for tier in tiers)
    largest = brackets[-1].max_skill if brackets else 0
    if largest < top_skill:
        raise DataError(file, None, f"brackets must cover every skill up to {top_skill} (the highest profession "
                                    f"tier), but the largest max_skill is {largest}")
    return tuple(brackets)


def _parse_misc_items(text: str, release_ids: set[int]) -> tuple[MiscItem, ...]:
    file = "misc_items.csv"
    unique = _Unique(file, "native_id")
    items = []
    for line, row in _read_rows(file, text, ("native_id", "kind", "name", "release")):
        item = MiscItem(_int(file, line, row, "native_id"), _choice(file, line, row, "kind", MISC_KINDS),
                        _text(file, line, row, "name"), _int(file, line, row, "release"))
        unique.add(line, (item.kind, item.native_id))  # kinds sit in different item categories
        _require_release(file, line, item.release, release_ids)
        _native_in_range(file, line, ids.item_id, item.category, item.native_id)
        items.append(item)
    if not any(item.kind == "filler" for item in items):
        raise DataError(file, None, "at least one filler item is required")
    care_packages = [item for item in items if item.kind == "care_package"]
    if len(care_packages) != 1:
        raise DataError(file, None, f"exactly one care_package item is required, found {len(care_packages)}")
    return tuple(items)


def _parse_profession_materials(text: str, release_ids: set[int], professions: Mapping[int, Profession],
                                brackets: tuple[MaterialBracket, ...],
                                tiers: tuple[ProfessionTier, ...]) -> tuple[ProfessionMaterial, ...]:
    file = "profession_materials.csv"
    columns = ("crafting_skill_line_id", "max_skill", "source", "gather_skill_line_id", "gather_skill",
               "required_level", "release")
    bracket_limits = {bracket.max_skill for bracket in brackets}
    top_skill = max(tier.max_skill for tier in tiers)
    unique = _Unique(file, "material source")
    materials = []
    for line, row in _read_rows(file, text, columns):
        source = _choice(file, line, row, "source", MATERIAL_SOURCES)
        gather_line = _int(file, line, row, "gather_skill_line_id") if row["gather_skill_line_id"] else None
        material = ProfessionMaterial(
            _int(file, line, row, "crafting_skill_line_id"), _int(file, line, row, "max_skill"), source,
            gather_line, _int(file, line, row, "gather_skill"), _int(file, line, row, "required_level"),
            _int(file, line, row, "release"))
        unique.add(line, (material.crafting_skill_line_id, material.max_skill, source, gather_line))
        _require_release(file, line, material.release, release_ids)
        for column, skill_line_id in (("crafting_skill_line_id", material.crafting_skill_line_id),
                                      ("gather_skill_line_id", gather_line)):
            if skill_line_id is not None and skill_line_id not in professions:
                raise DataError(file, line, f"{column} {skill_line_id} is not in professions.csv")
        if material.max_skill not in bracket_limits:
            raise DataError(file, line, f"max_skill {material.max_skill} is not a max_skill of material_brackets.csv")
        if source == "gather":
            if gather_line is None:
                raise DataError(file, line, "a gather source needs a gather_skill_line_id")
            if gather_line == material.crafting_skill_line_id:
                raise DataError(file, line, "a profession cannot gather its own material")
            if not 0 < material.gather_skill <= top_skill:
                raise DataError(file, line, f"gather_skill must be 1..{top_skill}, got {material.gather_skill}")
        elif gather_line is not None or material.gather_skill != 0:
            raise DataError(file, line, f"{source} sources must have an empty gather_skill_line_id and gather_skill 0")
        materials.append(material)
    return tuple(materials)


# --- quests ----------------------------------------------------------------------------------

@dataclass(frozen=True)
class _RawQuest:
    line: int
    quest_id: int
    name: str
    zone_ui_map_id: int
    req_level: int
    faction: str
    release: int
    prereq_quest_ids: tuple[int, ...]
    extra_zone_ids: tuple[int, ...]
    name_suffix: str


def _parse_raw_quests(text: str, zones: Mapping[int, Zone], release_ids: set[int]) -> dict[int, _RawQuest]:
    file = "quests.csv"
    columns = ("quest_id", "name", "zone_ui_map_id", "req_level", "faction", "release",
               "prereq_quest_ids", "extra_zone_ids", "name_suffix")
    raw: dict[int, _RawQuest] = {}
    unique = _Unique(file, "quest_id")
    for line, row in _read_rows(file, text, columns):
        quest = _RawQuest(
            line, _int(file, line, row, "quest_id"), _text(file, line, row, "name"),
            _int(file, line, row, "zone_ui_map_id"), _int(file, line, row, "req_level"),
            _choice(file, line, row, "faction", FACTIONS), _int(file, line, row, "release"),
            _id_list(file, line, row, "prereq_quest_ids"), _id_list(file, line, row, "extra_zone_ids"),
            row["name_suffix"],
        )
        unique.add(line, quest.quest_id)
        _require_release(file, line, quest.release, release_ids)
        _native_in_range(file, line, ids.location_id, ids.LocCat.QUEST, quest.quest_id)
        for zone_id in (quest.zone_ui_map_id, *quest.extra_zone_ids):
            if zone_id not in zones:
                raise DataError(file, line, f"unknown zone {zone_id}")
        raw[quest.quest_id] = quest
    for quest in raw.values():
        for prereq in quest.prereq_quest_ids:
            if prereq not in raw:
                raise DataError(file, quest.line, f"unknown prerequisite quest {prereq}")
    return raw


def _check_acyclic(raw: Mapping[int, _RawQuest]) -> None:
    done: set[int] = set()

    def visit(quest_id: int, path: tuple[int, ...]) -> None:
        if quest_id in path:
            cycle = " -> ".join(str(q) for q in (*path[path.index(quest_id):], quest_id))
            raise DataError("quests.csv", raw[quest_id].line, f"prerequisite cycle {cycle}")
        if quest_id in done:
            return
        for prereq in raw[quest_id].prereq_quest_ids:
            visit(prereq, (*path, quest_id))
        done.add(quest_id)

    for quest_id in raw:
        visit(quest_id, ())


def _build_quests(raw: Mapping[int, _RawQuest], zones: Mapping[int, Zone]) -> tuple[Quest, ...]:
    _check_acyclic(raw)
    derived: dict[int, tuple[frozenset[int], int]] = {}

    def derive(quest_id: int) -> tuple[frozenset[int], int]:
        if quest_id not in derived:
            quest = raw[quest_id]
            needed = {quest.zone_ui_map_id, *quest.extra_zone_ids}
            level = quest.req_level
            for prereq in quest.prereq_quest_ids:
                prereq_zones, prereq_level = derive(prereq)
                needed |= prereq_zones
                level = max(level, prereq_level)
            derived[quest_id] = (frozenset(needed), level)
        return derived[quest_id]

    quests = []
    names: dict[str, int] = {}
    for quest in raw.values():
        needed, level = derive(quest.quest_id)
        suffix = f" {quest.name_suffix}" if quest.name_suffix else ""
        location_name = f"{zones[quest.zone_ui_map_id].name}: {quest.name}{suffix}"
        if location_name in RESERVED_LOCATION_NAMES or location_name in names:
            raise DataError("quests.csv", quest.line, f"duplicate AP location name '{location_name}': set name_suffix")
        names[location_name] = quest.line
        quests.append(Quest(
            quest.quest_id, quest.name, quest.zone_ui_map_id, quest.req_level, quest.faction, quest.release,
            quest.prereq_quest_ids, quest.extra_zone_ids, quest.name_suffix, location_name,
            tuple(sorted(needed)), level,
        ))
    return tuple(quests)


# --- extra check categories (plan 004) -------------------------------------------------------

def _parse_instances(text: str, zones: Mapping[int, Zone], release_ids: set[int]) -> tuple[Instance, ...]:
    file = "instances.csv"
    columns = ("instance_id", "name", "kind", "entrance_ui_map_id", "min_level", "group_size", "faction", "release")
    unique = _Unique(file, "instance_id")
    instances = []
    for line, row in _read_rows(file, text, columns):
        instance = Instance(
            _int(file, line, row, "instance_id"), _text(file, line, row, "name"),
            _choice(file, line, row, "kind", INSTANCE_KINDS), _int(file, line, row, "entrance_ui_map_id"),
            _int(file, line, row, "min_level"), _int(file, line, row, "group_size"),
            _choice(file, line, row, "faction", FACTIONS), _int(file, line, row, "release"))
        unique.add(line, instance.instance_id)
        _require_release(file, line, instance.release, release_ids)
        if instance.entrance_ui_map_id not in zones:
            raise DataError(file, line, f"unknown zone {instance.entrance_ui_map_id}")
        if not 1 <= instance.min_level <= GOAL_LEVEL:
            raise DataError(file, line, f"min_level must be 1..{GOAL_LEVEL}, got {instance.min_level}")
        if instance.group_size < 1:
            raise DataError(file, line, f"group_size must be at least 1, got {instance.group_size}")
        instances.append(instance)
    return tuple(instances)


def _parse_encounters(text: str, instances: Mapping[int, Instance], release_ids: set[int]) -> tuple[Encounter, ...]:
    file = "encounters.csv"
    unique = _Unique(file, "encounter_id")
    encounters = []
    for line, row in _read_rows(file, text, ("encounter_id", "name", "instance_id", "release")):
        encounter_id, instance_id = _int(file, line, row, "encounter_id"), _int(file, line, row, "instance_id")
        name, release = _text(file, line, row, "name"), _int(file, line, row, "release")
        unique.add(line, encounter_id)
        _require_release(file, line, release, release_ids)
        _native_in_range(file, line, ids.location_id, ids.LocCat.BOSS, encounter_id)
        if instance_id not in instances:
            raise DataError(file, line, f"unknown instance {instance_id}")
        encounters.append(Encounter(encounter_id, name, instance_id, release,
                                    f"{instances[instance_id].name}: {name}"))
    return tuple(encounters)


def _parse_discoveries(text: str, zones: Mapping[int, Zone], release_ids: set[int]) -> tuple[Discovery, ...]:
    file = "discoveries.csv"
    unique = _Unique(file, "area_id")
    discoveries = []
    for line, row in _read_rows(file, text, ("area_id", "name", "ui_map_id", "release")):
        area_id, name = _int(file, line, row, "area_id"), _text(file, line, row, "name")
        ui_map_id, release = _int(file, line, row, "ui_map_id"), _int(file, line, row, "release")
        unique.add(line, area_id)
        _require_release(file, line, release, release_ids)
        _native_in_range(file, line, ids.location_id, ids.LocCat.AREA_DISCOVERY, area_id)
        if ui_map_id not in zones:
            raise DataError(file, line, f"unknown zone {ui_map_id}")
        discoveries.append(Discovery(area_id, name, ui_map_id, release, f"Discover {zones[ui_map_id].name}: {name}"))
    return tuple(discoveries)


def _parse_reputations(text: str, zones: Mapping[int, Zone], release_ids: set[int]) -> tuple[Reputation, ...]:
    file = "reputations.csv"
    columns = ("faction_id", "standing", "name", "faction_side", "required_level", "required_ui_map_ids", "release")
    unique = _Unique(file, "faction_id/standing")
    reputations = []
    for line, row in _read_rows(file, text, columns):
        reputation = Reputation(
            _int(file, line, row, "faction_id"), _int(file, line, row, "standing"), _text(file, line, row, "name"),
            _choice(file, line, row, "faction_side", FACTIONS), _int(file, line, row, "required_level"),
            _id_list(file, line, row, "required_ui_map_ids"), _int(file, line, row, "release"))
        unique.add(line, (reputation.faction_id, reputation.standing))
        _require_release(file, line, reputation.release, release_ids)
        if reputation.standing not in STANDING_NAMES:
            allowed = ", ".join(str(standing) for standing in STANDING_NAMES)
            raise DataError(file, line, f"standing must be one of {allowed}, got {reputation.standing}")
        if not 1 <= reputation.required_level <= GOAL_LEVEL:
            raise DataError(file, line, f"required_level must be 1..{GOAL_LEVEL}, got {reputation.required_level}")
        for zone_id in reputation.required_ui_map_ids:
            if zone_id not in zones:
                raise DataError(file, line, f"unknown zone {zone_id}")
        _native_in_range(file, line, ids.location_id, ids.LocCat.REPUTATION, reputation.native_id)
        reputations.append(reputation)
    return tuple(reputations)


def _parse_pvp(text: str, release_ids: set[int]) -> tuple[PvpMilestone, ...]:
    file = "pvp.csv"
    unique = _Unique(file, "pvp_id")
    milestones = []
    for line, row in _read_rows(file, text, ("pvp_id", "kind", "param", "name", "required_level", "release")):
        milestone = PvpMilestone(
            _int(file, line, row, "pvp_id"), _choice(file, line, row, "kind", PVP_KINDS),
            _int(file, line, row, "param"), _text(file, line, row, "name"),
            _int(file, line, row, "required_level"), _int(file, line, row, "release"))
        unique.add(line, milestone.pvp_id)
        _require_release(file, line, milestone.release, release_ids)
        _native_in_range(file, line, ids.location_id, ids.LocCat.PVP, milestone.pvp_id)
        if milestone.param < 1:
            raise DataError(file, line, f"param must be at least 1, got {milestone.param}")
        if not 1 <= milestone.required_level <= GOAL_LEVEL:
            raise DataError(file, line, f"required_level must be 1..{GOAL_LEVEL}, got {milestone.required_level}")
        milestones.append(milestone)
    return tuple(milestones)


def _level_and_profession_names(professions: Iterable[Profession],
                                tiers: Iterable[ProfessionTier]) -> list[tuple[str, str]]:
    """The (file, name) pairs of the level and profession-skill locations, which have no CSV rows of their own."""
    top_skill = max((tier.max_skill for tier in tiers), default=0)
    names = [("the level locations", level_location_name(level)) for level in range(2, GOAL_LEVEL + 1)]
    names += [("professions.csv", profession_location_name(profession.name, skill))
              for profession in professions for skill in range(1, top_skill + 1)]
    return names


def _check_location_names_unique(data_names: Iterable[tuple[str, str]]) -> None:
    """AP location names must be unique across every category: (file, name) pairs in file order."""
    seen: dict[str, str] = {}
    for file, name in data_names:
        if name in RESERVED_LOCATION_NAMES or name in seen:
            other = seen.get(name, "the reserved names")
            raise DataError(file, None, f"duplicate AP location name '{name}' (also in {other})")
        seen[name] = file


def _check_item_names_unique(zones: tuple[Zone, ...], professions: tuple[Profession, ...],
                             misc_items: tuple[MiscItem, ...]) -> None:
    seen: set[str] = set()
    for name in [z.item_name for z in zones] + [p.item_name for p in professions] + [m.name for m in misc_items]:
        if name in seen:
            raise DataError("zones.csv/professions.csv/misc_items.csv", None, f"duplicate AP item name '{name}'")
        seen.add(name)


# --- public API ------------------------------------------------------------------------------

def parse_game_data(files: Mapping[str, str]) -> GameData:
    """Parse and validate CSV texts keyed by file name (see ``DATA_FILES``); raises ``DataError``."""
    releases = _parse_releases(files["releases.csv"])
    release_ids = {release.id for release in releases}
    zones = _parse_zones(files["zones.csv"], release_ids)
    zones_by_id = {zone.ui_map_id: zone for zone in zones}
    professions = _parse_professions(files["professions.csv"], release_ids)
    tiers = _parse_tiers(files["profession_tiers.csv"], release_ids)
    brackets = _parse_brackets(files["material_brackets.csv"], tiers)
    professions_by_id = {profession.skill_line_id: profession for profession in professions}
    materials = _parse_profession_materials(files["profession_materials.csv"], release_ids, professions_by_id,
                                            brackets, tiers)
    misc_items = _parse_misc_items(files["misc_items.csv"], release_ids)
    quests = _build_quests(_parse_raw_quests(files["quests.csv"], zones_by_id, release_ids), zones_by_id)
    _check_item_names_unique(zones, professions, misc_items)
    instances = _parse_instances(files["instances.csv"], zones_by_id, release_ids)
    instances_by_id = {instance.instance_id: instance for instance in instances}
    encounters = _parse_encounters(files["encounters.csv"], instances_by_id, release_ids)
    discoveries = _parse_discoveries(files["discoveries.csv"], zones_by_id, release_ids)
    reputations = _parse_reputations(files["reputations.csv"], zones_by_id, release_ids)
    pvp_milestones = _parse_pvp(files["pvp.csv"], release_ids)
    _check_location_names_unique(
        _level_and_profession_names(professions, tiers)
        + [("quests.csv", quest.location_name) for quest in quests]
        + [("encounters.csv", encounter.location_name) for encounter in encounters]
        + [("discoveries.csv", discovery.location_name) for discovery in discoveries]
        + [("reputations.csv", reputation.location_name) for reputation in reputations]
        + [("pvp.csv", milestone.location_name) for milestone in pvp_milestones])
    return GameData(
        releases, zones, quests, professions, tiers, brackets, materials, misc_items,
        instances, encounters, discoveries, reputations, pvp_milestones,
        zones_by_id=zones_by_id,
        quests_by_id={quest.quest_id: quest for quest in quests},
        professions_by_id=professions_by_id,
        releases_by_id={release.id: release for release in releases},
        instances_by_id=instances_by_id,
        encounters_by_id={encounter.encounter_id: encounter for encounter in encounters},
        discoveries_by_id={discovery.area_id: discovery for discovery in discoveries},
        reputations_by_native={reputation.native_id: reputation for reputation in reputations},
        pvp_by_id={milestone.pvp_id: milestone for milestone in pvp_milestones},
    )


def read_shipped_files() -> dict[str, str]:
    """Return the shipped CSV texts keyed by file name."""
    texts = {}
    for name in DATA_FILES:
        raw = pkgutil.get_data(__package__, f"data/{name}")
        if raw is None:
            raise DataError(name, None, "shipped data file not found")
        texts[name] = raw.decode("utf-8")
    return texts


@cache
def load_game_data() -> GameData:
    """Load, validate and cache the shipped game data."""
    return parse_game_data(read_shipped_files())
