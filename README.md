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

## Data

Game data lives in `apworld/wow_forever/data/*.csv`. Rows marked provisional in their source comment
come from public Classic Era sources and must be confirmed in the live Forever client before the first
release. Each CSV names its source in a leading `#` comment line.

## Development

```
bash scripts/setup_ap.sh     # clone the pinned Archipelago release into .ap/ and link the apworld
pytest                       # Python tests
ruff check .                 # Python lint
bash scripts/ci.sh           # Lua lint/tests, generated-data check, packaging
```

Python 3.12 is what CI uses; Archipelago supports 3.11 to 3.13.

## License

MIT, see `LICENSE`.
