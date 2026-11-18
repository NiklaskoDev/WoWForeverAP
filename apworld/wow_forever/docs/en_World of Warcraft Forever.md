# World of Warcraft: Forever

## Where is the options page?

The [player options page for this game](../player-options) contains all the options you need to configure
and export a config file.

## What does randomization do to this game?

Zones and profession tiers are shuffled into the multiworld. You play World of Warcraft: Forever as usual, on
as many characters as you like, but every zone and every profession tier is **locked** until the item that
unlocks it arrives. What you do in the game sends out checks.

- **Items:** a zone unlock for every zone of your faction, and one *Progressive* item per profession (each
  copy unlocks the next tier). Then the *Care Package* items (see below). Everything else is filler.
  The item reference below describes every item.
- **Locations (checks):**
  - turning in a quest (a share of the quests your faction can do, set by `quest_weight`: 1-100 percent, default 25;
    the quest list of your seed shows which ones are checks. Class quests, race quests, repeatable quests,
    profession quests and quests in cities and dungeons are never checks),
  - reaching a character level (every `level_milestone_step` levels, and always the goal level),
  - reaching a profession skill (every `profession_milestone_step` points, up to the top tier of your content release),
  - the optional categories below (bosses, area discoveries, reputation, PvP).
- **Goal:** any linked character reaches the goal level (`goal_level`, 10-60, default 60).

The `goal_level` slider shortens the game: everything that needs a level above it is left out of the seed. That
is every zone that starts above the goal level, quests, reputation and PvP checks and dungeons whose level is above
it, and the profession tiers whose trainer level or material level is above it (a lower tier can stay when a higher
one is cut, never the other way round, so a low goal level may leave only the first tiers). A zone that
spans the goal level stays, with its lower quests. In the game, zones above the goal level show as "not in your
seed".

### Profession modes

`profession_mode` limits how many **primary** professions (Alchemy, Blacksmithing, Enchanting, Engineering,
Herbalism, Leatherworking, Mining, Skinning, Tailoring) the seed has. Secondary professions (Cooking, First Aid,
Fishing) are never limited: every one listed in `professions` is in.

| Mode | Primary professions |
|---|---|
| `all` (default) | every one listed in `professions` |
| `solo` | at most 2, what one character can learn |
| `team` | at most 2 per team member, `team_size` 2-4 (so 4, 6 or 8) |

`professions` stays the pool. When it lists no more primaries than the mode allows, those are used as listed, so
you can pick them yourself. When it lists more, the seed picks them at random. With the Auction House, trading,
mail and shared banks all off, only picks whose crafting professions can reach their gathering profession are
possible, and generation stops with a message when there is none. In team mode the seed does not say who takes
which profession: sort that out among yourselves.

`/start` in the client and `/wfap start` in the game show your faction, start zone, goal level and professions;
the spoiler log lists the same lines for every slot.

Your start zone is unlocked from the beginning (`start_zone`), and one more zone of your faction that covers
level 11 is sent early so you are never stuck. The logic assumes a character needs a zone that covers every five levels
on the way up (levels 1-5, 6-10, 11-15, and so on), so a gap in the zones you own blocks the levels above it.

## Extra check categories

Four optional categories add more checks. Each has an on/off option and a weight (1-100, default 100, except `discovery_weight`: 20): the
weight is the percentage of the category's eligible checks that are put into your seed, drawn with the seed's
random generator (at least one when any are eligible). Rows of a later content release and rows of the other
faction are never eligible.

| Category | Options (default) | A check is... |
|---|---|---|
| Boss | `boss_checks` (off), `boss_weight` | killing a dungeon boss (`ENCOUNTER_END` with a kill) |
| Discovery | `discovery_checks` (on), `discovery_weight` (20) | exploring a map area of a zone, for example "Discover Elwynn Forest: Crystal Lake" |
| Reputation | `reputation_checks` (off), `reputation_weight` | reaching Friendly, Honored, Revered or Exalted with a city or Steamwheedle Cartel faction |
| PvP | `pvp_checks` (off), `pvp_weight` | 100, 250, 500 and 1000 honorable kills, and a first win in Warsong Gulch, Arathi Basin and Alterac Valley |

- **Discoveries are many** (about 500 for a seed with every zone of your faction), so by default only 20% of them
  are included. Raise or lower `discovery_weight` to taste. Unlike reputation and PvP, an area you explored **before** linking still counts: the next time you
  stand in it the check is recorded, because the game does not say when an area was discovered.
- **Bosses:** a dungeon belongs to the zone with its entrance, so its bosses need that zone's unlock item and the
  dungeon's level; there are no separate dungeon unlock items. Raids (not part of the first release) would also
  need the goal level in the logic. Boss checks only exist for bosses whose encounter id is in the game data; the first
  data has none yet (see the README, "Unconfirmed"), so the category adds nothing until they are confirmed.
- **Reputation and PvP** only count progress made after the character was linked: the addon stores the standings
  and the honorable-kill total when you link, and a check needs a standing above that or kills beyond that total.
  A battleground win is counted when you win a match as the winning faction after linking.
- Group finder teleports into a dungeon are allowed only if the zone with the dungeon's entrance is unlocked.
- The Legacy System is not a check category.

## Economy and self-found rules

Five options decide how much help a character may get from other players and from your other characters:

| Option | Default | Meaning |
|---|---|---|
| `allow_auction_house` | on | Buying and selling at the Auction House |
| `allow_trading` | on | The trade window with other players |
| `allow_mail` | on | Sending and receiving items and gold by mail |
| `allow_shared_banks` | off | The guild bank and the account (warband) bank |
| `allow_main_boosts` | off | Dungeon carries and power levelling by a main character |

The first four change the logic of the profession checks. With **any** of them on, materials are assumed to be
obtainable from other players, so a profession skill check only needs the character level of its skill range.
With **all four off** you are self-found: every crafting profession must get its materials itself.

- Blacksmithing, Engineering: ore from Mining. Alchemy: herbs from Herbalism. Leatherworking: hides from
  Skinning. The gathering profession must be in your `professions` and its *Progressive* item must have
  unlocked the tier that reaches the material (for example Mining tier 3 for Mithril).
- Enchanting, Tailoring, Cooking, First Aid: the materials come from loot, so the character level of the skill
  range is enough.
- Mining, Herbalism, Skinning and Fishing need nothing.
- If a crafting profession needs a gathering profession that is not in `professions`, generation stops with a
  message that names both. Select the gathering profession or turn one of the four options on.

`allow_main_boosts` changes nothing in the logic. It only tells you whether a main may carry you through
dungeons or power-level you.

### Care Packages

`care_packages` (default 5) adds that many *Care Package* items to the item pool. Each one allows **one** pull
from a main character: up to `care_package_gold` gold (default 50) **or** `care_package_stacks` stacks of
materials (default 5). The logic never requires a Care Package, and they are the first items dropped if the
seed has fewer locations than items. In the game:

- `/wfap rules` shows the economy rules of your slot.
- `/wfap care` shows how many Care Packages are available (received minus used).
- `/wfap care use` asks for confirmation and counts one as used. It cannot go below zero.

The tool never moves gold or items. The count is only a reminder of what you agreed to.

## Several characters, one slot

Any number of characters can be linked to the same slot, on one account or on several accounts and PCs.
Checks from all of them are merged by the Archipelago server, and every unlock applies to every linked
character. A character only earns checks for what it does **after** it was linked: quests turned in, levels
gained, profession skill raised, reputation standings reached and honorable kills made from the moment of
linking.

## The honor system

The game cannot be locked by the tool, so the rules are yours to keep. They are shown in the game and in this
guide, nothing enforces them.

- **Locked zone:** do not quest, kill for experience, gather or loot there. Passing through (roads, flight
  paths, boats, the way to your next zone) is allowed.
- **Start zone:** one start zone per seed is open. Characters of other races travel to it first.
- **Locked profession tier:** do not train the tier before its *Progressive* item has arrived.
- **Economy windows:** when you open the Auction House, a mailbox, the trade window or a guild or account bank
  that your seed does not allow, the addon shows a warning. It cannot stop you: keeping to it is up to you.
- No gold, items or services are created for you by this tool. Items you receive are unlocks, not goods.

## How the game and Archipelago talk to each other

The tool stays inside Blizzard's rules: the addon only reads game state through the official in-game API, and
the Archipelago client never touches the running game. Information moves through two files, and only when
**you** reload or log out:

1. The addon records your checks in its saved data. The game writes that file on `/reload`, on logout and on
   exit.
2. The Archipelago client reads that file and sends the checks to the server.
3. The client writes the unlocks (and the list of what is already checked) into the small data addon
   `WoWForeverAP_Inbox`. The game loads it on your next `/reload` or login.

Nothing here sends keystrokes, reads game memory, watches network traffic or starts and stops the game.

## What do I see in the game?

Chat messages with the `[AP]` prefix: when a check is recorded ("N checks waiting - /reload or log out to
send them"), when items arrive after a reload, and when the goal is reached. The addon speaks English and
German (`/wfap help` lists its commands).

## Item reference

<!-- BEGIN GENERATED: item reference (python tools/gen_addon_data.py). Do not edit by hand. -->

Generated from the game data, like the item descriptions of this world. The data is provisional (see "Unconfirmed content").

### Zones

Each zone is one item, `Zone: <zone>`. Once it has arrived you may quest, kill for experience, gather and loot in the zone; before that, only travel through it.

| Item | Faction | Levels | Start zone | Dungeons | Release |
|---|---|---|---|---|---|
| Zone: Elwynn Forest | Alliance | 1-10 | yes |  | Launch |
| Zone: Dun Morogh | Alliance | 1-10 | yes | Gnomeregan | Launch |
| Zone: Teldrassil | Alliance | 1-10 | yes |  | Launch |
| Zone: Durotar | Horde | 1-10 | yes |  | Launch |
| Zone: Mulgore | Horde | 1-10 | yes |  | Launch |
| Zone: Tirisfal Glades | Horde | 1-10 | yes | Scarlet Monastery | Launch |
| Zone: Zephra's Isle | both factions | 1-12 | yes |  | Launch |
| Zone: Westfall | Alliance | 10-20 |  | The Deadmines | Launch |
| Zone: Darkshore | Alliance | 10-20 |  |  | Launch |
| Zone: Loch Modan | Alliance | 10-20 |  |  | Launch |
| Zone: Redridge Mountains | Alliance | 15-25 |  |  | Launch |
| Zone: Duskwood | Alliance | 18-30 |  |  | Launch |
| Zone: Wetlands | Alliance | 20-30 |  |  | Launch |
| Zone: Silverpine Forest | Horde | 10-20 |  | Shadowfang Keep | Launch |
| Zone: The Barrens | Horde | 10-25 |  | Wailing Caverns, Razorfen Kraul and Razorfen Downs | Launch |
| Zone: Ashenvale | both factions | 18-30 |  | Blackfathom Deeps | Launch |
| Zone: Stonetalon Mountains | both factions | 15-27 |  |  | Launch |
| Zone: Hillsbrad Foothills | both factions | 20-30 |  |  | Launch |
| Zone: Thousand Needles | both factions | 25-35 |  |  | Launch |
| Zone: Arathi Highlands | both factions | 30-40 |  |  | Launch |
| Zone: Alterac Mountains | both factions | 30-40 |  |  | Launch |
| Zone: Desolace | both factions | 30-40 |  | Maraudon | Launch |
| Zone: Stranglethorn Vale | both factions | 30-45 |  |  | Launch |
| Zone: Badlands | both factions | 35-45 |  | Uldaman | Launch |
| Zone: Swamp of Sorrows | both factions | 35-45 |  | The Temple of Atal'Hakkar | Launch |
| Zone: Dustwallow Marsh | both factions | 35-45 |  |  | Launch |
| Zone: The Hinterlands | both factions | 40-50 |  |  | Launch |
| Zone: Tanaris | both factions | 40-50 |  | Zul'Farrak | Launch |
| Zone: Feralas | both factions | 40-50 |  | Dire Maul | Launch |
| Zone: Searing Gorge | both factions | 43-50 |  |  | Launch |
| Zone: Azshara | both factions | 45-55 |  |  | Launch |
| Zone: Blasted Lands | both factions | 45-55 |  |  | Launch |
| Zone: Un'Goro Crater | both factions | 48-55 |  |  | Launch |
| Zone: Felwood | both factions | 48-55 |  |  | Launch |
| Zone: Burning Steppes | both factions | 50-58 |  |  | Launch |
| Zone: Western Plaguelands | both factions | 51-58 |  | Scholomance | Launch |
| Zone: Winterspring | both factions | 53-60 |  |  | Launch |
| Zone: Eastern Plaguelands | both factions | 53-60 |  |  | Launch |
| Zone: Silithus | both factions | 55-60 |  |  | Launch |
| Zone: Moonglade | both factions | 55-60 |  |  | Launch |
| Zone: Deadwind Pass | both factions | 55-60 |  |  | Launch |

### Professions

Each profession is one item, `Progressive <profession>`, with one copy per rank. Do not train a rank before its copy has arrived. Every profession has the same ranks:

| Copies | Rank | Skill cap | Trainer level | Logic level | Release |
|---|---|---|---|---|---|
| 1 | Apprentice | 75 | 5 | 5 | Launch |
| 2 | Journeyman | 150 | 10 | 15 | Launch |
| 3 | Expert | 225 | 20 | 30 | Launch |
| 4 | Artisan | 300 | 35 | 45 | Launch |

The logic level is the character level the logic needs for skill checks up to the rank's cap. A seed whose goal_level is below it leaves that rank and every later one out.

| Item | Kind | Self-found materials |
|---|---|---|
| Progressive Alchemy | primary | Herbalism |
| Progressive Blacksmithing | primary | Mining |
| Progressive Enchanting | primary | loot |
| Progressive Engineering | primary | Mining |
| Progressive Herbalism | primary | supplies Alchemy |
| Progressive Leatherworking | primary | Skinning |
| Progressive Mining | primary | supplies Blacksmithing and Engineering |
| Progressive Skinning | primary | supplies Leatherworking |
| Progressive Tailoring | primary | loot |
| Progressive Cooking | secondary | loot |
| Progressive First Aid | secondary | loot |
| Progressive Fishing | secondary | - |

"Self-found" means the Auction House, trading, mail and shared banks are all off.

### Other items

| Item | Description |
|---|---|
| Traveler's Tale | Filler: it unlocks nothing. It fills the locations left over after the unlocks and the Care Package items. |
| Care Package | Allows one pull from a main character: up to care_package_gold gold or care_package_stacks stacks of materials, as set in your options (care_packages sets how many are in the pool). The logic never needs it. In the game, /wfap care counts the ones received and used; the tool moves no gold or items. |

<!-- END GENERATED: item reference -->

## Unconfirmed content

Zone level ranges, profession skill-line ids and tier limits come from public Classic Era sources, and the
quests from the community-maintained AllTheThings database; all of it is still being confirmed against the live
Forever client. If
something in your seed does not match the game, please report it.
