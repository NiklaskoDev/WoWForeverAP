#!/usr/bin/env bash
# Clones Archipelago at the pinned tag into .ap/Archipelago, installs its headless
# Python dependencies and links the apworld into it. Safe to run repeatedly.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tag="$(tr -d '[:space:]' < "$root/tools/ap_version.txt")"
ap_dir="$root/.ap/Archipelago"

if [ -d "$ap_dir/.git" ]; then
    current="$(git -C "$ap_dir" describe --tags --exact-match 2>/dev/null || true)"
    if [ "$current" != "$tag" ]; then
        echo "Archipelago checkout is at '${current:-unknown}', pinned tag is $tag: removing it" >&2
        rm -rf "$ap_dir"
    fi
fi
if [ ! -d "$ap_dir/.git" ]; then
    mkdir -p "$root/.ap"
    git clone --depth 1 --branch "$tag" https://github.com/ArchipelagoMW/Archipelago.git "$ap_dir"
fi

# The GUI stack (kivy/kivymd), Cython and the Windows-only Pymem are not needed to
# generate seeds or run the tests, and kivymd is installed from git: skip them.
filtered="$(mktemp)"
trap 'rm -f "$filtered"' EXIT
grep -viE '^(kivy|kivymd|cython|pymem|bsdiff4|pyshortcuts)\b' "$ap_dir/requirements.txt" > "$filtered"
python -m pip install -r "$filtered"

link="$ap_dir/worlds/wow_forever"
if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "$link exists and is not a symlink" >&2
    exit 1
fi
ln -sfn "$root/apworld/wow_forever" "$link"
echo "Archipelago $tag ready in $ap_dir"
