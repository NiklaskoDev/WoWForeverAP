# 010 — World map overlay with real zone shapes

Status: implemented (live-client visual check pending)
Type: feature
Version impact: minor — visual overhaul of an existing addon feature, no format change. Part of 0.2.0 with 008 and 009; no release without the programmer's word.
Depends on: 008 only for the "above the goal level" state, which already arrives as `"unavailable"` from `Checks.zoneState`; can be built in parallel otherwise.

## Goal
On continent maps, locked and not-in-seed zones are filled in their real zone shapes instead of overlapping rectangles, so no two fills ever overlap; the visual language for unlocked / start / locked / not-in-seed is clean and consistent, and the zone map of a not-in-seed zone gets its own banner. Tooltip hit-testing uses the game's own zone lookup instead of "smallest rectangle".
Out of scope: drawing on zone maps beyond the banner, minimap, a map legend frame.

## Reuse
- `UI/MapOverlay.lua` provider structure (`MapCanvasDataProviderMixin`, `RefreshAllData`, `OnCanvasSizeChanged`, `OnUpdate` tooltip, `drawBanner`, `install`, `refresh`), `Checks.zoneState`, `Checks.openByZone`, `Style.stateTint`, `Style.STATE_LABEL_KEYS`, `MapOverlay.tooltipLines`, setting `ns.db.ui.mapOverlay`, `ns.tryCall`.
- Blizzard does the same two things on continent maps, and the plan copies their API use (12.1.5 UI source):
  - zone under a point: `C_Map.GetMapInfoAtPosition(mapID, x, y)` → `UiMapDetails` (`Blizzard_SharedMapDataProviders/AreaLabelDataProvider.lua:78`, `Blizzard_MapCanvas/Blizzard_MapCanvas.lua:1002`);
  - zone shape art: `C_Map.GetMapHighlightInfoAtPosition(mapID, x, y)` → `fileDataID, atlasID, texPercentageX, texPercentageY, textureX, textureY, scrollChildX, scrollChildY` and its placement math (`Blizzard_SharedMapDataProviders/MapHighlightDataProvider.lua:49-95`). Both documented in `Blizzard_APIDocumentationGenerated/MapDocumentation.lua` (`MayReturnNothing`).
- New file `UI/MapShapes.lua`: sampling and art lookup are game-API geometry with a cache; `MapOverlay.lua` keeps view/drawing/provider. One line why: it keeps both files small and lets the geometry be tested without a provider.

## Code layout
- `addon/WoWForeverAP/UI/MapShapes.lua` (new) — per continent, once per session: zone partition by sampling (`runs`) and per-zone highlight art; cached.
- `addon/WoWForeverAP/UI/MapOverlay.lua` — continent view uses `MapShapes.forContinent`; draws art or runs; tooltip via `MapShapes.zoneAt`; banner for locked **and** not-in-seed zone maps. `zoneRects`/rectangle `zoneAt` and `GetMapRectOnMap`/`GetMapChildrenInfo` use are removed.
- `addon/WoWForeverAP/UI/Style.lua` — tokens per D1 (fill colours/alphas, banner colours), `Style.MAP_SHAPE_SOURCE` (D2).
- `addon/WoWForeverAP/WoWForeverAP.toc` — `UI\MapShapes.lua` before `UI\MapOverlay.lua`.
- `addon/WoWForeverAP/Locales/enUS.lua`, `deDE.lua` — `MAP_UNAVAILABLE_BANNER` ("Not in your seed" / "Nicht in deinem Seed"); `OPT_MAP_OVERLAY_TIP` reworded to the new look.
- `addon/spec/helpers/wow_stub.lua` — texture stubs: `SetTexture`, `SetAtlas`, `SetTexCoord`, `SetVertexColor`, `SetDesaturated`, `SetBlendMode` (record calls).
- `addon/spec/map_overlay_spec.lua` — rewritten for the new geometry; new `addon/spec/map_shapes_spec.lua`.
- `README.md` "Unconfirmed" — replace the `GetMapRectOnMap`/`GetMapChildrenInfo` entry with the new APIs (below).
- `CHANGELOG.md` — `[Unreleased]` → Changed.

## Data
None. Cache lives in a Lua upvalue for the session (not SavedVariables).

## Interfaces
`MapShapes` (all game calls through `ns.tryCall`, every return type-checked; anything missing → empty result, map unchanged):
- Constants `MapShapes.COLUMNS = 160`, `MapShapes.ROWS = 107` (continent canvases are about 3:2; cell ≈ 0.6 % of the map).
- `MapShapes.sampleRuns(continentMapId) -> { [uiMapId] = { { row, first, last }, ... } }` — for every cell centre `x = (col - 0.5) / COLUMNS`, `y = (row - 0.5) / ROWS`: `info = C_Map.GetMapInfoAtPosition(continentMapId, x, y)`; keep `info.mapID` only when `ns.Data.zones[info.mapID]` exists and `info.mapID ~= continentMapId`; consecutive cells of one row with the same id merge into one run. Returns `{}` when the API is missing or errors on the first call (stop sampling).
- `MapShapes.highlightArt(continentMapId, x, y) -> art | nil` — calls `C_Map.GetMapHighlightInfoAtPosition`; returns nil unless `(fileDataID > 0) or atlasID`; else `{ file = fileDataID or nil, atlas = atlasID or nil, texRight = texPercentageX, texBottom = texPercentageY, width = textureX, height = textureY, left = scrollChildX, top = scrollChildY }` (normalised values exactly as returned).
- `MapShapes.forContinent(continentMapId) -> { [uiMapId] = { runs = {...}, art = art | nil } }` — cached per continent id. For each zone in `sampleRuns`, the probe point is the centre of its longest run (always inside the zone); `art = highlightArt(continent, probeX, probeY)`. A completed sampling is cached even when it finds no data zones; only a missing or erroring API is not cached (retry next open) — amended after review.
- `MapShapes.zoneAt(continentMapId, x, y) -> uiMapId | nil` — `GetMapInfoAtPosition` at the cursor; nil unless it is a data zone other than the continent.
- `MapShapes.reset()` — clears the cache (specs only).

`MapOverlay`:
- `MapOverlay.view(mapId, slot, pending)` — continent: `{ kind = "continent", zones = { [uiMapId] = { uiMapId, state, tint, open, shape } } }` for every zone in `MapShapes.forContinent(mapId)`; zone map: `{ kind = "zone", banner = text, tone = "locked" | "unavailable" }` for a zone whose state is `locked` (`MAP_LOCKED_BANNER`) or `unavailable` (`MAP_UNAVAILABLE_BANNER`); else nil.
- Drawing per zone with a tint (texture pool `self.textures`, reused, surplus hidden):
  - Art (when `Style.MAP_SHAPE_SOURCE == "art"` and `shape.art`): one texture, `SetBlendMode("BLEND")`, `SetDesaturated(true)`, `SetVertexColor(tint.r, tint.g, tint.b, tint.a)`, `SetTexCoord(0, texRight, 0, texBottom)`. Atlas: `SetAtlas(atlas, true)`, anchor `CENTER` of the overlay at `((left + 0.5 * width) - 0.5) * W`, `-((top + 0.5 * height) - 0.5) * H`. File: `SetTexture(file)`, size `width * W` × `height * H`, `TOPLEFT` at `left * W`, `-top * H`. (`W`, `H` = canvas size; the overlay covers the canvas like Blizzard's canvas-sized highlight pin.)
  - Runs (otherwise): one `SetColorTexture(tint)` texture per run, `TOPLEFT` at `(first - 1) / COLUMNS * W`, `-(row - 1) / ROWS * H`, size `(last - first + 1) / COLUMNS * W` × `H / ROWS`.
  - `OnCanvasSizeChanged` re-places with the same math.
- `OnUpdate` hover: `MapShapes.zoneAt(mapId, x, y)` → `self.zones[id]` → `tooltipLines` (unchanged lines).
- Banner: `drawBanner(self, text, tone)` colours the background with `Style.COLORS.locked` or `Style.COLORS.unavailableBanner` at `Style.BANNER_ALPHA`.

New game APIs (add to README "Unconfirmed"; all guarded): `C_Map.GetMapInfoAtPosition`, `C_Map.GetMapHighlightInfoAtPosition`, texture `SetAtlas`, `SetTexCoord`, `SetVertexColor`, `SetDesaturated`, `SetBlendMode`, and whether the highlight art has an alpha channel that reads as a fill under `BLEND` (it is drawn with `alphaMode="ADD"` by Blizzard).

## Security and user data
None.

## UI
Design proposal for approval (D1), using the existing tokens of plan 003 (neutral Blizzard frame, one gold accent, flat fills, text labels for every state):
- **Unlocked and start zone:** no fill — the map stays as the game draws it where you may play. Tooltip says "start zone" / "unlocked".
- **Locked:** the zone shape filled with the existing muted red `#8C2A2A` at 45 % (up from 35 %: shapes no longer stack, so one layer must read alone).
- **Not in your seed (other faction, later release, above the goal level):** the zone shape filled with a neutral near-black `#141414` at 65 % — "absent", clearly darker and colourless next to locked red, distinct in luminance for colour-blind players.
- **Hover:** Blizzard's own zone highlight glow stays on top; our tooltip lists name, state label, open checks.
- **Zone maps:** existing red "Locked: travel only" banner; new neutral banner "Not in your seed" in `#141414` at the banner alpha, same size/position/font.
- No legend frame, no outlines, no animation.
States handled: overlay off (nothing drawn), not linked / no slot (nothing), API missing (nothing, as today), zone without art (runs fallback), continent without data zones (nothing).

## Steps
1. Texture stubs in `wow_stub.lua`.
2. `MapShapes.lua` with `sampleRuns`, `highlightArt`, `forContinent`, `zoneAt`, `reset`; TOC entry; `map_shapes_spec.lua`.
3. `Style.lua` tokens per the approved D1 values: `COLORS.locked` alpha, `COLORS.unavailable` → `141414` / 0.65, `COLORS.unavailableBanner`, `MAP_SHAPE_SOURCE` per D2.
4. `MapOverlay.lua`: new view, art/runs drawing, re-placing, hover via `zoneAt`, banner tones; delete `zoneRects` and rectangle `zoneAt`; update the header comment (APIs used).
5. Locale keys (both files), `OPT_MAP_OVERLAY_TIP` ("Fills locked zones red and zones outside your seed dark on continent maps.").
6. README "Unconfirmed", `CHANGELOG.md`.
7. Specs; `luacheck addon`, `bash scripts/ci.sh`.
8. Manual (programmer, live client): open Eastern Kingdoms and Kalimdor with a slot that has locked, unlocked and other-faction zones; check (a) fills follow zone borders and never overlap, (b) art mode looks like a fill and not a glow or a rectangle — if not, set `MAP_SHAPE_SOURCE = "runs"` and recheck, (c) the first open of a continent does not hitch noticeably, (d) tooltip matches the zone under the cursor, (e) banners on a locked and on an other-faction zone map. Record the results in README "Unconfirmed".

## Tests
`map_shapes_spec.lua` (stub `GetMapInfoAtPosition`: x < 0.5 → zone 1429, x ≥ 0.5 → 1411, a band at the top → a city id not in Data, bottom row → the continent id itself):
- `sampleRuns` gives one run per row for each zone, merged across the full half; the city and the continent id produce no runs.
- API missing, or erroring → `{}`; erroring stops after the first call.
- `forContinent` caches: a second call makes no API calls, also for a continent whose sampling worked but found no data zones; a missing or erroring API is not cached and retries.
- Probe point is the centre of the longest run (assert the coordinates passed to `GetMapHighlightInfoAtPosition`).
- `highlightArt`: nothing / `fileDataID == 0` without atlas → nil; atlas and file cases map the returned values.
- `zoneAt`: data zone → id; city, continent, nil info, API error → nil.
`map_overlay_spec.lua`:
- Continent view: states and tints per zone (start/unlocked no tint, locked red, unavailable dark); zone above `goalLevel` comes out unavailable.
- Art mode: one texture per tinted zone with blend/desaturate/vertex colour and the anchor/size math above (atlas and file variants); unlocked zone draws nothing.
- Runs mode, and art mode for a zone without art: one texture per run with the run math; re-placed after `OnCanvasSizeChanged`.
- Texture pool: a redraw with fewer tinted zones hides the surplus textures.
- Tooltip follows `zoneAt`; leaving the canvas hides it.
- Zone maps: locked → red banner text, unavailable → neutral banner text, unlocked → no banner.
- Overlay off / not linked / `Enum` or `C_Map` missing → nothing drawn, no error.

## Decisions for the programmer
Resolved 2026-11-18: the programmer accepted every recommendation below (D1 visual language (a): unlocked and start zone clear, locked #8C2A2A at 45 %, not-in-seed #141414 at 65 %, "Not in your seed" banner; D2 highlight art with strip fallback and a switch to strips if the live check fails; D3 sample once and cache, spread over frames only if the live check shows a stutter).
- **D1 Visual language (needs approval per `docs/ai/ui.md`).** (a) As proposed under UI: unlocked/start clear, locked red `#8C2A2A` 45 %, not-in-seed neutral `#141414` 65 %, plus a "Not in your seed" banner on zone maps. (b) "Spotlight": no red at all — locked `#141414` 40 %, not-in-seed `#141414` 70 %; only playable zones are bright, the label in the tooltip tells locked from absent. (c) Keep today's colours (red 35 %, black 55 %) and only fix the shapes. **Recommend (a)**: one meaning per colour, red = "you will get it", dark = "not in this game".
- **D2 Shape source.** (a) Zone highlight art (exact, soft edges like Blizzard's hover), with runs only for zones the API gives no art for; the constant switches to runs if the live check fails. (b) Sampled runs only (exact partition, cannot overlap by construction, edges stepped at about 0.6 % of the map; no dependence on how the art blends). (c) Art only, no runs (less code; zones without art stay unfilled). **Recommend (a)**: best look, and the runs path guarantees a clean result whatever the art turns out to be. If (b) or (c) is chosen, drop the unused path from steps 2–4 and its tests.
- **D3 Sampling cost.** 160 × 107 ≈ 17 000 `GetMapInfoAtPosition` calls on the first open of each continent per session. (a) Synchronous, once, cached. (b) Spread over several frames (draw when done). **Recommend (a)**, and switch to (b) only if the live check shows a hitch; it keeps the code simple.

## Risks / follow-ups
- The highlight art is made for additive blending; under `BLEND` it may show as a faint glow or a full rectangle. Only the live client tells; D2 (a) keeps runs as the fallback and the manual step decides.
- `GetMapInfoAtPosition` without `ignoreZoneMapPositionData` may return a sub-zone or city in place of the zone for some points; cells for ids not in `ns.Data.zones` stay unfilled (small holes over cities). Acceptable; noted for the live check.
- Forever may ship continents whose zone positions differ from the 12.1.5 source; everything is data-driven from the live API, so only the "Unconfirmed" list needs updating.
