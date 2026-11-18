# 012 — hotfix: map overlay draws dark rectangles with the default "art" shape source

Status: implemented (live-client check of the default strips pending)
Version: 0.2.0 → 0.2.1
Gate (fix only · no API/format change · no migration or new dependency · ≤ 3 source files · no critical decision): holds — one source file (`Style.lua`); the switch to strips is the pre-approved fallback of plan 010 D2 ("highlight art with strip fallback and a switch to strips if the live check fails"); the live check failed.

Symptom: released v0.2.0 on live client 1.60.1, default `Style.MAP_SHAPE_SOURCE = "art"`: the world map overlay on Eastern Kingdoms shows dark, overlapping rectangles (darker where they overlap, no red tint). With `MAP_SHAPE_SOURCE = "runs"` and `/reload` the strip fallback draws non-overlapping zone-shaped fills (locked red, not-in-seed dark) as intended.
Repro: v0.2.0 addon, default Style, linked slot, open the Eastern Kingdoms world map.
Cause: `addon/WoWForeverAP/UI/MapOverlay.lua:126` dresses art textures with `SetBlendMode("BLEND")`, but Blizzard draws the `C_Map.GetMapHighlightInfoAtPosition` art with `alphaMode="ADD"` (`Blizzard_SharedMapDataProviders/MapHighlightDataProvider.xml:8` and `:13`): the art has an opaque black background meant to vanish under additive blending, so under `BLEND` each zone's whole art rectangle renders dark and neighbouring rectangles overlap. Additive blending only lightens, so the art cannot produce the approved dark/red fills under either mode. The default `addon/WoWForeverAP/UI/Style.lua:38` (`"art"`) routes every zone with art through this path (`MapOverlay.lua:79`, `usableArt`). (confirmed by: code reading of both files + the programmer's two live screenshots)
Fix:
- `addon/WoWForeverAP/UI/Style.lua:38` — `Style.MAP_SHAPE_SOURCE = "runs"`; update the comment at :36–37 to say "art" is kept but does not read as a fill on the live client (drawn additively, black background).
- `README.md:109–111` (docs, not counted as source) — in the "Map overlay zone shapes (plan 010)" Unconfirmed note, replace the open point about the art under `BLEND` with the live result: on client 1.60.1 the highlight art renders as dark rectangles (Blizzard draws it with `alphaMode="ADD"`), so the default is `"runs"`; strips confirmed to draw non-overlapping zone-shaped fills on Eastern Kingdoms. Leave the other open points unchanged except "whether the fills follow the zone borders without overlapping", which is confirmed for strips on Eastern Kingdoms.
- `CHANGELOG.md` — under `[Unreleased]` add `### Fixed`: the world map overlay draws zone-shaped fills (strips) by default instead of dark rectangles from the zone highlight art.
No change to `MapOverlay.lua`.

Regression test (write first, see it fail on the current default):
- `addon/spec/style_spec.lua:25` — change to `assert.equals("runs", Style.MAP_SHAPE_SOURCE)`.
- `addon/spec/map_overlay_spec.lua` — new case near :317, e.g. `it("draws strips, not art, with the default style even where the game has art", ...)`: set `arts[DUN_MOROGH]` (atlas) and `arts[DUROTAR]` (file with size, as in :298), `install()`, `provider():RefreshAllData()`, do NOT touch `ns.Style.MAP_SHAPE_SOURCE`; assert every `provider().items[i].kind == "run"`, `#shownTextures() == runCount()`, and no shown texture is desaturated. Fails today (art items appear), passes after the fix.

Existing art cases must keep exercising the art path: in `addon/spec/map_overlay_spec.lua` the tests at :275, :297 and :317 rely on the old default. Add `ns.Style.MAP_SHAPE_SOURCE = "art"` at the start of each (before `install()`); in :317 keep the later switch to `"runs"`. `Env.new()` in `before_each` (:114) rebuilds `ns`, so the setting does not leak between cases.

Affected — changed symbols, their direct callers/readers, shared data they write:
| Part | Covered by |
|---|---|
| `Style.MAP_SHAPE_SOURCE` default (`UI/Style.lua:38`) | `addon/spec/style_spec.lua:25` (updated) |
| `usableArt` reader (`UI/MapOverlay.lua:79`) → `zoneItems`, `dress`, `placeItem` | `addon/spec/map_overlay_spec.lua` new default-style case + strip cases (:234 ff., :333, :344) |
| Art path still reachable via explicit `"art"` (`dress` atlas/file branch, `placeItem` atlas/file) | `addon/spec/map_overlay_spec.lua:275`, `:297`, `:317` (set `"art"` explicitly) |
| Live rendering on Eastern Kingdoms and Kalimdor with the default style | manual: open both continent maps with a linked slot, default Style — zone-shaped fills, locked red, not-in-seed dark, no rectangles |
| README Unconfirmed note, CHANGELOG | manual: text matches the live result |

Decisions for the programmer: none
Follow-ups:
- Remove the art code path (`usableArt`, atlas/file branches of `dress`/`placeItem`, `MapShapes` art lookup via `C_Map.GetMapHighlightInfoAtPosition`, the `"art"` option, its specs and README API note) — deletes a feature, needs a plan.
- Strip mode visuals: blocky stair-step edges from the 160 x 107 sampling grid and fills over coastal water — sampling resolution / edge smoothing, separate plan.
