"""Builds and writes the client -> game inbox file. The only file the client ever writes into the game folder."""
import logging
import os
import tempfile
import time
from collections.abc import Callable, Iterable, Mapping, Sequence
from pathlib import Path
from typing import Any

from .lua_table import LuaParseError, parse_assignments, render

LOGGER = logging.getLogger(__name__)
INBOX_VARIABLE = "WoWForeverAP_Inbox"
INBOX_SCHEMA = 1
INBOX_ADDON_FOLDER = Path("Interface") / "AddOns" / "WoWForeverAP_Inbox"
INBOX_FILE = "Inbox.lua"
UNKNOWN_SENDER = "?"
MAX_HINTS = 200

# slot_data key -> inbox option key
_OPTION_KEYS = {
    "faction": "faction",
    "start_zone": "startZone",
    "content_release": "contentRelease",
    "goal_level": "goalLevel",
    "professions": "professions",
    "level_step": "levelStep",
    "profession_step": "professionStep",
    "economy": "economy",
}


class InboxError(RuntimeError):
    """The inbox cannot be built or written; the message tells the player what to do."""


def build(
    slot_key: str,
    seed: str,
    slot: str,
    slot_data: Mapping[str, Any],
    server_locations: Iterable[int],
    checked: Iterable[int],
    received_items: Sequence[Any],
    names: Mapping[int, str],
    hints: Iterable[Mapping[str, Any]] = (),
) -> dict[str, Any]:
    """The inbox table of one slot. ``received_items`` are NetworkItem-like (item, location, player), in order.

    ``hints`` are already resolved to names (see ``hint_entry``); malformed ones are dropped, at most
    ``MAX_HINTS`` are kept, open hints before found ones."""
    del slot_key  # the key is where the table is stored, not part of it
    missing = [key for key in (*_OPTION_KEYS, "world_version") if key not in slot_data]
    if missing:
        raise InboxError(f"slot data is missing {', '.join(missing)}: the seed was made by an incompatible apworld")
    return {
        "seed": seed,
        "slot": slot,
        "worldVersion": slot_data["world_version"],
        "options": {inbox_key: slot_data[data_key] for data_key, inbox_key in _OPTION_KEYS.items()},
        "locations": {location_id: True for location_id in server_locations},
        "checked": {location_id: True for location_id in checked},
        "items": [
            {"id": item.item, "sender": names.get(item.player, UNKNOWN_SENDER), "loc": item.location}
            for item in received_items
        ],
        "hints": _capped_hints(hints),
    }


def hint_entry(
    item: str, item_id: int, location: str, finder: str, receiver: str, found: bool, our_item: bool
) -> dict[str, Any]:
    """One hint as the addon reads it. Names come from other players' data: they are only ever rendered as
    escaped Lua strings and shown with SetText, never evaluated."""
    return {"item": item, "itemId": item_id, "location": location, "finder": finder, "receiver": receiver,
            "found": found, "ourItem": our_item}


def _valid_hint(hint: Mapping[str, Any]) -> bool:
    texts = all(isinstance(hint.get(key), str) for key in ("item", "location", "finder", "receiver"))
    flags = all(isinstance(hint.get(key), bool) for key in ("found", "ourItem"))
    item_id = hint.get("itemId")
    return texts and flags and isinstance(item_id, int) and not isinstance(item_id, bool)


def _capped_hints(hints: Iterable[Mapping[str, Any]]) -> list[dict[str, Any]]:
    """Valid hints only, open before found, a stable order (hints carry no timestamp), at most MAX_HINTS."""
    valid = [dict(hint) for hint in hints if isinstance(hint, Mapping) and _valid_hint(hint)]
    valid.sort(key=lambda hint: (hint["found"], hint["location"], hint["item"], hint["receiver"]))
    return valid[:MAX_HINTS]


def inbox_path(wow_path: Path) -> Path:
    """Path of ``Inbox.lua``; raises InboxError when the inbox addon is not installed or the path escapes."""
    root = Path(wow_path).resolve()
    addon_folder = root / INBOX_ADDON_FOLDER
    if not addon_folder.is_dir():
        raise InboxError(f"{addon_folder} not found: install the WoWForeverAP_Inbox addon first "
                         "and check the WoW path (/wowpath)")
    target = (addon_folder / INBOX_FILE).resolve()
    if not target.is_relative_to(root):
        raise InboxError(f"{target} is outside the WoW folder {root}; refusing to write")
    return target


def read_slots(path: Path) -> dict[Any, Any]:
    """Slots of an existing inbox file; an unreadable or malformed file counts as empty."""
    try:
        parsed = parse_assignments(Path(path).read_text(encoding="utf-8", errors="replace"))
    except FileNotFoundError:
        return {}
    except (LuaParseError, OSError) as error:
        LOGGER.warning("Existing inbox %s is unusable and will be replaced: %s", path, error)
        return {}
    inbox = parsed.get(INBOX_VARIABLE)
    slots = inbox.get("slots") if isinstance(inbox, dict) else None
    return slots if isinstance(slots, dict) else {}


def write(wow_path: Path, slot_key: str, slot_dict: dict[str, Any], now: Callable[[], float] = time.time) -> Path:
    """Replace this slot in the inbox file, keep all other slots, write atomically; returns the file path."""
    target = inbox_path(wow_path)
    slots = read_slots(target)
    slots[slot_key] = slot_dict
    text = render(INBOX_VARIABLE, {"schema": INBOX_SCHEMA, "written": int(now()), "slots": slots})
    handle, temp_name = tempfile.mkstemp(dir=target.parent, prefix=f"{INBOX_FILE}.", suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8", newline="\n") as temp_file:
            temp_file.write(text)
        os.replace(temp_name, target)
    except BaseException:
        Path(temp_name).unlink(missing_ok=True)
        raise
    return target
