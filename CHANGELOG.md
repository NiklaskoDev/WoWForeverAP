# Changelog

Versions follow `{major}.{minor}.{hotfix}[-prN]` — see `docs/ai/versioning.md`.
Sections per version: Added, Changed, Fixed, Removed, Security.

## [Unreleased]
### Added
- Item descriptions (plan 011): every item has a short description generated from the game data, as the world's item descriptions and as an "Item reference" section of the game guide, kept in sync by `tools/gen_addon_data.py --check`.

### Changed
- World map overlay (plan 013): zone fills follow borders three times as finely (480 x 321 grid) and are sampled over several frames, so opening a continent map does not stutter; fills appear once sampling finishes (first open per session).

### Fixed
- The world map overlay draws zone-shaped fills (strips) by default instead of dark rectangles from the zone highlight art.

### Removed
- The unused zone highlight art option of the map overlay (`Style.MAP_SHAPE_SOURCE`, plan 013); strips are the only shape source.

## [0.2.0] - 2026-11-18
### Added
- Option `goal_level` (slider, 10-60, default 60; plan 008): the character level that wins the game. Zones that start above it, and quests, profession tiers (a tier is left out when its trainer level or material level is above it, and every tier after it), bosses, reputations and PvP milestones that need a higher level, are no longer in the seed; the level milestones end at the goal level and raids need it. The default keeps today's seeds. In the addon, zones above the goal level show as "not in your seed" with no lock warning.
- Options `profession_mode` (`all` default, `solo`, `team`) and `team_size` (2-4, default 2; plan 009): limit the primary professions of a seed to 2 (solo) or 2 per team member, with every selected secondary profession kept. `professions` stays the pool: as many or fewer primaries than the limit are used as listed, more are drawn by the seed, respecting the self-found rule (generation stops with a message when no pick can get its materials). The default mode keeps today's seeds.
- Start info (plan 009): client command `/start` and addon command `/wfap start` show the slot's faction, start zone, goal level and primary and secondary professions (the addon works on any character, linked or not, and lists every slot when unlinked); the spoiler log carries the same lines.

### Changed
- World map overlay (plan 010): locked and not-in-seed zones are filled in their real zone shapes (the game's zone highlight art, or strips sampled from its zone lookup) instead of overlapping rectangles, so fills never overlap; locked zones are red at 45 %, zones outside the seed neutral dark at 65 % (previously black), unlocked and start zones stay clear. The tooltip uses the game's own zone lookup, and the map of a zone outside the seed gets a "Not in your seed" banner next to the red "Locked: travel only" one. `Style.MAP_SHAPE_SOURCE` switches to strips if the art does not look right in the live client.

## [0.1.0] - 2026-11-17
### Added
- Archipelago apworld "World of Warcraft Forever": zone unlocks and progressive profession tiers as items; quest turn-ins, level milestones and profession-skill milestones as locations; goal is reaching level 60. IDs are derived from Blizzard ids, rows carry a content release, options cover faction, start zone, content release, professions and milestone steps. Quest data is unconfirmed until checked in the live client.
- Archipelago client (launcher component) that reads the addon's SavedVariables and writes only the inbox addon file; commands `/wowpath`, `/sync`, `/status`.
- WoWForeverAP addon (enUS and deDE): link a character to a slot (`/wfap link`), records quest turn-ins, level milestones, profession skill milestones and the level-60 goal as checks in its SavedVariables, reads unlocks from the `WoWForeverAP_Inbox` data addon, and reminds you to `/reload` to send checks. `/wfap capture on` logs zones and quests for the data review. Interface numbers and the Mainline 12.x API are assumptions that still need a check in the live client (see README, "Unconfirmed").
- Tools: `tools/gen_addon_data.py` generates the addon's data tables from the CSVs, `tools/import_capture.py` turns captured zones and quests into review CSVs, `tools/build.py` builds `dist/wow_forever.apworld` and `dist/WoWForeverAP-<version>.zip`.
- Economy and self-found rules: options for the Auction House, trading, mail, shared banks (guild and account bank) and boosts from a main; with all four market options off, crafting professions need their gathering profession (Blacksmithing and Engineering: Mining, Alchemy: Herbalism, Leatherworking: Skinning) and generation stops with a clear message when it is not selected. "Care Package" items (`care_packages`, `care_package_gold`, `care_package_stacks`) each allow one honor-system pull from a main. The addon warns when a disallowed economy window opens and has `/wfap rules`, `/wfap care` and `/wfap care use`. New data file `profession_materials.csv` (provisional).
- In-game lock and check UI (plan 003): `/wfap` (or the addon menu) opens a window with tabs Checks (open quests per zone, level and profession milestones), Items, Hints and Rules, a header with the slot, checks waiting for `/reload` and the age of the client data, and a "Link this character" button while unlinked; world map tint for locked zones and zones outside the seed with a tooltip per zone and a "Locked" banner on a locked zone's map; on-screen warnings when entering a locked zone, learning a locked profession or training above the unlocked tier; options in the game's Settings (`/wfap options`). The client now also writes the slot's Archipelago hints (at most 200, open ones first) into the inbox. The window and map overlay use Blizzard templates and map APIs that still need a check in the live client (README, "Unconfirmed").
- Extra check categories (plan 004): optional dungeon boss kills, map-area discoveries, reputation standings (Friendly to Exalted) and PvP milestones (honorable kills, first win per battleground), each with an on/off option and a weight (1-100) that sets the share of its eligible checks included in the seed (`discovery_checks` on by default with weight 20; `boss_checks`, `reputation_checks` and `pvp_checks` off). A dungeon belongs to the zone with its entrance, so its bosses need that zone and the dungeon's level. The addon detects them with `ENCOUNTER_END`, `C_MapExplorationInfo`, `UPDATE_FACTION`, `GetPVPLifetimeStats` and the battleground winner events (all guarded and still unconfirmed for the Forever client, see README), stores reputation, honorable-kill and battleground baselines when a character links, and lists the new checks in the Checks tab (bosses and areas under their zone, reputation and PvP under "Character"). New data files `instances.csv` (14 dungeons), `discoveries.csv` (615 areas), `reputations.csv`, `pvp.csv`, all provisional; `encounters.csv` has no rows until the boss encounter ids are captured in the live client, and raids and the Legacy System are not included. `/wfap capture` now also logs `ENCOUNTER_END` ids and explored area ids, and `tools/import_capture.py` writes review files for them.
- Defaults of the extra check categories: `boss_checks` is off (no boss encounter ids until they are captured in the live client) and `discovery_weight` is 20, so a default seed includes a fifth of the area discoveries.
- Game guide and setup guide for players, README sections on data sources and unconfirmed values.
- Quest import tool (plan 005): `scripts/fetch_att.sh` clones AllTheThings at the commit pinned in `tools/att_version.txt` (dev only, git-ignored `.att/`), and `tools/import_att.py` generates `quests.csv` from its Forever database, writes a review report (`data_capture/att_report.txt`: exclusions by reason, unresolved maps, quests per zone, a zone level and a profession tier cross-check against ATT) and has a `--check` mode. ATT's Lua is parsed as data by `tools/att_lua.py`, never executed.
- Quest weight option `quest_weight` (1-100, default 25): the percentage of the eligible quests that are checks in the seed.
- Tooling: Lua lint and tests (luacheck, busted) and the packaging build run in `scripts/ci.sh`; pinned Archipelago checkout (`scripts/setup_ap.sh`), CI setup, ruff and pytest configuration, MIT licence.
- Release workflow: a version tag builds `wow_forever.apworld` and the addon zip, checks that the tag matches `VERSION` and the stamped versions, and attaches both (with `SHA256SUMS`) to the GitHub release; `scripts/release_dry_run.sh` runs the same steps locally without publishing.

### Changed
- `quests.csv` is now generated from the AllTheThings Forever database (about 1,700 quests, 1,000 to 1,100 per faction, replacing the 34 provisional start-zone rows); `req_level` is ATT's minimum level. Class and race quests, repeatable quests, breadcrumbs, profession and reputation quests, quests that lock out others, and quests in cities and dungeons are left out. The WoW-Pro Guides credit is gone from the data and the docs.
- The addon targets the Forever interface 16001 only (confirmed in the live client with `GetBuildInfo()`); the TOCs no longer list 120105.

### Fixed
- Security workflow: the secret scan (gitleaks) has `pull-requests: read`, so it no longer fails with 403 on pull requests.
