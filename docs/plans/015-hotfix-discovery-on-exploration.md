# 015 — hotfix: discovery checks on first exploration

Status: implemented (live-client check pending)
Version: 0.3.1 → 0.3.2
Gate (fix only · no API/format change · no migration or new dependency · ≤ 3 source files · no critical decision): holds (1 source file plus CHANGELOG; no SavedVariables, data-format or generated-data change)

Symptom: since discovery checks shipped, seen live on client 1.60.1 with the released 0.3.1 addon: "Exploring isn't completing the check". Walking into a never-explored area that the seed lists as an open "Discover <zone>: <area>" check records nothing.
Repro: linked character, seed with discovery checks; walk into an area that is listed as an open discovery check and that the character has never explored.
Cause: `addon/WoWForeverAP/Detect/Discovery.lua:52-54`. `Discovery.scan` only runs on `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS` and `ZONE_CHANGED_NEW_AREA`. When the player enters a new area, the zone event fires before the client marks the area explored. `GetExploredAreaIDsAtPosition` does not list it yet, so the scan finds nothing. The explored flag comes afterwards with `MAP_EXPLORATION_UPDATED`, and the addon does not listen for that event. The area is only counted when the player enters it again later. Confirmed by code reading of the 12.1.5 UI source:
- `Blizzard_APIDocumentationGenerated/MapExplorationDocumentation.lua:46-51` declares `MAP_EXPLORATION_UPDATED` (SynchronousEvent, no payload).
- `Blizzard_SharedMapDataProviders/MapExplorationDataProvider.lua:17-29` refreshes the explored overlays on that event and not on zone events.
- `Blizzard_WorldMap/MapTexturePreloader.lua:17,25` does the same.

The source does not show the exact order of the zone event and the exploration update. That order is inferred from Blizzard listening for the separate event. The live order is a manual check (see below).
Fix: `addon/WoWForeverAP/Detect/Discovery.lua:52-54`: keep the three `ns.Events.register` calls and add `ns.Events.tryRegister("MAP_EXPLORATION_UPDATED", Discovery.scan)` after the loop. This is the same guarded pattern as `Detect/Encounters.lua:31`, so a client that does not know the event skips it without an error. Also update the header comment at lines 1-2 to name the new trigger. The doc comment at lines 40-41 stays as it is.
- `CHANGELOG.md` `[Unreleased]` → `### Fixed`: "Discovering a new map area records its "Discover <zone>: <area>" check right away; before, it only counted after leaving and re-entering the area."
- No change to `Capture.lua` (dev capture mode). See Follow-ups.

Regression test: `addon/spec/detect_discovery_spec.lua`, add `describe("on map exploration", ...)` after "on a zone event":
1. "records a listed area when the client marks it explored". Call `standing({})` and `ns.Events.dispatch("ZONE_CHANGED")`. The outbox is `{}`, because the area is not explored yet. Then call `standing({ CRYSTAL_LAKE })` and `ns.Events.dispatch("MAP_EXPLORATION_UPDATED")`. `Linked.outbox(db)` equals `{ areaId(CRYSTAL_LAKE) }` and the first chat line is `CHECK_RECORDED:format("Discover Crystal Lake")`. This fails today because no handler is registered for the event, so the outbox stays empty.
2. "does nothing for an area the seed does not list or an unlinked character". `standing({ MOONBROOK })` + dispatch → empty outbox. Then `standing({ CRYSTAL_LAKE })`, set `db.characters[game.guid].slotKey = nil`, and dispatch → empty outbox.
3. "loads without the event when the client rejects it". Set `_G.C_EventUtils = { IsEventValid = function(event) return event ~= "MAP_EXPLORATION_UPDATED" end }` before the addon environment is built, as in `detect_pvp_spec.lua:268`; follow that file for how the env is rebuilt. Then: there is no error, `game.errors` is `{}`, and `ZONE_CHANGED` with `standing({ CRYSTAL_LAKE })` still records the check.

Affected — changed symbols, their direct callers/readers, shared data they write:
| Part | Covered by |
|---|---|
| `Discovery.scan` on `MAP_EXPLORATION_UPDATED` (new trigger) | `addon/spec/detect_discovery_spec.lua` "on map exploration": cases 1-2 (add) |
| `Discovery.scan` on the three ZONE_CHANGED* events (unchanged) | `addon/spec/detect_discovery_spec.lua` "on a zone event" (existing) |
| Duplicate recording when the zone event and the exploration event both see the area | `addon/spec/detect_discovery_spec.lua:100-106` "records an area only once" (existing); add one line to case 1: dispatching `MAP_EXPLORATION_UPDATED` a second time leaves the outbox unchanged |
| `Tracker.recordForPlayer` / `Tracker.playerContext` (outbox SavedVariables write, chat line) | existing discovery cases above; no change to Tracker |
| `Discovery.exploredAreaIds` (shared with `Detect/Capture.lua:105` `Capture.onAreaChanged`) | unchanged; `addon/spec/detect_discovery_spec.lua` "exploredAreaIds" (existing) + the Capture spec (existing, no change) |
| `Events.tryRegister("MAP_EXPLORATION_UPDATED")` on a client that rejects the event | `addon/spec/detect_spec.lua:38-60` "tryRegister" (existing, generic) + case 3 (add) |
| In-game behaviour | manual: with `/console scriptErrors 1`, walk a linked character into a never-explored area that the Checks tab lists as an open discovery. The "Check recorded: Discover …" chat line appears within a moment of the map uncovering it, without leaving the area. No Lua errors. |

Decisions for the programmer: none
Follow-ups / manual checks (other causes to rule out if the fix does not help; not fixes):
- Is the area in the seed at all? With the default `discovery_weight` of 20, only about a fifth of all areas become checks. Check that the area appears as an open "Discover …" row in `/wfap` → Checks before walking in. If it is missing, this is expected behaviour, not a bug.
- Do the area ids from ATT (`apworld/wow_forever/data/*.csv`) match the ids the client reports? With dev capture mode on, walk into the area. Compare the area id that `Capture.onAreaChanged` logs against the id behind the seed's location for that area. A mismatch is a data bug and needs a normal plan.
- `Capture.onAreaChanged` (`Detect/Capture.lua:114-116`) has the same blind spot for newly explored areas. Adding `MAP_EXPLORATION_UPDATED` there is a separate dev-tool change, so it is not part of this hotfix.
