"""Puts the pinned Archipelago checkout on sys.path before any test imports the world."""
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
AP_DIR = REPO_ROOT / ".ap" / "Archipelago"

if not (AP_DIR / "worlds" / "wow_forever").exists():
    raise RuntimeError(f"Archipelago checkout with the linked apworld not found in {AP_DIR}: run scripts/setup_ap.sh")

# Archipelago's ModuleUpdate would otherwise pip-install all world requirements on import.
os.environ.setdefault("SKIP_REQUIREMENTS_UPDATE", "1")
sys.path.insert(0, str(AP_DIR))
