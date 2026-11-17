"""Imports the apworld's pure modules (ids, data_loader, client.lua_table, ...) without Archipelago.

``apworld/wow_forever/__init__.py`` imports Archipelago, which the tools must not need. A package object
without executing that ``__init__`` is enough for the pure modules and their relative imports.
"""
import importlib
import importlib.util
import sys
from pathlib import Path
from types import ModuleType

ROOT = Path(__file__).resolve().parent.parent
APWORLD_DIR = ROOT / "apworld" / "wow_forever"
PACKAGE = "wow_forever"


def _ensure_package() -> None:
    if PACKAGE in sys.modules:
        return
    spec = importlib.util.spec_from_file_location(
        PACKAGE, APWORLD_DIR / "__init__.py", submodule_search_locations=[str(APWORLD_DIR)])
    if spec is None:
        raise ImportError(f"cannot load the apworld package from {APWORLD_DIR}")
    sys.modules[PACKAGE] = importlib.util.module_from_spec(spec)


def apworld_module(name: str) -> ModuleType:
    """Import ``apworld/wow_forever/<name>.py`` (dotted for subpackages, e.g. ``client.lua_table``)."""
    _ensure_package()
    return importlib.import_module(f"{PACKAGE}.{name}")
