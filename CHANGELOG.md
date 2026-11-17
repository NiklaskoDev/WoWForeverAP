# Changelog

Versions follow `{major}.{minor}.{hotfix}[-prN]` — see `docs/ai/versioning.md`.
Sections per version: Added, Changed, Fixed, Removed, Security.

## [Unreleased]
### Added
- Archipelago apworld "World of Warcraft Forever": zone unlocks and progressive profession tiers as items; quest turn-ins, level milestones and profession-skill milestones as locations; goal is reaching level 60. IDs are derived from Blizzard ids, rows carry a content release, options cover faction, start zone, content release, professions and milestone steps. Start-zone quest data is provisional until confirmed in the live client.
- Archipelago client (launcher component) that reads the addon's SavedVariables and writes only the inbox addon file; commands `/wowpath`, `/sync`, `/status`.
- Tooling: pinned Archipelago checkout (`scripts/setup_ap.sh`), CI setup, ruff and pytest configuration, MIT licence.

## [0.1.0] - YYYY-MM-DD
### Added
- Initial version.
