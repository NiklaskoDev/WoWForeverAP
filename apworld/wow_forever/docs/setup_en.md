# World of Warcraft: Forever Setup Guide

## What you need

- World of Warcraft: Forever, installed and playable.
- [Archipelago](https://github.com/ArchipelagoMW/Archipelago/releases) (the same version the apworld was built
  for, see the apworld's `archipelago.json`).
- The two files of a release of this project: `wow_forever.apworld` and `WoWForeverAP-<version>.zip`.
  The release also has a `SHA256SUMS` file to check the downloads (`sha256sum -c SHA256SUMS` on Linux and macOS,
  `Get-FileHash` in PowerShell).

## Installing

### The apworld

Double-click `wow_forever.apworld` (the Archipelago Launcher installs it), or copy it into the `custom_worlds`
folder of your Archipelago installation. Restart the Launcher.

### The addons

1. Unzip `WoWForeverAP-<version>.zip`. It contains two folders: `WoWForeverAP` and `WoWForeverAP_Inbox`.
2. Copy **both** into the AddOns folder of your Forever installation: the game folder is the one that contains
   `Interface` and `WTF`: the `_forever_` subfolder of your World of Warcraft folder, so the
   result is `<game folder>/Interface/AddOns/WoWForeverAP` and `.../WoWForeverAP_Inbox`.
3. **Restart the game completely.** The game only discovers new addon folders at startup, a `/reload` is not
   enough. Check the addon list on the character selection screen: both addons must be enabled.

### The client

1. Open the Archipelago Launcher and start **World of Warcraft Forever Client**.
2. Tell it where the game is: `/wowpath <game folder>`, for example
   `/wowpath C:\Program Files (x86)\World of Warcraft\_forever_`. The path is saved in `host.yaml`.
3. Connect to the server with your slot name, as in any other Archipelago game.

## Playing

### Link a character

Log in with a character, after the client has connected at least once. If the inbox holds exactly one slot,
the addon asks whether to link the character. Otherwise use:

- `/wfap` opens the window (the same as clicking the addon in the minimap addon menu): open checks per zone,
  received items, hints and the rules. When the character is not linked it explains how and offers a button,
- `/wfap link` to link to the only slot, or `/wfap link <number>` to pick one from the list,
- `/wfap unlink` to remove the link,
- `/wfap status` for the linked slot, received items and open checks,
- `/wfap rules` for the economy rules of the slot (Auction House, trading, mail, shared banks, boosts),
- `/wfap care` for your Care Packages, and `/wfap care use` to spend one,
- `/wfap options` opens the addon options (also under Options > AddOns).

A character must be of the faction of the slot. If it is above level 1 the addon warns you: progress made
before linking does not count. Link as many characters as you like to the same slot.

### The play loop

1. **Play.** Quests you turn in, levels you reach and profession skill you raise become checks, and so do the
   bosses you kill, the map areas you explore, the reputation you earn and your PvP, when your seed has those
   categories. The addon tells you in chat when one is recorded.
2. **`/reload`** (or log out) when you want to send checks. The game writes its saved data now.
3. The client notices the new file within seconds and sends the checks. Look at the client window.
4. **`/reload` again** to receive what came back: the client has written the new unlocks, and the game reads
   them on the reload. The addon lists the new items in chat; `/wfap items` lists all of them.

Checks are only stored when the game writes its saved data. If the game crashes, checks since the last
`/reload` or logout are lost: reload now and then.

### Keep the rules

Locked zones and locked profession tiers are an honor system, see the game guide. Passing through a locked
zone is fine; questing, killing for experience, gathering and looting there is not. Do not train a profession
tier you have not unlocked. The economy rules work the same way: the addon warns when you open a window your
seed does not allow, but it cannot stop you.

The addon helps you keep the zone and profession rules without stopping you: on the world map locked zones are
tinted red and zones outside your seed dark, a locked zone's map shows a "Locked" banner, and a warning appears
when you enter a locked zone, learn a locked profession or train above your unlocked tier. The options turn the
map tint and the warnings off. Hints show in the window after the client has written them and you `/reload`.

## Client commands

- `/wowpath [folder]` shows or sets the game folder.
- `/sync` reads the addon's saved data and rewrites the inbox now.
- `/status` shows linked characters, checks waiting to be sent and the inbox file.

## Troubleshooting

- *"install the WoWForeverAP_Inbox addon first"*: the client cannot find
  `Interface/AddOns/WoWForeverAP_Inbox` under the path from `/wowpath`.
- *No slot found in the game*: the client has not written the inbox yet. Connect it, wait a few seconds, then
  `/reload`.
- *The addon does not appear*: the game was not restarted after copying the folders, or the addon list has
  "load out-of-date addons" turned off and the game's interface version differs from the addon's. Please report
  the interface version of your client (`/dump GetBuildInfo()`).
- *Checks do not arrive*: they only leave the game on `/reload`, logout or exit.
