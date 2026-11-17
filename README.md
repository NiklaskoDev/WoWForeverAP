# WoWForeverAP

An [Archipelago](https://archipelago.gg) multiworld game for World of Warcraft: Forever. Zones and
profession tiers are shuffled into the item pool; quest turn-ins, character levels and profession
skill milestones are the checks. It doubles as a guided way to level alts and professions.

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

- **WoW-Pro Guides** ([Ludovicus-Maior/WoW-Pro-Guides](https://github.com/Ludovicus-Maior/WoW-Pro-Guides),
  licensed CC BY-NC-ND 3.0): the Forever leveling guides were used only as an id lookup for `quests.csv`
  (quest ids, quest titles and prerequisite chains) and for the Zephra's Isle level range. No guide text is
  copied. Credit to the WoW-Pro Guides authors.
- **WoW_ClassicUIResources** ([Hoizame/WoW_ClassicUIResources](https://github.com/Hoizame/WoW_ClassicUIResources)):
  Classic client UiMap and SkillLine tables, the source of zone and profession ids and names.
- **AllTheThings** ([ATTWoWAddon/AllTheThings](https://github.com/ATTWoWAddon/AllTheThings)): Forever map ids
  (used to cross-check zone ids, and for Zephra's Isle).
- Zone level ranges and profession tier limits are commonly published Classic Era values.

`addon/WoWForeverAP/Data/Generated.lua` is generated from these CSVs by `tools/gen_addon_data.py`; never edit
it by hand.

## Unconfirmed

Everything below was set without access to the live Forever client and **must be confirmed there before the
first release** (plan 001, decisions D1 and D2). Nothing here is hidden behaviour: each item is a value or a
data file that may turn out wrong.

Client facts (D2):

- **Interface numbers** `## Interface: 16001, 120105` in `addon/WoWForeverAP/WoWForeverAP.toc` and
  `addon/WoWForeverAP_Inbox/WoWForeverAP_Inbox.toc`. Both values were reported, neither is confirmed. Check
  with `/dump GetBuildInfo()` (the fourth value is the interface number).
- **Game folder name** of Forever under the WoW install (for example `_forever_`). Only mentioned as an example
  in the setup guide and the `/wowpath` hint; no code depends on it.
- **Mainline 12.x API.** The addon assumes the Mainline API (checked against the 12.1.5 UI source). Unconfirmed
  for the Forever client: `GetProfessions` / `GetProfessionInfo` (used for profession skill, fallback
  `C_TradeSkillUI.GetProfessionInfoBySkillLineID`), `C_TradeSkillUI.GetProfessionInfoBySkillLineID` and
  `C_Map.GetMapInfo` (localised names), `C_QuestLog.GetTitleForQuestID`, `C_Map.GetMapLevels` and
  `C_Map.GetBestMapForUnit` (capture mode), and the events `QUEST_TURNED_IN`, `PLAYER_LEVEL_UP`,
  `SKILL_LINES_CHANGED`. A missing profession API shows one chat warning; if the client is Classic-style, the
  `Detect/*` files change (`GetSkillLineInfo` is not implemented: it does not exist in 12.x).
- **`## AddonCompartmentFunc`** and the `StaticPopup` link prompt (button3 / `OnAlt`) are Mainline features.

Provisional data files:

- `zones.csv`: ids and names from the Classic UiMap table; level ranges and factions from published Classic
  Era values; Zephra's Isle (2521) from the WoW-Pro guides and AllTheThings. Cities, battlegrounds, dungeons and
  the other new Forever zones (Mount Hyjal 2482, Rivergladss 2548, Shendralas 2652) are not in the data yet.
- `quests.csv`: a small start-zone set from the WoW-Pro guides; `req_level` is 1 for every row.
- `professions.csv`: Classic SkillLine ids and the profession set.
- `profession_tiers.csv`: Classic ranks (75/150/225/300) and trainer level requirements, not machine-verified.
- `material_brackets.csv`: a game-design approximation, not game data; tune freely.
- `releases.csv`: only the launch release (2026-11-04) is confirmed. Later releases are added once their date
  is confirmed.
- `misc_items.csv`: our own filler ids; permanent once released.

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
python tools/build.py        # dist/wow_forever.apworld and dist/WoWForeverAP-<version>.zip
```

Python 3.12 is what CI uses; Archipelago supports 3.11 to 3.13.

## License

MIT, see `LICENSE`.
