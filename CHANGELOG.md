# Changelog

Versions follow `{major}.{minor}.{hotfix}[-prN]` — see `docs/ai/versioning.md`.
Sections per version: Added, Changed, Fixed, Removed, Security.

## [Unreleased]
### Added
- Archipelago apworld "World of Warcraft Forever": zone unlocks and progressive profession tiers as items; quest turn-ins, level milestones and profession-skill milestones as locations; goal is reaching level 60. IDs are derived from Blizzard ids, rows carry a content release, options cover faction, start zone, content release, professions and milestone steps. Start-zone quest data is provisional until confirmed in the live client.
- Archipelago client (launcher component) that reads the addon's SavedVariables and writes only the inbox addon file; commands `/wowpath`, `/sync`, `/status`.
- WoWForeverAP addon (enUS and deDE): link a character to a slot (`/wfap link`), records quest turn-ins, level milestones, profession skill milestones and the level-60 goal as checks in its SavedVariables, reads unlocks from the `WoWForeverAP_Inbox` data addon, and reminds you to `/reload` to send checks. `/wfap capture on` logs zones and quests for the data review. Interface numbers and the Mainline 12.x API are assumptions that still need a check in the live client (see README, "Unconfirmed").
- Tools: `tools/gen_addon_data.py` generates the addon's data tables from the CSVs, `tools/import_capture.py` turns captured zones and quests into review CSVs, `tools/build.py` builds `dist/wow_forever.apworld` and `dist/WoWForeverAP-<version>.zip`.
- Economy and self-found rules: options for the Auction House, trading, mail, shared banks (guild and account bank) and boosts from a main; with all four market options off, crafting professions need their gathering profession (Blacksmithing and Engineering: Mining, Alchemy: Herbalism, Leatherworking: Skinning) and generation stops with a clear message when it is not selected. "Care Package" items (`care_packages`, `care_package_gold`, `care_package_stacks`) each allow one honor-system pull from a main. The addon warns when a disallowed economy window opens and has `/wfap rules`, `/wfap care` and `/wfap care use`. New data file `profession_materials.csv` (provisional).
- Game guide and setup guide for players, README sections on data sources (WoW-Pro Guides credit) and unconfirmed values.
- Tooling: Lua lint and tests (luacheck, busted) and the packaging build run in `scripts/ci.sh`; pinned Archipelago checkout (`scripts/setup_ap.sh`), CI setup, ruff and pytest configuration, MIT licence.

## [0.1.0] - YYYY-MM-DD
### Added
- Initial version.
