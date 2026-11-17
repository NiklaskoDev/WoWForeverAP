# 003 — In-game lock and check UI

Status: draft
Type: feature
Version impact: none until release — part of the first release (expected `0.1.0`); addon-only plus inbox hints.

## Goal
The honor-system rules stay visible without leaving the game (scout feature #4):
- world-map overlay showing locked and unlocked zones (Region Locker style);
- warnings when entering a locked zone, learning a locked profession or raising a profession above its unlocked tier;
- a panel with open checks per zone, received items and hints.
Out of scope: gear/equip locks (no such items exist — 001's item set has none); everything declined in 001 (#7–#10).

## Reuse
- 001: `Core/Inbox.lua` (items, checked, locations, options), `Data/Generated.lua` (zones, quests, professions), `Core/Ids.lua` decode, `Locales/*`, `UI/Notify.lua`, `Commands.lua`, TOC `AddonCompartmentFunc`.
- 002: economy rules text (`/wfap rules` source) shown in the panel's Rules tab.
- Blizzard UI: `ButtonFrameTemplate`/`PortraitFrameTemplate`, `PanelTabButtonTemplate`, `WowScrollBoxList` + `ScrollUtil`/`CreateScrollBoxListLinearView`, `UIPanelButtonTemplate`, `WorldMapFrame:AddDataProvider` with `MapCanvasDataProviderMixin`, `RaidNotice_AddMessage(RaidWarningFrame, …)`, `Settings.RegisterVerticalLayoutCategory`.
- Client: AP hint data via data storage key `_read_hints_{team}_{slot}` (`SetNotify` + `Get`), already provided by CommonContext.

## Code layout
- `addon/WoWForeverAP/UI/Style.lua` — new: the design tokens below (colours, spacing, fonts).
- `addon/WoWForeverAP/UI/MapOverlay.lua` — new: world map data provider.
- `addon/WoWForeverAP/UI/Panel.lua` — new: main window with tabs Checks, Items, Hints, Rules.
- `addon/WoWForeverAP/UI/Settings.lua` — new: options in the game's Settings panel.
- `addon/WoWForeverAP/Rules/Warnings.lua` — new: locked-zone and profession warnings.
- `addon/WoWForeverAP/Core/Checks.lua` — new, pure: open checks grouped by zone; zone lock state; allowed profession cap.
- `addon/WoWForeverAP/Core/DB.lua` — account-level `ui = { mapOverlay = true, zoneWarnings = true, panelPoint = {…} }`.
- `addon/WoWForeverAP/Commands.lua` — `/wfap` with no args opens the panel; `/wfap help` keeps help.
- `addon/WoWForeverAP/Locales/enUS.lua`, `deDE.lua` — strings.
- `addon/WoWForeverAP/WoWForeverAP.toc` — file list.
- `apworld/wow_forever/client/inbox.py`, `wow_client.py` — add `hints` to the inbox slot.
- `tools/gen_addon_data.py` — add `zoneParents` (continent uiMapID per zone) if `C_Map.GetMapInfo().parentMapID` is not enough at runtime (only if needed).
- Tests: `addon/spec/checks_spec.lua`, `addon/spec/warnings_spec.lua`, `tests/test_inbox.py` (extend), `tests/test_client_sync.py` (extend).

## Data
- Inbox slot gains `hints = { { item = "<name>", itemId = <int>, location = "<name>", finder = "<player>", receiver = "<player>", found = bool, ourItem = bool }, … }` (max 200 entries, newest first; strings escaped and capped by `lua_table.render`). Inbox schema stays 1 (new optional field; the addon treats missing as empty).
- SV: `WoWForeverAP_DB.ui` as above.

## Interfaces
- `Checks.zoneState(slot, uiMapID) -> "start"|"unlocked"|"locked"|"unavailable"` (unavailable = other faction or later release).
- `Checks.openByZone(slot) -> { {uiMapID, state, quests = {ids}}, … }` plus `Checks.openCharacter(slot) -> {levels = {…}, professions = {[line] = {skills}}}`.
- `Checks.allowedSkill(slot, skillLineID) -> int` (0 = profession locked; else `max_skill` of the highest unlocked tier).
- `Warnings`: on `ZONE_CHANGED_NEW_AREA` and `PLAYER_ENTERING_WORLD` resolve `C_Map.GetBestMapForUnit("player")`, walk `parentMapID` up to `Enum.UIMapType.Zone`; if `locked` → raid-warning text `L.ZONE_LOCKED` ("%s is locked: travel only — no quests, kills for XP, gathering or looting") once per entry. Inside instances: no warning in 003 (dungeons belong to 004's decision). On `SKILL_LINES_CHANGED`: profession learned while `allowedSkill == 0` → warning; rank above `allowedSkill` → warning once per rank.
- `MapOverlay`: provider on `WorldMapFrame`; on continent maps (`Enum.UIMapType.Continent`) draws one texture per data zone using `C_Map.GetMapRectOnMap(zone, continent)`; locked = tint, unlocked = none, unavailable = darker tint; on a zone map that is locked shows a top banner "Locked". Toggle via settings. Tooltip on hover: zone name, state, open check count.
- `Panel` (toggle via `/wfap`, addon compartment, keybinding-free): tabs
  - Checks: unlocked zones first, list of open quest checks (localised titles), then level and profession milestones; zero state "No open checks. Play, then /reload to sync."
  - Items: received items in order, localised names, sender; zero state.
  - Hints: hint list, ours first; zero state "No hints yet."
  - Rules: honor rules text + economy rules from 002.
  - Header line: linked slot, "%d checks waiting for /reload" when outbox is non-empty, inbox age ("data from 12 min ago").
  - Not linked: panel shows the link explanation and a "Link this character" button (calls 001 `Link`).

## Security and user data
Hint strings come from other players → escaped by the client (001) and shown with `SetText` only (never passed to `loadstring` or format strings as the format argument).

## UI
No design system exists; this proposal needs the programmer's approval before building (docs/ai/ui.md):
- Base: Blizzard's native frame templates and font objects, so the addon looks like part of the game. No custom textures except flat colour tints.
- Palette: neutral Blizzard frame + one accent `#D4A017` (gold, used for headers and the prefix). Semantics: locked = red tint `#8C2A2A` at 35 % alpha; unavailable = `#000000` at 55 %; unlocked = no tint; checked = grey text `#9D9D9D`; open = `HIGHLIGHT_FONT_COLOR`. Never colour alone: every state also has a text label in tooltips and lists.
- Type: `GameFontNormalLarge` (title), `GameFontNormal` (headers), `GameFontHighlight` (rows), `GameFontHighlightSmall` (meta). Four sizes.
- Spacing: 4/8/12/16/24. Rows 20 px. Window 420 × 520, movable, position saved, Esc closes (`UISpecialFrames`).
- Components: one button style (`UIPanelButtonTemplate`), Blizzard tabs, ScrollBox lists. One primary action per view (Link button only when unlinked).
- States per tab: empty, many items (scroll), long names (truncate with tooltip), not linked, no inbox yet ("Start the client and /reload").

## Steps
1. Get approval for the UI proposal above.
2. `Core/Checks.lua` + specs.
3. Client/inbox hints + Python tests.
4. `Rules/Warnings.lua` + specs (pure decision functions; event wiring thin).
5. `UI/Style.lua`, `UI/Panel.lua`, `UI/Settings.lua`, commands.
6. `UI/MapOverlay.lua`.
7. Locales, TOC, `CHANGELOG.md`.
8. Manual check in the live client (programmer): default, small UI scale, not-linked state, locked zone entered; screenshots in the PR.

## Tests
- `zoneState`: start, unlocked by item, locked, other faction, later release.
- `openByZone`: excludes checked and outbox ids; sorts unlocked first; empty slot → empty list.
- `allowedSkill`: 0 tiers → 0; 2 tiers → 150 (fixture tiers).
- Warnings: entering the same locked zone twice in a row warns once; unlocked zone never warns; skill above cap warns once per rank.
- Inbox hints: capped at 200; hostile strings rendered inert; missing hints in old inbox → empty list in Lua.

## Decisions for the programmer
- **UI proposal above** — approve, or name changes.
- **Map overlay precision.** (a) Rectangles from `C_Map.GetMapRectOnMap` (approximate, overlaps at zone borders). (b) Exact zone shapes via map highlight art (`C_Map.GetMapArtHighlightInfo`-style APIs, if present in Forever), more work and API-dependent. **Recommend (a)** first.

## Risks / follow-ups
- Map APIs (`GetMapRectOnMap`, data providers, `Enum.UIMapType`) are Mainline APIs; confirm with 001 D2.
- 12.x addon restrictions apply to combat and some protected frames; the panel must not open in combat if templates turn out to be protected (`InCombatLockdown()` check before showing).
