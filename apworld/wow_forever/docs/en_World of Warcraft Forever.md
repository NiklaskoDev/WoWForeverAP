# World of Warcraft: Forever

## Where is the options page?

The [player options page for this game](../player-options) contains all the options you need to configure
and export a config file.

## What does randomization do to this game?

Zones and profession tiers are shuffled into the multiworld. You play World of Warcraft: Forever as usual, on
as many characters as you like, but every zone and every profession tier is **locked** until the item that
unlocks it arrives. What you do in the game sends out checks.

- **Items:** a zone unlock for every zone of your faction, and one *Progressive* item per profession (each
  copy unlocks the next tier). Everything else is filler.
- **Locations (checks):**
  - turning in a quest (see the quest list of your seed),
  - reaching a character level (every `level_milestone_step` levels, and always level 60),
  - reaching a profession skill (every `profession_milestone_step` points, up to the top tier of your content release).
- **Goal:** any linked character reaches level 60.

Your start zone is unlocked from the beginning (`start_zone`), and one more zone of your faction that covers
level 11 is sent early so you are never stuck. The logic assumes a character needs a zone that covers every five levels
on the way up (levels 1-5, 6-10, 11-15, and so on), so a gap in the zones you own blocks the levels above it.

## Several characters, one slot

Any number of characters can be linked to the same slot, on one account or on several accounts and PCs.
Checks from all of them are merged by the Archipelago server, and every unlock applies to every linked
character. A character only earns checks for what it does **after** it was linked: quests turned in, levels
gained and profession skill raised from the moment of linking.

## The honor system

The game cannot be locked by the tool, so the rules are yours to keep. They are shown in the game and in this
guide, nothing enforces them.

- **Locked zone:** do not quest, kill for experience, gather or loot there. Passing through (roads, flight
  paths, boats, the way to your next zone) is allowed.
- **Start zone:** one start zone per seed is open. Characters of other races travel to it first.
- **Locked profession tier:** do not train the tier before its *Progressive* item has arrived.
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

## Unconfirmed content

Zone level ranges, profession skill-line ids and tier limits, and the start-zone quests come from public
Classic Era sources and community guides and are still being confirmed against the live Forever client. If
something in your seed does not match the game, please report it.
