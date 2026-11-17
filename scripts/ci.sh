#!/usr/bin/env bash
# Non-Python CI checks: Lua lint and tests, generated-data check, packaging.
# Steps whose target does not exist yet are skipped with a note (addon and build tooling
# arrive in later phases of plan 001); once they exist they always run.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

as_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

ensure_lua_tool() {
    command -v "$1" >/dev/null && return
    if ! command -v luarocks >/dev/null; then
        as_root apt-get update
        as_root apt-get install -y lua5.1 liblua5.1-0-dev luarocks build-essential
    fi
    as_root luarocks install "$1"
}

if [ -d addon ]; then
    ensure_lua_tool luacheck
    luacheck addon
    if [ -d addon/spec ]; then
        ensure_lua_tool busted
        busted addon/spec
    else
        echo "skip: busted (no addon/spec yet)"
    fi
else
    echo "skip: luacheck, busted (no addon yet)"
fi

if [ -f tools/gen_addon_data.py ]; then python tools/gen_addon_data.py --check; else echo "skip: gen_addon_data (not written yet)"; fi
if [ -f tools/build.py ]; then python tools/build.py; else echo "skip: build (not written yet)"; fi
