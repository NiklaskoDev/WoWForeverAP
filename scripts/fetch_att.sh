#!/usr/bin/env bash
# Clones AllTheThings at the pinned commit into .att/AllTheThings (blob-less, only the Forever database)
# for tools/import_att.py. Safe to run repeatedly. ATT is dev-time input only: nothing here runs at play time.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sha="$(tr -d '[:space:]' < "$root/tools/att_version.txt")"
att_dir="$root/.att/AllTheThings"
subdir=".contrib/.db/forever"

if [ -d "$att_dir/.git" ]; then
    current="$(git -C "$att_dir" rev-parse HEAD 2>/dev/null || true)"
    if [ "$current" != "$sha" ]; then
        echo "ATT checkout is at '${current:-unknown}', pinned commit is $sha: removing it" >&2
        rm -rf "$att_dir"
    fi
fi
if [ ! -d "$att_dir/.git" ]; then
    mkdir -p "$root/.att"
    git clone --filter=blob:none --no-checkout --sparse https://github.com/ATTWoWAddon/AllTheThings.git "$att_dir"
    git -C "$att_dir" sparse-checkout set "$subdir"
    git -C "$att_dir" fetch --depth 1 origin "$sha"
    git -C "$att_dir" checkout --quiet "$sha"
fi
echo "$att_dir/$subdir"
