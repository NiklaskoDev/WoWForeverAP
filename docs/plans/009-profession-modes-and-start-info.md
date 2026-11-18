# 009 — Solo / team profession modes and a "start info" command

Status: approved
Type: feature
Version impact: minor — new options and commands, backward compatible (defaults keep today's seeds; no slot-data or inbox format change). Part of 0.2.0 together with 008 and 010; no release without the programmer's word.
Depends on: 008 (the start info shows the goal level, and the options sit next to `goal_level`).

## Goal
- `profession_mode` limits how many **primary** professions a seed has: `solo` = 2 (one character's limit) plus every selected secondary profession; `team` = 2 per team member (`team_size`) plus every selected secondary. `all` (default) = today's behaviour.
- A command shows the slot's faction, randomized start zone, goal level and professions: in the Archipelago client (`/start`, works as soon as the client is connected, before the game is started) and in the addon (`/wfap start`, works on any character, linked or not, once the inbox has the slot).
Out of scope: assigning professions to specific team members or characters; enforcing the 2-primary limit per character in the addon (the game already does).

## Reuse
- `Professions` OptionSet stays the candidate pool; `generate_early` already filters it by release (`__init__.py`).
- Self-found check: `rules.unreachable_material_sources` (refactored into a pure helper so candidate sets can be tested before choosing).
- Slot data already has `faction`, `start_zone`, `goal_level`, `professions` (skill line ids); the inbox already has `faction`, `startZone`, `goalLevel`, `professions`. Both commands read only these, so they also work for v0.1.0 seeds.
- Client: `WoWForeverCommandProcessor` + module-level pure helpers as in `wow_client.py` (`pending_checks`, `goal_to_send`); names from `data_loader.load_game_data()` (cached).
- Addon: `Commands.lua` handlers, `ns.Inbox.slotKeys/slot/options`, `ns.Names.zone/profession`, `ns.Notify.say/print`, `ns.Style.escape`, locale files.

## Code layout
- `apworld/wow_forever/options.py` — `ProfessionMode(Choice)`, `TeamSize(Range)`, constant `PRIMARIES_PER_CHARACTER = 2`, function `primary_limit(options) -> int | None`; fields after `professions`.
- `apworld/wow_forever/rules.py` — pure `missing_gatherers(professions, material_sources, data)`; `unreachable_material_sources(world)` becomes a thin wrapper (empty with market access, as today).
- `apworld/wow_forever/__init__.py` — `_select_professions()` replaces the inline comprehension for `selected_professions`; optional `write_spoiler_header` (D4).
- `apworld/wow_forever/client/wow_client.py` — `start_info_lines(slot_data, data)`; `_cmd_start`.
- `addon/WoWForeverAP/Core/Names.lua` — `Names.faction(key)`.
- `addon/WoWForeverAP/Commands.lua` — `Commands.startLines(slot)`, `handlers.start`, help key.
- `addon/WoWForeverAP/Locales/enUS.lua`, `deDE.lua` — new keys (below).
- `apworld/wow_forever/docs/en_World of Warcraft Forever.md`, `docs/setup_en.md` — options and both commands.
- `CHANGELOG.md` — `[Unreleased]` → Added.

## Data
None. No CSV change. Slot data / inbox unchanged (D5).

## Interfaces
- `ProfessionMode(Choice)`: `option_all = 0`, `option_solo = 1`, `option_team = 2`, `default = 0`, display "Profession Mode". Docstring: "all: every profession in Professions. solo: at most 2 primary professions (what one character can learn) plus every secondary profession in Professions. team: at most 2 primary professions per team member (Team Size) plus every secondary. When Professions lists more primaries than allowed, the seed picks them at random; list exactly the ones you want to choose them yourself."
- `TeamSize(Range)`: display "Team Size", docstring "Number of players sharing this slot in team mode; each brings 2 primary professions. Ignored in the other modes."; range/default per D2 (proposal 2–4, default 2).
- `options.primary_limit(options) -> int | None` — `None` for `all`, `2` for `solo`, `2 * team_size` for `team`.
- `rules.missing_gatherers(professions: Iterable[Profession], material_sources, data) -> dict[Profession, list[Profession]]` — today's loop body of `unreachable_material_sources`, with the selected set given explicitly.
- `WoWForeverWorld._select_professions() -> tuple[Profession, ...]`:
  1. `candidates` = professions in `options.professions` with `release <= content_release`, in data order (today's comprehension).
  2. `limit = primary_limit(self.options)`; `primaries = [p for p in candidates if p.kind == "primary"]`, `secondaries` = the rest. If `limit is None or len(primaries) <= limit` → return `candidates` **without touching `self.random`** (default seeds stay identical).
  3. Else `combos = list(itertools.combinations(primaries, limit))`; `self.random.shuffle(combos)`; the first combo for which `rules.has_market_access(self)` is true or `missing_gatherers(combo + secondaries, ...)` is empty wins. Return `combo + secondaries` re-sorted into data order.
  4. No combo works → `OptionError(f"{player}: no {limit} primary professions out of professions can get their own materials with the Auction House, trading, mail and shared banks all off. Add gathering professions or turn one of those options on")`.
  Called in `generate_early` after `material_sources` is computed (move that line up) and before `_check_self_found_materials`; `selected_skill_line_ids` derives from the result as today.
- Client `start_info_lines(slot_data: Mapping[str, Any], data: GameData) -> list[str]` (pure):
  `"Faction: Alliance"`, `"Start zone: Elwynn Forest"`, `"Goal level: 60"`, `"Primary professions: Alchemy, Mining"`, `"Secondary professions: Cooking, First Aid, Fishing"` (`"none"` when empty). Unknown start zone id → `"zone 1234"`; unknown profession id → `"profession 123"`; a missing key → `"unknown"`. Faction shown capitalised.
- Client `/start` (`_cmd_start`, docstring "Show the faction, start zone, goal level and professions of the connected slot."): not connected (`ctx.slot_key is None`) → `"Not connected to a slot: /connect first."`; else prints `start_info_lines(ctx.slot_data, load_game_data())`.
- Addon `Names.faction(key)` — `L.SIDE_ALLIANCE` / `L.SIDE_HORDE` for `"alliance"`/`"horde"` (case-insensitive), else `tostring(key)`.
- Addon `Commands.startLines(slot) -> { string, ... }` (pure): the same five lines from `ns.Inbox.options(slot)`, names via `Names.faction`, `Names.zone`, `Names.profession`; primary/secondary by `ns.Data.professions[id].kind` (unknown id → primary list, `Names.profession` fallback text).
- Addon `/wfap start` (`handlers.start`): linked character with its slot in the inbox → `startLines` of that slot. Otherwise every slot of `ns.Inbox.slotKeys(ns.Inbox.current())`: a `START_SLOT_HEADER` line (`"%d. %s"`, same numbering as `/wfap link`) then its lines. No slots → `LINK_NO_SLOTS`. Linked but slot missing → `SLOT_MISSING` (as `status`).
- Locale keys (enUS / deDE): `SIDE_ALLIANCE` "Alliance"/"Allianz", `SIDE_HORDE` "Horde"/"Horde", `START_FACTION` "Faction: %s"/"Fraktion: %s", `START_ZONE` "Start zone: %s"/"Startgebiet: %s", `START_GOAL` "Goal level: %d"/"Zielstufe: %d", `START_PRIMARY` "Primary professions: %s"/"Hauptberufe: %s", `START_SECONDARY` "Secondary professions: %s"/"Nebenberufe: %s", `START_NONE` "none"/"keine", `START_SLOT_HEADER` "%d. %s", `HELP_START` "/wfap start - faction, start zone, goal and professions of your slot(s)" / German equivalent. Add `HELP_START` to the `help` key list after `HELP_STATUS`.

## Security and user data
None new. The slot key in `START_SLOT_HEADER` contains a player-chosen slot name: pass it through `ns.Style.escape` so a `|` cannot form a chat escape. Zone and profession names come from the game API or the generated data.

## UI
Chat output only (client log and addon chat), same format as `/status` and `/wfap status`. No new window.

## Steps
1. `options.py`: `ProfessionMode`, `TeamSize`, `PRIMARIES_PER_CHARACTER`, `primary_limit`, dataclass fields.
2. `rules.py`: extract `missing_gatherers`; `unreachable_material_sources` calls it. `pytest` green.
3. `__init__.py`: `_select_professions`, reorder `generate_early` as described.
4. Client: `start_info_lines`, `_cmd_start`.
5. Addon: `Names.faction`, `Commands.startLines`, `handlers.start`, help list, locale keys (both files).
6. Only if D4 = yes: move `start_info_lines` to a new `apworld/wow_forever/start_info.py` (no client imports, so generation can use it; the client imports it from there) and add `write_spoiler_header(self, spoiler_handle)` writing `f"{self.player_name}: {line}\n"` for each line of `start_info_lines(self.fill_slot_data(), self.data)`.
7. Docs and `CHANGELOG.md`.
8. Tests; `pytest`, `bash scripts/ci.sh`, `ruff check .`, `luacheck addon`, `python tools/gen_addon_data.py --check`.

## Tests
- `primary_limit`: all → None, solo → 2, team with size 3 → 6.
- Default options: `selected_professions` identical to before and the random state untouched (same start zone and same location sample as before the change for a fixed seed).
- solo, all 12 professions selected, market on → exactly 2 primaries + 3 secondaries; deterministic for a fixed seed; at least two different seeds give different pairs.
- solo with exactly 2 primaries selected → those two.
- team size 3 → 6 primaries; team size whose limit exceeds the 9 primaries → all 9.
- solo, market off, candidates {Blacksmithing, Tailoring, Mining} → result never contains Blacksmithing without Mining (several seeds).
- solo, market off, candidates {Blacksmithing, Engineering, Leatherworking} → `OptionError` with the new message.
- Secondaries deselected in `professions` stay out in solo mode.
- Generation succeeds for solo and team (both factions); progressive items only for selected professions.
- `start_info_lines`: full slot data → the five lines; unknown zone/profession ids → fallbacks; missing keys → "unknown"; empty secondary list → "none".
- `/start` not connected → the "Not connected" line; connected → the lines (processor test like `test_wowpath_*`).
- If D4: spoiler header contains the start zone line (`test_world` with a `StringIO`).
- `addon/spec/commands_spec.lua`: `startLines` for the fixture slot; `/wfap start` linked → one block; unlinked with two slots → two numbered blocks; slot key with `|` is escaped; no slots → `LINK_NO_SLOTS`. `names_spec.lua`: `Names.faction` for "HORDE", "alliance", unknown.
- `addon/spec/locale_spec.lua` (existing key parity) passes with the new keys.

## Decisions for the programmer
Resolved 2026-11-18: the programmer accepted every recommendation below (D1 start info in both client `/start` and addon `/wfap start`; D2 team size 2–4, two primaries per member, secondaries never scaled; D3 `Professions` is the pool (≤ limit → used as is, more → random pick respecting the self-found rule); D4 start info also in the spoiler log; D5 no new slot-data keys).
- **D1 Where the start info lives.** (a) Client `/start` only — known right after connecting, before logging in. (b) Addon `/wfap start` only — needs the client to have written the inbox and a `/reload`. (c) Both. **Recommend (c)**: the client answers before a character exists (needed to pick the faction), the addon answers in game on any character.
- **D2 Team size range and scaling.** (a) `team_size` 2–4, 2 primaries per member (4/6/8; only 9 primaries exist, so 5+ would mean "all"). (b) 2–6, values ≥5 meaning all primaries. **Recommend (a)**. Secondaries are not scaled: every selected secondary is in, as in solo.
- **D3 Which primaries and how modes combine with `Professions`.** (a) `Professions` is the pool: as many or fewer primaries than the limit → used as listed (player-chosen); more → random pick by the seed that respects the self-found rule. Secondaries: those selected in `Professions` (default all). (b) Always random among all primaries, ignoring `Professions` for primaries. (c) Player must list exactly the limit; more is an error. **Recommend (a)**: covers both "I choose" and "surprise me" and keeps `Professions` meaningful.
- **D4 Spoiler log.** Also write the same lines into the spoiler header, so whoever generates can read them without connecting. (a) Yes. (b) No, commands only. **Recommend (a)**; cheap, same lines.
- **D5 Slot data.** (a) No new keys: the commands show the resulting professions, not the mode. (b) Add `profession_mode` / `team_size` as optional keys (read with defaults so v0.1.0 seeds still load; `inbox.build` must not require them). **Recommend (a)**: nothing in the addon needs the mode.

## Risks / follow-ups
- In team mode nothing says which member takes which primaries; players sort that out themselves.
- `/start` is a short command name; `CommonClient` has none today. If Archipelago adds one, this client's processor shadows it for this client only.
