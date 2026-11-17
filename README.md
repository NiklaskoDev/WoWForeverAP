# WoWForeverAP

An [Archipelago](https://archipelago.gg) multiworld game for World of Warcraft: Forever. Zones and
profession tiers are shuffled into the item pool; quest turn-ins, character levels and profession
skill milestones are the checks, plus optional dungeon bosses, map-area discoveries, reputation standings and
PvP milestones. It doubles as a guided way to level alts and professions.

Several characters (one account or many players) can link to one slot; their checks are merged by the
Archipelago server and unlocks apply to every linked character.

This project is not affiliated with, endorsed by or sponsored by Blizzard Entertainment. World of
Warcraft is a trademark of Blizzard Entertainment, Inc.

## Terms of Service boundary

Binding for the whole project:

- The addon uses only the official in-game Lua API. It never automates actions, never casts, moves,
  buys or sends anything for the player.
- The client never reads game memory, never touches network traffic, never sends keystrokes or input
  to the game, never triggers `/reload` and never starts or stops the game.
- Game to client: the client reads `WTF/Account/*/SavedVariables/WoWForeverAP.lua`, which the game
  writes on `/reload`, logout or exit.
- Client to game: the client writes only `Interface/AddOns/WoWForeverAP_Inbox/Inbox.lua`, which the
  game loads on the next player-initiated `/reload` or login. This is the same pattern as the TSM
  desktop app and WeakAuras Companion.
- Unlocks and restrictions are honor-system rules shown to the player. No in-game goods, gold or
  services are produced by the tool.

## Setup and play

Install guide: [`apworld/wow_forever/docs/setup_en.md`](apworld/wow_forever/docs/setup_en.md). Rules and what is
randomised: [`apworld/wow_forever/docs/en_World of Warcraft Forever.md`](apworld/wow_forever/docs/en_World%20of%20Warcraft%20Forever.md).
In short: play, `/reload`, the client sends your checks, `/reload` again to receive unlocks.

## Data and sources

Game data lives in `apworld/wow_forever/data/*.csv`; each file names its sources in leading `#` comment lines.

- **WoW_ClassicUIResources** ([Hoizame/WoW_ClassicUIResources](https://github.com/Hoizame/WoW_ClassicUIResources)):
  Classic client UiMap, SkillLine, Map, Faction and BattlemasterList tables, the source of zone, profession,
  instance, faction and battleground ids and names. The repository has no licence file; only Blizzard's ids and
  names are taken from it, no code or text. Credit to its author.
- **AllTheThings** ([ATTWoWAddon/AllTheThings](https://github.com/ATTWoWAddon/AllTheThings), MIT): Forever map ids
  (used to cross-check zone ids, and for Zephra's Isle) and, since plan 005, `quests.csv`: the file is generated
  from the Forever database (`.contrib/.db/forever/zones`) at the commit pinned in `tools/att_version.txt`
  (quest ids, titles, levels, prerequisites, faction and zones). The generator keeps the quests of the zones in
  `zones.csv` that characters of any race and class can do and leaves out class and race quests, repeatable
  quests, breadcrumbs, profession and reputation quests, quests that lock out others, and quests whose giver or
  objectives are in a city or dungeon (`tools/import_att.py`, plan 005). Its report lists every exclusion.
- **Extra check categories (plan 004).** `instances.csv`: instance ids and names from the Classic Map table
  (Hoizame), entrance zone and entry level from the Forever dungeon files of AllTheThings (`.contrib/.db/forever/dungeons & raids`).
  `discoveries.csv`: the exploration areas of the AllTheThings Forever database (`.config/exploration/*` and the
  `.config/.wago` AreaTable and UiMapAssignment exports). `reputations.csv`: Classic Faction table (Hoizame).
  `pvp.csv`: battleground map ids and minimum levels from the Classic Map and BattlemasterList tables (Hoizame).
  `encounters.csv` has no rows: no public source lists the encounter ids of the Classic dungeon bosses.
- Zone level ranges and profession tier limits are commonly published Classic Era values.

`addon/WoWForeverAP/Data/Generated.lua` is generated from these CSVs by `tools/gen_addon_data.py`; never edit
it by hand.

## Unconfirmed

Everything below was set without access to the live Forever client and **must be confirmed there before the
first release** (plan 001, decisions D1 and D2). Nothing here is hidden behaviour: each item is a value or a
data file that may turn out wrong.

Client facts (D2):

- Confirmed 2026-11-17 by the programmer: the Forever game folder is `_forever_` inside the World of Warcraft
  install (for example `D:\World of Warcraft\_forever_`). No code depends on it; the client uses the folder set with `/wowpath`.
- Confirmed 2026-11-17 by the programmer in the live Forever client: `GetBuildInfo()` returns "1.60.1", "70938",
  "Nov 12 2026", 16001, so both TOCs declare `## Interface: 16001` (the addon targets Forever only). `GetProfessions()`
  exists and returned 5 slot indices (the addon reads up to 6 positions).
- Confirmed 2026-11-17 by the programmer in the live Forever client: `GetProfessionInfo(index)` returns the rank as
  3rd and the skill line id as 7th value (e.g. Tailoring: rank 135, skill line 197), as the addon reads them.
- **Rest of the API.** Forever (build 1.60.1, interface 16001) shares the Mainline API shape; every call was checked
  against Blizzard's 12.1.5 UI source. `GetProfessions` and `GetProfessionInfo` are confirmed in the live client (above);
  still unconfirmed there: `C_TradeSkillUI.GetProfessionInfoBySkillLineID` (profession fallback and localised
  profession names), `C_Map.GetMapInfo` (localised zone names), `C_QuestLog.GetTitleForQuestID`, `C_Map.GetMapLevels` and
  `C_Map.GetBestMapForUnit` (capture mode), and the events `QUEST_TURNED_IN`, `PLAYER_LEVEL_UP`,
  `SKILL_LINES_CHANGED`. A missing profession API shows one chat warning; if the client is Classic-style, the
  `Detect/*` files change (`GetSkillLineInfo` is not implemented: it does not exist in 12.x).
- **Economy warnings (plan 002).** Checked against the Gethe/wow-ui-source mirror (live branch, 12.x),
  unconfirmed for the Forever client: the event `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` and
  `Enum.PlayerInteractionType` members `Auctioneer`, `MailInfo`, `TradePartner`, `GuildBanker` and
  `AccountBanker`; `C_EventUtils.IsEventValid`; `UIErrorsFrame:AddMessage`. When the enum or the event is
  missing the addon falls back to `AUCTION_HOUSE_SHOW`, `MAIL_SHOW`, `TRADE_SHOW` and `GUILDBANKFRAME_OPENED`
  (no fallback exists for the account bank) and skips an event the client refuses to register.
- **In-game UI (plan 003).** Checked against the same 12.x mirror, unconfirmed for the Forever client:
  `ButtonFrameTemplate`, `PanelTabButtonTemplate`, `WowScrollBoxList`, `MinimalScrollBar`, `UIPanelButtonTemplate`,
  `CreateScrollBoxListLinearView`, `ScrollUtil.InitScrollBoxListWithScrollBar`, `CreateDataProvider`,
  `PanelTemplates_SetNumTabs` / `PanelTemplates_SetTab`, `ButtonFrameTemplate_HidePortrait` (a missing template
  makes `/wfap` print one chat line instead of opening the window); `WorldMapFrame:AddDataProvider` with
  `MapCanvasDataProviderMixin` and `RegisterDataProviderOnUpdate`, `C_Map.GetMapChildrenInfo`,
  `C_Map.GetMapRectOnMap` (returns left, right, top, bottom), `Enum.UIMapType` (the overlay is skipped when
  one is missing); `RaidWarningUtil.AddMessage` (falls back to the deprecated `RaidNotice_AddMessage`, then
  `UIErrorsFrame`, then chat); `Settings.RegisterVerticalLayoutCategory` / `RegisterProxySetting` /
  `CreateCheckbox` / `RegisterAddOnCategory` / `OpenToCategory` (without them the options stay at their
  defaults); the events `ZONE_CHANGED_NEW_AREA` and `PLAYER_ENTERING_WORLD`. Also unconfirmed: how the map
  tints look (zone rectangles overlap at borders, frame level above the map art and below pins) and that the
  window may open in combat (it has no protected frames).
- **Extra check categories (plan 004).** Checked against the Gethe/wow-ui-source mirror (live branch, 12.1.5),
  unconfirmed for the Forever client: the event `ENCOUNTER_END` (payload encounterID, encounterName,
  difficultyID, groupSize, success; the addon reads encounterID and success and ignores anything that is not a
  kill); `C_MapExplorationInfo.GetExploredAreaIDsAtPosition(uiMapID, position)` (read with the position from
  `C_Map.GetPlayerMapPosition`, as Blizzard's `MapUtil` does) and `C_Map.GetAreaInfo` for the events
  `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS` and `ZONE_CHANGED_NEW_AREA`; the event `UPDATE_FACTION` and
  `C_Reputation.GetFactionDataByID(id).reaction` (4 neutral, 5 friendly ... 8 exalted); `GetPVPLifetimeStats()`
  (first return: lifetime honorable kills) and the event `PLAYER_PVP_KILLS_CHANGED`; the battleground winner from
  `PVP_MATCH_COMPLETE(winner)` (0 Horde, 1 Alliance; documented in 12.x) and from `UPDATE_BATTLEFIELD_STATUS` plus
  `GetBattlefieldWinner()` (used by Blizzard's UI but not in the generated API documentation); the battleground
  is the instance id `GetInstanceInfo()` returns. Every one of them is guarded: a missing or failing API means no
  check, never an error. An event the client does not know is skipped (`C_EventUtils.IsEventValid`). Also
  unconfirmed: that `ENCOUNTER_END` fires for the Classic dungeon bosses of Forever at all, and that the 12.x
  "secret value" restrictions leave its payload readable.
- **`## AddonCompartmentFunc`** and the `StaticPopup` link prompt (button3 / `OnAlt`) are Mainline features.

Provisional data files:

- `zones.csv`: ids and names from the Classic UiMap table; level ranges and factions from published Classic
  Era values; Zephra's Isle (2521) from AllTheThings (its 1-12 range is provisional: ATT's quest levels there are
  2-8). Cities, battlegrounds, dungeons and the other new Forever zones (Mount Hyjal 2482, Rivergladss 2548,
  Shendralas 2652) are not in the data yet. `tools/import_att.py` cross-checks the level ranges against ATT's quest
  levels in its report (it is a minimum level, so zone maxima are only a lower bound) and changes nothing.
- `quests.csv`: generated from the AllTheThings Forever database (about 1,700 quests, 1,000 to 1,100 per faction), which is
  community-maintained and partly unverified for Forever; the ids, levels, prerequisites and the leaving-out rules
  need a check in the live client. `req_level` is ATT's minimum level (the zone's minimum when ATT has none).
  Prerequisites with several alternatives are read as all-required. Quests in cities and dungeons, class and race
  quests are not in the data until a later plan adds those zones or options.
- `professions.csv`: Classic SkillLine ids and the profession set.
- `profession_tiers.csv`: Classic ranks (75/150/225/300) and trainer level requirements, not machine-verified. The
  ATT report confirms the rank names and the skill at which each rank is learnable; ATT has no character-level
  requirement for a tier, so `required_level` stays a design value.
- `material_brackets.csv`: a game-design approximation, not game data; tune freely.
- `releases.csv`: only the launch release (2026-11-04) is confirmed. Later releases are added once their date
  is confirmed.
- `instances.csv`: Classic Era dungeons with an entrance in a zone of `zones.csv` (14 rows); entry levels are
  ATT's recommended levels. Left out: Ragefire Chasm and The Stockade (city entrances), Blackrock Depths and
  Spire, Stratholme, the new Forever instances and **all raids** (their release date, 9 Dec 2026, has a single
  source and is unconfirmed; `releases.csv` has no later release yet).
- `encounters.csv`: **empty**. The `ENCOUNTER_END` ids of the Classic dungeon bosses are not in any public
  source (the Classic DungeonEncounter table holds raid bosses only; ATT's encounter ids are Encounter Journal
  ids). Capture them in the live client with `/wfap capture on`, kill the bosses, then
  `python tools/import_capture.py <WoW folder>` writes `data_capture/encounters.csv` for review. Until then the
  boss category adds no checks.
- `discoveries.csv`: 615 exploration areas taken from the ATT Forever exploration data (a mix of points harvested
  in the game and positions estimated from the WorldMapOverlay table); each area is on the zone map of its
  top-level parent area. Whether every one of them can be discovered by walking is unconfirmed.
- `reputations.csv`: twelve Classic factions (the capital cities, Gnomeregan Exiles, Darkspear Trolls and the four
  Steamwheedle Cartel towns); the home zone and the level per standing are a game-design approximation, not game
  data. Whether Forever has the same faction set is unconfirmed.
- `pvp.csv`: game-design milestones (honorable kills) and the three Classic battlegrounds; whether battlegrounds
  are open at launch is unconfirmed (the category is off by default).
- `profession_materials.csv`: a game-design approximation (which source supplies the main material of each
  crafting profession per skill bracket, and the gathering skill it needs), not game data; tune freely.
- `misc_items.csv`: our own filler and care package ids; permanent once released.

The dev capture mode (`/wfap capture on`, then `python tools/import_capture.py <WoW folder>`) logs zones
and quests in the live client into review CSVs in `data_capture/`; it is the intended way to replace the
provisional rows. Plan 001 step 16 (a manual live-client run: link, turn in a quest, `/reload`, check sent,
inbox written, `/reload`, item shown) is also still open.

## Development

```
bash scripts/setup_ap.sh     # clone the pinned Archipelago release into .ap/ and link the apworld
pytest                       # Python tests
ruff check .                 # Python lint
bash scripts/ci.sh           # Lua lint/tests (luacheck, busted), generated-data check, packaging
python tools/gen_addon_data.py   # regenerate addon/WoWForeverAP/Data/Generated.lua after changing a CSV
bash scripts/fetch_att.sh    # clone AllTheThings at the commit in tools/att_version.txt into .att/ (dev only)
python tools/import_att.py   # regenerate quests.csv from it; the review report goes to data_capture/att_report.txt
python tools/import_att.py --check   # exit 1 when quests.csv differs from what the import would write
python tools/build.py        # dist/wow_forever.apworld and dist/WoWForeverAP-<version>.zip
```

Python 3.12 is what CI uses; Archipelago supports 3.11 to 3.13.

`quests.csv` is generated, never edited by hand. To update it from AllTheThings: put the new commit hash into
`tools/att_version.txt`, run `bash scripts/fetch_att.sh` and `python tools/import_att.py`, review the `quests.csv`
diff and the report, and note the exclusion counts per reason in the pull request. CI does not fetch ATT; a test
only checks that the CSV header names the pinned commit. ATT is read as data by `tools/att_lua.py`; its Lua is
never executed, and nothing from ATT is needed to play.

## License

MIT, see `LICENSE`. Data derived from AllTheThings (MIT) and other sources is covered by
[`apworld/wow_forever/THIRD_PARTY_NOTICES.md`](apworld/wow_forever/THIRD_PARTY_NOTICES.md), which is packed into the apworld.
