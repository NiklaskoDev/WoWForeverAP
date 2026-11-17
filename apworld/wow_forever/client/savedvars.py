"""Reads the addon's SavedVariables files (game -> client direction). Pure apart from file reads."""
import logging
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .lua_table import LuaParseError, parse_assignments

LOGGER = logging.getLogger(__name__)
SAVED_VARIABLES_GLOB = "WTF/Account/*/SavedVariables/WoWForeverAP.lua"
DB_VARIABLE = "WoWForeverAP_DB"
CHECK_KIND = "check"


def find_files(wow_path: Path) -> list[Path]:
    """SavedVariables files of every account under the game folder, in a stable order."""
    return sorted(Path(wow_path).glob(SAVED_VARIABLES_GLOB))


def _as_dict(value: Any) -> dict:
    return value if isinstance(value, dict) else {}


def _entries(value: Any) -> list:
    """Table entries as a list; the parser returns a dict for an empty table, a list otherwise."""
    return value if isinstance(value, list) else []


@dataclass
class SavedState:
    """Merged view over the ``WoWForeverAP_DB`` tables of all accounts."""
    databases: list[dict] = field(default_factory=list)

    def _slot_tables(self, slot_key: str) -> Iterable[dict]:
        for database in self.databases:
            slot = _as_dict(_as_dict(database.get("slots")).get(slot_key))
            if slot:
                yield slot

    def outbox_ids(self, slot_key: str) -> set[int]:
        """Location ids of all check entries of ``slot_key`` over every account."""
        found: set[int] = set()
        for slot in self._slot_tables(slot_key):
            for entry in _entries(slot.get("outbox")):
                location_id = _as_dict(entry).get("id")
                if _as_dict(entry).get("kind") == CHECK_KIND and isinstance(location_id, int) \
                        and not isinstance(location_id, bool):
                    found.add(location_id)
        return found

    def goal_reached(self, slot_key: str) -> bool:
        """True when any linked character on any account reached the goal."""
        return any(_as_dict(slot.get("goal")) for slot in self._slot_tables(slot_key))

    def linked_count(self, slot_key: str) -> int:
        """Number of characters, over all accounts, linked to ``slot_key``."""
        return sum(
            1
            for database in self.databases
            for character in _as_dict(database.get("characters")).values()
            if _as_dict(character).get("slotKey") == slot_key
        )


def read_file(path: Path) -> dict:
    """Parse one SavedVariables file into the ``WoWForeverAP_DB`` table; raises LuaParseError or OSError."""
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    return _as_dict(parse_assignments(text).get(DB_VARIABLE))


def read_all(wow_path: Path) -> SavedState:
    """Read and merge every account's file; an unreadable or unparseable file is logged and skipped."""
    state = SavedState()
    for path in find_files(wow_path):
        try:
            state.databases.append(read_file(path))
        except (LuaParseError, OSError) as error:
            LOGGER.warning("Skipping %s this round: %s", path, error)
    return state
