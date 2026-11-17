# 001 — Playable core: apworld, AP client, WoW addon (multi-character, release-tagged, ID-based)

Status: approved
Type: new project
Version impact: none until release — nothing is released yet; all entries go under `[Unreleased]`. Plans 001–004 together form the first release (expected `0.1.0`), which happens only when the programmer says so.

## Goal
A playable Archipelago game "World of Warcraft Forever": the apworld generates seeds whose items are zone unlocks and progressive profession tiers and whose locations are quest turn-ins, character-level milestones and profession-skill milestones. An AP client exchanges data with an in-game addon only through SavedVariables (read) and an addon data file (write) that the game loads on a player-initiated `/reload` or login. Built in from the start (chosen scout features, all retrofit-hard):
- **#1 Multi-character slots** — any number of characters (one account or several players/PCs) link to one slot; checks are merged by the AP server; unlocks apply to every linked character.
- **#2 Content-release tagging** — every location/item row carries a `release` id; option `content_release` limits a seed; ID ranges are reserved per category.
- **#3 Locale-independent data, localised addon** — all logic and detection key on quest/uiMap/skill-line IDs; addon text in enUS and deDE with enUS fallback.
- **Minimum goal** — see Decisions D6 (recommended: any linked character reaches level 60).

Built by later plans: 002 economy and self-found rules (#5), 003 in-game lock and check UI (#4), 004 extra check categories (#6). 001–004 must all land before the first release, so seeds are not affected by them.

Out of scope (declined by the programmer): #7 Hardcore and DeathLink · #8 run shape and goal options (start from an existing character, alternative goals, length scaling) · #9 external tracker support (Universal Tracker slot data, PopTracker pack) · #10 honor-system trap items. The layout must not block them (see Risks).

### ToS boundary (binding for every plan)
- The addon uses only the official in-game Lua API. It never automates actions, never casts, moves, buys or sends anything for the player.
- The client never reads game memory, never touches network traffic, never sends keystrokes/input to the game, never triggers `/reload` and never starts or stops the game.
- Game → client: the client **reads** `WTF/Account/*/SavedVariables/WoWForeverAP.lua`, which the game writes on `/reload`, logout or exit.
- Client → game: the client **writes** only `Interface/AddOns/WoWForeverAP_Inbox/Inbox.lua`, which the game loads on the next player-initiated `/reload` or login. This is the same pattern as the TSM desktop app and WeakAuras Companion.
- Unlocks and restrictions are honor-system rules shown to the player. No in-game goods, gold or services are produced by the tool.

## Reuse
- Archipelago `worlds/osrs` as the structural reference (World/Options/Items/Locations/Regions/Rules split, region-unlock items, CSV-driven data). We keep CSVs as runtime data loaded with `pkgutil.get_data` instead of OSRS's generated `.py` tables, so the addon's Lua tables can be generated from the same source.
- Archipelago `CommonClient.CommonContext`, `ClientCommandProcessor`, `server_loop`, `get_base_parser`, `gui_enabled`; `worlds.LauncherComponents` (`Component`, `Type.CLIENT`, `launch_subprocess`, `components`); `settings.Group` for the WoW path in `host.yaml`; `test.bases.WorldTestBase` for generation tests.
- RuneLite Region Locker concept: whole-zone unlocks, honor system.
- Existing repo: `.github/workflows/ci.yml` (Python step plus `scripts/ci.sh` hook), `release.yml`, `.gitignore`, `CHANGELOG.md`.
- New structures (nothing exists yet): everything below. Lua table parser in `lua_table.py`: the stdlib has none and the SavedVariables subset is small (see D5).

## Code layout
Project block values for `CLAUDE.md` (the programmer pastes them in after approval):
- Stack: Python 3.12 (apworld + AP client, inside the Archipelago launcher) · Lua 5.1 (WoW addon) · no database.
- Commands: setup `bash scripts/setup_ap.sh` · test `pytest` and `bash scripts/ci.sh` · lint `ruff check .` and `luacheck addon` · build `python tools/build.py` → `dist/wow_forever.apworld`, `dist/WoWForeverAP-<version>.zip`
- Version source of truth: `VERSION` (see D4)
- Layout: `apworld/wow_forever/` apworld (world + `client/` + `data/*.csv`) · `addon/WoWForeverAP/` main addon · `addon/WoWForeverAP_Inbox/` client-written data addon · `tools/` build/generators · `scripts/` setup/CI · `tests/` Python tests (run against a pinned Archipelago checkout in `.ap/`) · `addon/spec/` Lua tests

Files (create):
- `VERSION` — single line `0.0.0`.
- `pyproject.toml` — tool config only (no `[project]` table): ruff (`extend-exclude = [".ap", "dist"]`, target py312), pytest (`testpaths = ["tests"]`).
- `tests/conftest.py` — puts `.ap/Archipelago` first on `sys.path`; fails with a clear message "run scripts/setup_ap.sh" if missing.
- `tools/ap_version.txt` — pinned Archipelago release tag (D3).
- `scripts/setup_ap.sh` — clone Archipelago at the pinned tag into `.ap/Archipelago` (shallow, idempotent), `pip install -r .ap/Archipelago/requirements.txt`, symlink `apworld/wow_forever` → `.ap/Archipelago/worlds/wow_forever`.
- `scripts/ci.sh` — install `lua5.1`, `luarocks`, `luacheck`, `busted` (apt + luarocks, D5); run `luacheck addon`, `busted addon/spec`, `python tools/gen_addon_data.py --check`, `python tools/build.py`.
- `.luacheckrc` — `std = "lua51"`, globals for the addon's SavedVariables and the WoW API functions used (explicit list, no `allow_defined_top`).
- `LICENSE` — per D8.
- `README.md` — what it is, ToS boundary (copy of the section above), "not affiliated with Blizzard", link to setup guide.
- `apworld/wow_forever/__init__.py` — `WoWForeverWeb(WebWorld)`, `WoWForeverWorld(World)`, launcher component registration.
- `apworld/wow_forever/archipelago.json` — apworld manifest (`game`, `world_version`), only if the pinned AP version supports manifests (check AP `docs/apworld specification.md` at that tag).
- `apworld/wow_forever/settings.py` — `WoWForeverSettings(settings.Group)` with `wow_path: UserFolderPath`.
- `apworld/wow_forever/ids.py` — pure (no AP import): ID scheme encode/decode.
- `apworld/wow_forever/data_loader.py` — pure: dataclasses + CSV loading + validation.
- `apworld/wow_forever/data/releases.csv`, `zones.csv`, `quests.csv`, `professions.csv`, `profession_tiers.csv`, `material_brackets.csv`, `misc_items.csv` — game data (schemas under Data).
- `apworld/wow_forever/options.py` — option classes + `WoWForeverOptions` dataclass.
- `apworld/wow_forever/items.py` — item table, `WoWForeverItem`, pool building.
- `apworld/wow_forever/locations.py` — location table, `WoWForeverLocation`, per-seed selection.
- `apworld/wow_forever/regions.py` — `create_regions(world)`.
- `apworld/wow_forever/rules.py` — `can_reach_level`, `has_zone`, `has_profession_tier`, `has_material_access`, `set_rules(world)`.
- `apworld/wow_forever/client/__init__.py` — empty.
- `apworld/wow_forever/client/lua_table.py` — pure: parse/serialise the Lua table subset.
- `apworld/wow_forever/client/savedvars.py` — pure: find SV files, extract outbox/characters.
- `apworld/wow_forever/client/inbox.py` — pure: build inbox dict, render, atomic write.
- `apworld/wow_forever/client/wow_client.py` — `WoWForeverContext(CommonContext)`, commands, `launch()`.
- `apworld/wow_forever/docs/en_World of Warcraft Forever.md` — game info page (rules, honor system, ToS boundary).
- `apworld/wow_forever/docs/setup_en.md` — setup guide (install apworld + addon, set WoW path, play loop: play → `/reload` → client syncs → `/reload` to receive).
- `tools/gen_addon_data.py` — CSV → `addon/WoWForeverAP/Data/Generated.lua`; `--check` exits 1 if out of date.
- `tools/build.py` — zips apworld and both addon folders; stamps version.
- `tools/import_capture.py` — reads a SavedVariables file's `capture` table and writes review CSVs to `data_capture/` (git-ignored) (only if D1 = option a/c).
- `addon/WoWForeverAP/WoWForeverAP.toc` — `## Interface: <D2>`, `## Title`, `## Version: @version@`, `## SavedVariables: WoWForeverAP_DB`, `## Dependencies: WoWForeverAP_Inbox`, `## AddonCompartmentFunc: WoWForeverAP_OnCompartmentClick`, file list in load order below.
- `addon/WoWForeverAP/Core/Namespace.lua` — addon table `ns`, constants (`SCHEMA = 1`), event dispatcher frame.
- `addon/WoWForeverAP/Core/Locale.lua` — `ns.L` with enUS fallback via metatable; picks `GetLocale()`.
- `addon/WoWForeverAP/Locales/enUS.lua`, `Locales/deDE.lua` — all user-facing strings.
- `addon/WoWForeverAP/Data/Generated.lua` — generated; never hand-edited.
- `addon/WoWForeverAP/Core/Ids.lua` — pure: mirror of `ids.py`.
- `addon/WoWForeverAP/Core/DB.lua` — pure: SV init/migrate, character records, outbox append/prune.
- `addon/WoWForeverAP/Core/Inbox.lua` — pure: validate `WoWForeverAP_Inbox`, list slots, `isLocationInSeed`, `isChecked`, `hasItem`, counts.
- `addon/WoWForeverAP/Core/Link.lua` — pure link/unlink rules + `StaticPopupDialogs` link prompt.
- `addon/WoWForeverAP/Detect/Quests.lua` — `QUEST_TURNED_IN`.
- `addon/WoWForeverAP/Detect/Level.lua` — `PLAYER_LEVEL_UP`, goal detection.
- `addon/WoWForeverAP/Detect/Professions.lua` — `SKILL_LINES_CHANGED`.
- `addon/WoWForeverAP/Detect/Capture.lua` — dev capture mode (only if D1 = a/c).
- `addon/WoWForeverAP/UI/Notify.lua` — chat output helpers (prefix, colour), "unsynced checks" reminder.
- `addon/WoWForeverAP/Commands.lua` — `/wfap` slash command.
- `addon/WoWForeverAP/Main.lua` — `ADDON_LOADED`/`PLAYER_LOGIN` wiring.
- `addon/WoWForeverAP_Inbox/WoWForeverAP_Inbox.toc` — `## Interface`, `## Title: WoWForeverAP Inbox`, `## Version: @version@`, `Inbox.lua`.
- `addon/WoWForeverAP_Inbox/Inbox.lua` — shipped placeholder `WoWForeverAP_Inbox = { schema = 1, slots = {} }`; overwritten by the client.
- `addon/spec/helpers/wow_stub.lua` — minimal stubs (`GetLocale`, `time`, `UnitGUID`…) for busted.
- `addon/spec/*_spec.lua` — Lua tests.
- `tests/test_*.py` — Python tests.

Files (change):
- `.gitignore` — add `.ap/`, `data_capture/`.
- `.github/workflows/ci.yml` — pin `python-version: '3.12'`; run `bash scripts/setup_ap.sh` before `ruff check .`/`pytest` (AP is needed to import the world package).
- `CHANGELOG.md` — `[Unreleased]` → Added entries.

## Data
No database. Stores: CSV game data (in the apworld), the addon's SavedVariables, the client-written inbox file.

### ID scheme (`ids.py` and `Core/Ids.lua` must match; see D7)
`id = BASE + category * 10_000_000 + native`, `BASE = 5_100_000_000`, `0 <= native < 10_000_000`. Items and locations use separate category tables. Category numbers are permanent; reserved ones must never be reused for something else.

Location categories:
| cat | meaning | native | plan |
|---|---|---|---|
| 1 | quest turn-in | questID | 001 |
| 2 | character level reached | level | 001 |
| 3 | profession skill reached | skillLineID * 1000 + skill | 001 |
| 4 | dungeon/raid boss kill | encounterID | 004 (reserved) |
| 5 | zone/area discovery | areaID | 004 (reserved) |
| 6 | reputation standing | factionID * 10 + standingID | 004 (reserved) |
| 7 | Legacy System milestone | curated id | 004 (reserved) |
| 8 | PvP milestone | curated id | 004 (reserved) |
| 9–99 | reserved | — | — |

Item categories:
| cat | meaning | native | plan |
|---|---|---|---|
| 1 | zone unlock | uiMapID | 001 |
| 2 | progressive profession tier | skillLineID | 001 |
| 3 | filler | curated id (`misc_items.csv`) | 001 |
| 4 | care package | curated id | 002 (reserved) |
| 5 | dungeon/raid access | instance id | reserved (004 D-decision) |
| 6–99 | reserved | — | — |

Functions: `location_id(cat, native) -> int`, `item_id(cat, native) -> int`, `decode(id) -> (cat, native)`; all raise `ValueError` for native out of range or unknown category. Constants: `LocCat`, `ItemCat` (`IntEnum`).

### CSV schemas (UTF-8, header row, `,` separator; `name` is English and used only for AP names)
- `releases.csv`: `id:int` (1, 2, … ascending in time), `key:str` (`launch`, `raids_1`, …), `label:str`, `date:YYYY-MM-DD`. Initial rows: `1,launch,Launch,2026-11-04`; add later releases only once their date is confirmed by the programmer.
- `zones.csv`: `ui_map_id:int` (PK), `name`, `min_level:int`, `max_level:int`, `faction:alliance|horde|both`, `is_start:0|1`, `release:int` (FK releases.id).
- `quests.csv`: `quest_id:int` (PK), `name`, `zone_ui_map_id:int` (FK), `req_level:int`, `faction:alliance|horde|both`, `release:int`, `prereq_quest_ids` (`;`-separated quest_ids, may be empty), `extra_zone_ids` (`;`-separated ui_map_ids, may be empty), `name_suffix` (may be empty; used to make AP names unique).
- `professions.csv`: `skill_line_id:int` (PK), `key` (option key, e.g. `alchemy`), `name`, `kind:primary|secondary`, `release:int`.
- `profession_tiers.csv`: `tier:int` (1..n), `name` (Apprentice…), `max_skill:int`, `required_level:int`, `release:int`.
- `material_brackets.csv`: `max_skill:int`, `required_level:int` — character level the logic assumes is needed to obtain materials up to that skill (self-gathered default; 002 extends).
- `misc_items.csv`: `native_id:int`, `kind:filler`, `name`, `release:int`. Initial row: `1,filler,Traveler's Tale,1`.

Validation in `data_loader.load_game_data() -> GameData` (raise `DataError` with file + row number): unique PKs; all FKs resolve; `min_level <= max_level`; `release` exists; `prereq_quest_ids` acyclic; AP names unique after suffix; natives within range. `GameData` is a frozen dataclass of tuples + dicts by id, loaded once and cached (`functools.cache`).

Derived per quest (computed in loader): `effective_zones` = own zone ∪ extra zones ∪ prereqs' effective zones; `effective_level` = max of own and prereqs' `req_level`.

AP names:
- Items: `Zone: {zone.name}`, `Progressive {profession.name}`, misc `name`.
- Locations: `{zone.name}: {quest.name}{" " + suffix if suffix}`, `Reach Level {L}`, `{profession.name} {skill}`.
- Event: location `Goal` (no id) holding event item `Victory`.

### SavedVariables `WoWForeverAP_DB` (account-wide, written by the addon, read by the client)
```lua
WoWForeverAP_DB = {
  schema = 1,
  characters = {               -- key: UnitGUID("player")
    ["Player-…"] = {
      name = "First Surname", faction = "Alliance", classFile = "MAGE",
      slotKey = "<seed_name>:<slot_name>" | nil,  -- nil = not linked
      linkedAt = <epoch>, linkedLevel = <int>,
      skillAtLink = { [skillLineID] = <int> },
      seenItemCount = <int>,
      neverAsk = true|nil,
    },
  },
  slots = {                    -- key: slotKey
    ["<seed>:<slot>"] = {
      outbox = { { kind = "check", id = <locationId>, char = "<guid>", t = <epoch> }, … },
      goal = { char = "<guid>", t = <epoch> } | nil,
    },
  },
  capture = { … },             -- dev only, D1
}
```
`kind` is kept on outbox entries so later kinds (e.g. a DeathLink event, declined #7) can be added without a schema change. Migration: `DB.migrate(db)` upgrades by `schema`; schema 1 is the first version, so for now it only initialises missing tables.

### Inbox `WoWForeverAP_Inbox` (written by the client, read by the addon)
```lua
WoWForeverAP_Inbox = {
  schema = 1, written = <epoch>,
  slots = {
    ["<seed>:<slot>"] = {
      seed = "…", slot = "…", worldVersion = "x.y.z",
      options = { faction = "alliance", startZone = <uiMapId>, contentRelease = <int>,
                  goalLevel = 60, professions = { <skillLineID>, … },
                  levelStep = <int>, professionStep = <int> },
      locations = { [<locationId>] = true, … },   -- all locations in this seed
      checked   = { [<locationId>] = true, … },   -- server's checked set
      items = { { id = <itemId>, sender = "<player>", loc = <locationId> }, … }, -- in received order
    },
  },
}
```
The client rewrites only its own `slotKey`; other slots in the file are kept (one PC may play several seeds).

## Interfaces
### Python (apworld)
- `WoWForeverWorld`: `game = "World of Warcraft Forever"`, `options_dataclass = WoWForeverOptions`, `item_name_to_id` / `location_name_to_id` from full data (all releases, all categories present in data), `settings_key = "wow_forever_options"`, `settings: ClassVar[WoWForeverSettings]`.
  - `generate_early()`: resolve `start_zone` (random among `is_start` zones of the faction if `faction_random`); validate faction match → `OptionError`.
  - `create_regions()` → `regions.create_regions(self)`.
  - `create_items()` → `items.build_pool(self)`; precollect `Zone: <start>`; `self.multiworld.early_items[self.player][<random zone of the faction, release-allowed, not start, min_level <= 11 <= max_level>] = 1`.
  - `set_rules()` → `rules.set_rules(self)`; completion `state.has("Victory", player)`.
  - `get_filler_item_name()` → `"Traveler's Tale"`.
  - `fill_slot_data()` → `{"schema": 1, "world_version", "faction", "start_zone", "content_release", "goal_level", "professions": [skillLineIDs], "level_step", "profession_step"}`.
- Options (`options.py`):
  - `Faction(Choice)`: `alliance`, `horde`; default `alliance`.
  - `StartZone(Choice)`: `faction_random` (default; Archipelago reserves the key `random` for its own random pick — amended 2026-11-17 after review) + one option per `is_start` zone, keys built from `zones.csv` names (snake_case) at import time.
  - `ContentRelease(Choice)`: one option per `releases.csv` key; default = highest id.
  - `Professions(OptionSet)`: valid keys from `professions.csv`; default all.
  - `LevelMilestoneStep(Range)`: 1–10, default 1.
  - `ProfessionMilestoneStep(Range)`: 5–75, default 25.
  - No goal option (D6); goal level = 60 constant `GOAL_LEVEL` in `rules.py`.
- Items: zone unlock for every zone with `release <= content_release` and faction in (`faction`, `both`), except the start zone (precollected). Progressive profession: per selected profession, count = number of tiers with `release <= content_release`. Fill remaining with filler. More items than locations → `OptionError("…enable more professions or a later content_release")`.
- Locations (filter all by `release <= content_release` and faction): quests whose `effective_zones` are all allowed; `Reach Level L` for `L in range(1 + step, 61, step)` plus 60 always; profession milestones `skill in range(step, max_tier_skill + 1, step)` per selected profession.
- Regions: `Menu` → one region per allowed zone (entrance rule `has_zone`); a region `Character` (from `Menu`, no rule) holds level, profession and `Goal` locations. Quests live in the region of their own zone.
- Rules (`rules.py`, all pure functions of `state, world`):
  - `has_zone(state, world, ui_map_id)`: zone is start zone or `state.has("Zone: …")`.
  - `can_reach_level(state, world, level)`: for every `b in range(1, level, 5)` some allowed zone with `has_zone` and `min_level <= b <= max_level`. Level 1 → True.
  - quest rule: all `effective_zones` `has_zone` and `can_reach_level(effective_level)`.
  - `has_profession_tier(state, world, skill_line_id, skill)`: `state.count("Progressive X") >= tier_for(skill)` and `can_reach_level(tier.required_level)`.
  - `has_material_access(state, world, skill_line_id, skill)`: `can_reach_level(bracket_for(skill).required_level)` — single seam that 002 extends.
  - profession location: `has_profession_tier` and `has_material_access`.
  - `Goal`: `can_reach_level(GOAL_LEVEL)`.
### Python (client) — module `worlds.wow_forever.client.wow_client`
- Launcher: `Component("World of Warcraft Forever Client", func=launch, component_type=Type.CLIENT)`.
- `WoWForeverContext(CommonContext)`: `game`, `items_handling = 0b111`, `want_slot_data = True`. Tasks: `sv_watch_loop()` polls every 2 s by mtime; `server_auth()` → `Connect`. On `Connected`/`ReceivedItems`/`RoomUpdate` → `write_inbox()` (debounced 1 s). On SV change → `savedvars.read_all(wow_path)` → for its `slotKey`: `LocationChecks` of outbox ids not in `checked_locations` and present in `server_locations`; if `goal` present and not yet sent → `StatusUpdate(CLIENT_GOAL)`.
- Commands: `/wowpath [path]` (show/set; persists to `host.yaml` via settings), `/sync` (re-read SV and rewrite inbox now), `/status` (linked characters count, pending checks, inbox path).
- `lua_table.parse_assignments(text) -> dict[str, Any]` (top-level `NAME = <value>` statements; values: nil, booleans, numbers incl. negatives/float/hex, strings `"…"` with escapes, `[[…]]` long strings, tables with `[key] =`, `key =` and positional entries; comments `--`). Raises `LuaParseError(line, col, msg)`. `lua_table.render(name, value) -> str`: deterministic, sorted keys, every string escaped (`\\`, `\"`, `\n`, `\r`, `\0`, other control chars as `\ddd`), length cap 200 chars for strings that come from other players.
- `savedvars.find_files(wow_path) -> list[Path]` (`WTF/Account/*/SavedVariables/WoWForeverAP.lua`); `savedvars.read_all(wow_path) -> SavedState` merging all accounts: `outbox_ids(slot_key) -> set[int]`, `goal_reached(slot_key) -> bool`, `linked_count(slot_key) -> int`. Parse errors on one file → logged warning, file skipped this round.
- `inbox.build(slot_key, seed, slot, slot_data, server_locations, checked, received_items, names) -> dict`; `inbox.write(wow_path, slot_key, slot_dict)`: read existing `Inbox.lua` (parse; on error start fresh), replace own slot, write temp file in the same dir, `os.replace`. Missing `WoWForeverAP_Inbox` folder → clear error "install the addon first".
### Lua (addon)
- `/wfap` → help; `/wfap status` (linked slot, items received, open checks count, unsynced outbox count); `/wfap link [n]`; `/wfap unlink`; `/wfap items` (received items in chat, localised names); `/wfap capture on|off` (D1).
- Link rules (`Link.lua`): link prompt at `PLAYER_LOGIN` if the character is unlinked, not `neverAsk`, and the inbox has exactly one slot (several → chat hint to use `/wfap link n`). Warn and refuse if faction ≠ slot faction. If level > 1 warn: "progress made before linking does not count". On link store `linkedLevel`, `skillAtLink`.
- Detection (only when linked and the location id is in the slot's `locations` and not `checked` or already in outbox):
  - `QUEST_TURNED_IN(questID)` → quest location.
  - `PLAYER_LEVEL_UP(level)` → `Reach Level L` for every milestone `linkedLevel < L <= level`; if `level >= goalLevel` set `slots[k].goal`.
  - `SKILL_LINES_CHANGED` → `GetProfessions()`/`GetProfessionInfo(i)` → for each profession milestone `skillAtLink[line] < s <= rank`.
- Localised display names: zones via `C_Map.GetMapInfo(uiMapID).name`, professions via `C_TradeSkillUI.GetProfessionInfoBySkillLineID` (verify, else `GetSkillLineInfo` fallback per D2 notes), quests via `C_QuestLog.GetTitleForQuestID` with fallback to `L.QUEST_FMT:format(id)`.
- Sync reminder (`Notify.lua`): after each new outbox entry print `L.UNSYNCED` ("%d checks waiting — /reload or log out to send them"); after login print new items since `seenItemCount`.

## Security and user data
- Secrets: none. AP server password is entered in the client UI as AP does today; never logged by our code.
- Personal data: character GUID and name stay in local SavedVariables; the client sends only location IDs and goal status to the AP server. Other players' names arrive in the inbox → escaped and length-capped by `lua_table.render` (prevents Lua injection into the addon file).
- File writes are confined to `<wow_path>/Interface/AddOns/WoWForeverAP_Inbox/Inbox.lua`; the client resolves and checks the path stays inside `wow_path` before writing.

## UI
Chat output and one `StaticPopup` (link prompt) only; full UI is plan 003. Chat prefix `|cffd4a017[AP]|r` (one accent colour, Blizzard gold family). No emoji. All strings in `Locales/*.lua`.

## Steps
Run `ruff check .`, `pytest`, `bash scripts/ci.sh` green after each phase.

Phase A — scaffold
1. Create `VERSION`, `pyproject.toml`, `tools/ap_version.txt`, `scripts/setup_ap.sh`, `tests/conftest.py`, `.luacheckrc`, `scripts/ci.sh`, `LICENSE`, `README.md`; update `.gitignore` and `ci.yml`.

Phase B — apworld
2. `ids.py` + `tests/test_ids.py`.
3. CSVs with the initial dataset per D1 (minimum: all launch zones of both factions, the professions and tiers, material brackets, misc item; quests: the verified set available). `data_loader.py` + `tests/test_data_loader.py`.
4. `options.py`, `items.py`, `locations.py`, `regions.py`, `rules.py`, `settings.py`, `__init__.py`, `archipelago.json`.
5. `tests/test_world.py` (WorldTestBase) and `tests/test_rules.py`.

Phase C — client
6. `client/lua_table.py` + `tests/test_lua_table.py`.
7. `client/savedvars.py`, `client/inbox.py` + tests with fixture files under `tests/fixtures/`.
8. `client/wow_client.py` + launcher component; `tests/test_client_sync.py` for the pure sync decision (`pending_checks(outbox, checked, server_locations)`).

Phase D — addon
9. `tools/gen_addon_data.py` → `Data/Generated.lua` (tables: `zones[uiMapID] = {min,max,faction,release}`, `quests[questID] = zoneUiMapID`, `professions[skillLineID] = {key, tiers}`, `levelGoal = 60`) + `tests/test_gen_addon_data.py`.
10. Addon `Core/*`, `Locales/*`, `Detect/*`, `UI/Notify.lua`, `Commands.lua`, `Main.lua`, TOC; Inbox addon.
11. `addon/spec/*_spec.lua` for Ids, DB, Inbox, Link, detection helpers (pure parts).
12. `Detect/Capture.lua` + `tools/import_capture.py` + test (D1 a/c only).

Phase E — packaging and docs
13. `tools/build.py` (replace `@version@` in TOCs, write `world_version` into `archipelago.json`, zip) + `tests/test_build.py`.
14. `docs/en_World of Warcraft Forever.md`, `docs/setup_en.md` (honor rules: locked zone = no questing, killing for XP, gathering or looting there; travelling through is allowed per D9; unlearned profession tier = do not train it).
15. `CHANGELOG.md` `[Unreleased]` → Added.
16. Manual check in the live client (programmer): load addon, link a character, turn in one quest, `/reload`, client sends check, client writes inbox, `/reload`, item shows. Record the result in the PR.

## Tests
- `ids`: round-trip for every category; native −1 / 10_000_000 / unknown category → `ValueError`; Python and Lua give identical ids for a fixture list (generator writes `addon/spec/fixtures/ids.lua` from Python, Lua spec compares).
- `data_loader`: shipped data loads; fixtures with duplicate PK, dangling FK, prereq cycle, duplicate AP name, unknown release each → `DataError` naming file and row.
- World (WorldTestBase): default options generate and are beatable; each faction and each start zone generate; `content_release=launch` excludes rows with release > 1 (fixture data); `professions=[]` generates; too few locations → `OptionError`; start zone of the other faction → `OptionError`; item/location IDs equal `ids.location_id/item_id` of their native ids.
- Rules: `can_reach_level` with only start zone (1–10) → True for 11, False for 12; adding a 10–20 zone → True for 21; quest with prereq in another zone needs both zones; profession 76 needs 2 tiers and tier-2 required level.
- `lua_table`: parses real-looking SV fixture (nested, escapes, long strings, comments, negative/float numbers); malformed input → `LuaParseError` with line; `render` → `parse` round-trip; hostile string (`"]] end os.exit() --"`, newlines, quotes, control chars) renders as one inert string literal.
- `savedvars`: merges two accounts; skips an unparseable file with a warning; only own `slotKey` outbox returned.
- `inbox`: keeps other slots; atomic write leaves no temp file; path outside `wow_path` → error; missing inbox addon folder → error.
- Client sync: pending = outbox ∩ server_locations − checked; goal sent once.
- `gen_addon_data --check`: fails when CSV changed and Lua not regenerated.
- `build`: zips contain expected paths, `@version@` replaced, apworld root folder is `wow_forever/`.
- Lua (busted): DB init/migrate idempotent; outbox no duplicates; prune drops checked ids; Link refuses faction mismatch; level milestone list for `linkedLevel=5 → level 8` with step 1 = {6,7,8}; locale fallback returns enUS for missing deDE key; every key in `deDE.lua` exists in `enUS.lua`.

## Decisions for the programmer
Resolved 2026-11-17: the programmer accepted every recommendation below (D1 a, D3 a, D4 a, D5 luacheck + busted CI-only and own Lua-table parser, D6 a, D7 a, D8 MIT, D9 a/a). D2 (live-client facts) is still open: Phases A–C go ahead now; Phase D waits for D2. Until D2 and the capture pass, initial zone/quest rows come from public Classic Era sources (cite the source per file in a comment line or the README data section) and are provisional; the first release needs them confirmed in the live client.
- **D1 Data source for quests/zones/IDs (biggest risk).** (a) Hand-curated CSVs, filled from an in-game dev capture mode (`/wfap capture` logs uiMapID + localised name + `C_Map.GetMapLevels`, and questID + title + uiMapID + level on turn-in, into SavedVariables; `tools/import_capture.py` turns it into review CSVs). ToS-clean, accurate for Forever, slow to grow. (b) Import from a community database (e.g. Questie's Classic DB): fast, but GPL-3.0 licence obligations for the apworld and Classic IDs may not match Forever. (c) (a) plus datamined DB2 tables from a site such as wago.tools for static tables (zones, skill lines): fast for static data, unclear whether a Forever build is published, and relies on datamined client data. **Recommend (a)**, with 001 shipping all zones/professions and a small verified quest set; quests grow in later data-only changes.
- **D2 Client facts the programmer must supply from the live client** (cannot be verified from outside): output of `/dump GetBuildInfo()` (interface number for the TOCs), the game folder name of Forever (e.g. `_forever_`) under the WoW install, and whether `C_TradeSkillUI.GetProfessionInfoBySkillLineID` and `GetProfessions` exist (`/dump GetProfessions()`). The plan assumes the Mainline (12.x) API; if it is a Classic-style API, detection functions in `Detect/*` change (the plan gets amended).
- **D3 Archipelago dependency and client shipping.** (a) Client lives in the apworld and registers as a Launcher component, using AP's CommonClient; CI clones a pinned AP release. (b) A standalone client (own websocket code, own installer). **Recommend (a)**, pinned to the latest stable AP release at implementation time.
- **D4 Version source of truth.** (a) `VERSION` file; `build.py` stamps TOCs and `archipelago.json`. (b) `pyproject.toml [project].version` (makes CI `pip install -e .` the repo, which needs packaging config). (c) `archipelago.json` `world_version`. **Recommend (a).**
- **D5 New dev dependencies.** Lua tooling: (a) `luacheck` + `busted` via luarocks, CI only; (b) only `luacheck`, no Lua unit tests; (c) none. Lua table parsing: (a) own stdlib parser (~150 lines, tested); (b) `slpp`/`lupa` from PyPI. **Recommend luacheck + busted (CI only) and the own parser** (no runtime dependency for players beyond Archipelago).
- **D6 Minimum goal (no goal options — #8 declined).** (a) Any linked character reaches level 60. (b) Complete N checks. (c) Turn in one fixed final quest. **Recommend (a)**: clear, detectable with `PLAYER_LEVEL_UP`, uses only zone logic.
- **D7 ID scheme.** (a) Derived from Blizzard ids (`BASE + cat * 10M + native`, above): stable when data is added, nothing to renumber. (b) Sequential ids from a registry file per category. **Recommend (a).** `BASE = 5_100_000_000` is arbitrary; any value works as long as it never changes after the first release.
- **D8 Licence.** (a) MIT (same as Archipelago). (b) GPL-3.0. (c) other / none yet. **Recommend MIT**, plus a "not affiliated with Blizzard Entertainment" notice. Must be GPL if D1 = (b).
- **D9 Honor rule for locked zones and start areas.** Travel: (a) passing through a locked zone (roads, flight paths, boats) is allowed, but no questing, XP kills, gathering or looting there; (b) locked zones may not be entered at all — then the logic would need a zone-adjacency graph. **Recommend (a)** (no graph needed). Start areas: (a) one start zone per seed, precollected; characters of other races travel to it; (b) every start zone of the faction is free. **Recommend (a)**.

## Risks / follow-ups
- Data coverage: with D1 (a) the first release depends on how much the programmer captures; a seed with few quests still works (level and profession checks), but is less varied.
- API uncertainty: the scout's "Mainline/Midnight 12.x API, interface ~16001" is unverified; D2 must be answered before Phase D. Combat restrictions in 12.x do not affect us (no combat-log reading in 001).
- Release dates: only launch 2026-11-04 is confirmed by several sources; the 9 Dec 2026 raid release appears in one source only. Do not add release rows until the programmer confirms them.
- SavedVariables are only written on `/reload`, logout or exit; a game crash loses unsynced checks since the last write. Documented in setup guide.
- New files added to an addon folder are only picked up after a full client restart, so the inbox addon ships a placeholder `Inbox.lua`; the client only overwrites it.
- Declined features stay possible: DeathLink (#7) = new outbox `kind` + client handler; slot takeover by a new character = linking already works per character; tracker support (#9) = `fill_slot_data` already carries all options; trap items (#10) = an item category from the reserved range; start from an existing character (#8) = `linkedLevel`/`skillAtLink` baselines already exist.
- Python must be a version the pinned AP release supports (3.12 pinned in CI).
