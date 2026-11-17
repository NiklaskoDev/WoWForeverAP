#!/usr/bin/env bash
# Non-Python CI checks: Lua lint and tests, generated-data check, packaging.
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

ensure_lua_tool luacheck
luacheck addon
ensure_lua_tool busted
busted addon/spec

python tools/gen_addon_data.py --check
python tools/build.py
