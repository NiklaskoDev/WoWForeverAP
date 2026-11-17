# 004 — Extra check categories

Status: approved
Type: feature
Version impact: none until release — part of the first release (expected `0.1.0`); uses location categories reserved in 001.

## Goal
Optional, weighted check categories (scout feature #6): dungeon and raid boss kills, zone/area discovery, reputation standings, Legacy System milestones and PvP. Each one can be turned on or off and given a weight. Seeds become longer and more varied.
Out of scope: everything declined in 001 (#7–#10); new item types (any dungeon access items depend on D1 below and use reserved item category 5 only if chosen).

## Reuse
- 001: `ids.LocCat` 4–8 (already reserved), `data_loader` pattern and validation, `locations.py` selection, `rules.can_reach_level`/`has_zone`, `releases`, `gen_addon_data.py`, `Detect/*` pattern, inbox `locations`/`checked`, `Locales/*`.
- 003: `Core/Checks.lua` lists (new categories appear in the Checks tab under their zone or a "Character" group).
- New CSVs, one per category (reason: different keys and fields per category).

## Code layout
- `apworld/wow_forever/data/instances.csv`, `encounters.csv`, `discoveries.csv`, `reputations.csv`, `legacy.csv`, `pvp.csv` — new data.
- `apworld/wow_forever/data_loader.py` — load and validate them.
- `apworld/wow_forever/options.py` — per category `<Cat>Checks(Toggle)` + `<Cat>Weight(Range 1–100)`.
- `apworld/wow_forever/locations.py` — category selection and weighted sampling.
- `apworld/wow_forever/regions.py` — instance regions (per D1).
- `apworld/wow_forever/rules.py` — rules per category.
- `apworld/wow_forever/__init__.py` — `fill_slot_data` adds `categories`.
- `tools/gen_addon_data.py` — Lua tables for the new categories.
- `addon/WoWForeverAP/Detect/Encounters.lua`, `Detect/Discovery.lua`, `Detect/Reputation.lua`, `Detect/Legacy.lua` (only per D2), `Detect/PvP.lua` — new.
- `addon/WoWForeverAP/Core/Checks.lua` — include new categories.
- `addon/WoWForeverAP/Core/Link.lua` — store baselines at link time for reputation, honorable kills and battleground wins (progress before linking does not count, same as 001).
- Locales, TOC, docs, `CHANGELOG.md`.
- Tests: `tests/test_categories.py`, `tests/test_data_loader.py` (extend), `addon/spec/detect_*_spec.lua`.

## Data
- `instances.csv`: `instance_id:int` (PK), `name`, `kind:dungeon|raid`, `entrance_ui_map_id:int` (FK zones), `min_level:int`, `group_size:int`, `faction`, `release:int`.
- `encounters.csv`: `encounter_id:int` (PK, `ENCOUNTER_END` id), `name`, `instance_id:int` (FK), `release:int`. Location id `LocCat.BOSS, encounter_id`; AP name `{instance}: {boss}`.
- `discoveries.csv`: `area_id:int` (PK), `name`, `ui_map_id:int` (FK zones), `release:int`. AP name `Discover {zone}: {area}`.
- `reputations.csv`: `faction_id:int`, `standing:int` (5 friendly … 8 exalted), `name`, `faction_side`, `required_level:int`, `required_ui_map_ids` (`;`), `release:int`; PK (faction_id, standing); native `faction_id*10+standing`. AP name `{faction}: {standing name}`.
- `legacy.csv`: `legacy_id:int` (curated PK), `name`, `kind`, `param:int`, `release:int` (only per D2).
- `pvp.csv`: `pvp_id:int` (curated PK), `kind:hk_total|bg_win`, `param:int` (kill count or battleground map id), `name`, `required_level:int`, `release:int`.
- SV: `characters[guid].baselines = { rep = {[factionID] = standing}, hk = <int>, bgWins = {[mapId] = <int>} }`.
- Slot data / inbox `options.categories = { boss = bool, discovery = bool, reputation = bool, legacy = bool, pvp = bool }`.

## Interfaces
- Options (defaults): `BossChecks` [on], `DiscoveryChecks` [on], `ReputationChecks` [off], `LegacyChecks` [off], `PvpChecks` [off]; each `…Weight(Range 1–100)` [100] = percentage of the category's eligible locations included, sampled with `self.random` after release/faction filtering (at least 1 when enabled and eligible > 0).
- Rules:
  - boss: `has_zone(entrance)` and `can_reach_level(instance.min_level)`; raids additionally `can_reach_level(60)` and access to the same release (D1 may add an access item).
  - discovery: `has_zone(ui_map_id)`.
  - reputation: all `required_ui_map_ids` `has_zone` and `can_reach_level(required_level)`.
  - legacy: per D2.
  - pvp: `can_reach_level(required_level)`.
- Detection (linked character, id in seed, not checked/outbox):
  - `ENCOUNTER_END(encounterID, _, _, _, success)` with `success == 1`.
  - Discovery: on `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA` → `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition`, `C_MapExplorationInfo.GetExploredAreaIDsAtPosition` → listed area ids.
  - Reputation: `UPDATE_FACTION` → `C_Reputation.GetFactionDataByID(id).reaction` for listed factions; standing reached above baseline.
  - PvP: `PLAYER_PVP_KILLS_CHANGED` → `GetPVPLifetimeStats()` honourable kills − baseline; battleground win on `UPDATE_BATTLEFIELD_STATUS` + `GetBattlefieldWinner()` matched to the player's faction.
  - Legacy: per D2.

## Security and user data
None beyond 001.

## UI
New categories appear in 003's Checks tab: bosses and discoveries under their zone, reputation/legacy/PvP under "Character". No new components.

## Steps
1. Confirm D1 and D2.
2. CSVs (initial data per 001 D1 process; extend `/wfap capture` to log `ENCOUNTER_END` ids and discovered area ids) + loader + tests.
3. Options, location selection with weights, regions, rules, slot data + tests.
4. Regenerate `Generated.lua`; addon detectors + baselines + specs.
5. Checks tab integration, locales, docs, `CHANGELOG.md`.

## Tests
- Each category off → no locations of that category; on with weight 100 → all eligible; weight 50 with 10 eligible → 5; weight 1 with 3 eligible → 1.
- Release filter applies to every new category; other-faction rows excluded.
- Boss in a raid needs level 60 logic; discovery needs its zone.
- Generated ids use `LocCat` 4–8 and their native ids.
- Default options still beatable; all categories on still beatable.
- Lua: `ENCOUNTER_END` with success 0 ignored; reputation below or equal to baseline ignored; HK milestones count from baseline; discovery of an unlisted area ignored.

## Decisions for the programmer
Resolved 2026-11-17: the programmer accepted every recommendation below.
- **D1 Dungeons and raids in the zone rules.** (a) An instance belongs to the zone with its entrance; no new items. (b) Separate "Dungeon/Raid: X" unlock items (reserved item category 5). **Recommend (a)** for fewer items; (b) gives more pool variety. Group finder teleports: honor rule "allowed only if the entrance zone is unlocked" under (a).
- **D2 Legacy System milestones.** The scout's "Legacy System" is unverified and its addon API is unknown. (a) The programmer confirms the feature and gives the API (event + query function) from the live client; implement then. (b) Leave the category out of this plan and keep `LocCat.LEGACY` reserved. **Recommend (b)** unless (a) can be confirmed before Step 2.
- **D3 PvP scope.** (a) Honourable-kill totals + battleground wins. (b) Honourable kills only. **Recommend (a)**, off by default.

## Risks / follow-ups
- `ENCOUNTER_END`, `C_MapExplorationInfo` and `C_Reputation.GetFactionDataByID` are Mainline APIs; confirm in the live client (001 D2). 12.x "secret value" combat restrictions should not affect `ENCOUNTER_END` payloads, but verify.
- Raid release date (9 Dec 2026) comes from a single source; raid rows get `release` > 1 only after the programmer confirms the date.
