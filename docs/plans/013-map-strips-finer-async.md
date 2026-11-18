# 013 — Finer map strips, sampled over several frames

Status: draft
Type: feature
Version impact: minor (recommended, D6) — a notable visual and performance improvement of an existing feature plus removal of the internal, never-working "art" path; no format, option or API change. Alternative: hotfix, see D6. No release without the programmer's word.

## Goal
On continent maps the strip fills (default since hotfix 012) follow zone borders twice as finely (320 × 214 grid instead of 160 × 107), and the four-times-larger sampling is spread over frames so opening a continent map never hitches. Cache semantics stay as in plan 010. With D5 (a), the unused highlight-art path (`Style.MAP_SHAPE_SOURCE = "art"`) is removed — the hotfix-012 follow-up.
Out of scope: fills over coastal water (the game's zone lookup includes sea; unchanged), holes over cities/sub-zones, edge smoothing beyond the finer grid, merging strips into rectangles, a progress indicator, zone maps and banners (unchanged).

## Reuse
- `UI/MapShapes.lua`: row sampling loop, `dataZoneId`, run merging, `zoneAt`, `reset`, the cache table and its "completed → cached, missing/erroring → not cached" rule (plan 010, amended).
- `UI/MapOverlay.lua`: provider `OnUpdate`, already registered with `map:RegisterDataProviderOnUpdate(self)` and called every frame by `MapCanvasMixin:RunDataProviderOnUpdate` while the map is shown (12.1.5 `Blizzard_MapCanvas/Blizzard_MapCanvas.lua:29-35, 135-160`). It is the frame driver — no new timer API (D4). `RefreshAllData` is called by the canvas on show (`:91-95`) and on map change (`MapCanvas_DataProviderBase.lua:74-77`), which gives the invalidation points for free.
- Texture pool, `placeItem` run math, `drawZones`, `RemoveAllData` unchanged in shape.
- Specs: `map_shapes_spec.lua` fake lookup, `map_overlay_spec.lua` fake map; the fake ticker is `provider():OnUpdate()`, already used by the tooltip specs.
- New: only `MapShapes.step` / `MapShapes.cached` (resumable job replaces the one-shot `sampleRuns` / `forContinent`); nothing existing samples incrementally.

## Code layout
- `addon/WoWForeverAP/UI/MapShapes.lua` — grid constants, per-continent resumable sampling job with a frame budget, cache; art lookup removed (D5 a).
- `addon/WoWForeverAP/UI/MapOverlay.lua` — "sampling" view state, step the job in `OnUpdate`, synchronous fallback without the per-frame hook; art drawing removed (D5 a).
- `addon/WoWForeverAP/UI/Style.lua` — remove `MAP_SHAPE_SOURCE` and its comment (D5 a).
- `.luacheckrc` — add `"debugprofilestop"` to `read_globals` (alphabetical).
- `addon/spec/map_shapes_spec.lua`, `addon/spec/map_overlay_spec.lua`, `addon/spec/style_spec.lua` — updated per Tests.
- `addon/spec/helpers/wow_stub.lua` — remove the `SetAtlas`, `SetTexCoord`, `SetVertexColor`, `SetDesaturated`, `SetBlendMode` stubs if, after the spec changes, `grep` finds no other user (D5 a).
- `README.md` "Unconfirmed" → "Map overlay zone shapes" note (lines 103-114) — rewrite per Step 6.
- `CHANGELOG.md` — `[Unreleased]` → `### Changed` (and `### Removed` with D5 a).

## Data
None. Cache and job state are Lua upvalues for the session (not SavedVariables).

## Interfaces
`MapShapes` (APIs checked against the 12.1.5 source: `C_Map.GetMapInfoAtPosition` as before; `debugprofilestop()` → `elapsedMilliseconds`, `Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua:533-540`. Never call `debugprofilestart` — it would reset other addons' profiling; only differences of `debugprofilestop()` are used):
- Constants: `COLUMNS = 320`, `ROWS = 214` (D1); `FRAME_BUDGET_MS = 4` (D3); `FALLBACK_ROWS_PER_STEP = 4` (rows per frame when `debugprofilestop` is missing or returns a non-number).
- Upvalues: `cache = {}` (`[continentMapId] = zones`), `jobs = {}` (`[continentMapId] = { nextRow = 1, runs = {}, started = false }`).
- `MapShapes.cached(continentMapId) -> zones | nil` — the finished partition `{ [uiMapId] = { runs = { { row, first, last }, ... } } }`, or nil when not (yet) sampled.
- `MapShapes.step(continentMapId, budgetMs) -> "done" | "pending" | "failed"`:
  1. `cache[id]` present → `"done"`, no API call.
  2. `C_Map` or `C_Map.GetMapInfoAtPosition` not a function → `jobs[id] = nil`, `"failed"`.
  3. `job = jobs[id]` or a new job (stored). Read `start = clock()` only when `budgetMs` is given; `clock()` = `debugprofilestop()` when it is a function returning a number, else nil.
  4. Loop: `sampleRow(id, job)` (local; the body of today's inner column loop for row `job.nextRow`, appending to `job.runs`, then `job.nextRow = job.nextRow + 1`). A `pcall` error on the job's very first call (`job.started == false`) → `jobs[id] = nil`, return `"failed"`; later errors make the cell empty (as today). After the row: if `job.nextRow > ROWS` → `cache[id] = zones` built from `job.runs` (`{ runs = list }` per id, also when empty), `jobs[id] = nil`, return `"done"`. Else stop with `"pending"` when `budgetMs` is given and either `start` is a number and `clock() - start >= budgetMs`, or `start` is nil and the rows sampled in this call `>= FALLBACK_ROWS_PER_STEP`. `budgetMs == nil` → run to completion (synchronous; used by the fallback and specs). At least one row per call.
- `MapShapes.zoneAt` unchanged. `MapShapes.reset()` clears `cache` and `jobs`.
- Removed: `sampleRuns`, `forContinent`, `highlightArt`, `probePoint` (D5 a). With D5 (b) keep `highlightArt`/`probePoint` and set `art` per zone when the job finishes (the ~25 extra calls happen in the finishing frame).

Mid-sampling invalidation (design, minor): a job's progress is kept when the map closes or switches to another map and resumes the next time that continent is opened; zone geometry does not change within a session, so nothing is resampled and no frame is wasted. A failed job is dropped and the next open starts again (plan 010's "retry next open").

`MapOverlay`:
- `MapOverlay.view` continent branch: `local shapes = ns.MapShapes.cached(mapId)`; nil → `return { kind = "sampling" }`; else as today over `pairs(shapes)` (nil when no data zone).
- `ProviderMethods:OnAdded` sets `self.ticking = true` when it registers with `RegisterDataProviderOnUpdate`.
- `RemoveAllData` also sets `self.sampling = nil` (map change, show, option toggle all pass through it).
- `RefreshAllData`, after `view` is built: if `view.kind == "sampling"`: when `self.ticking` → `self.sampling = mapId` and return (nothing drawn, D2); otherwise `ns.MapShapes.step(mapId)` synchronously, then rebuild `view` once (never recurse; a failed step leaves `view` as "sampling" → return).
- `OnUpdate`, first thing: if `self.sampling` → `status = ns.MapShapes.step(self.sampling, ns.MapShapes.FRAME_BUDGET_MS)`; `"pending"` → return; else `self.sampling = nil`, and on `"done"` call `self:RefreshAllData()`; return (tooltip resumes next frame). No tooltip while sampling (`self.zones` is nil).
- With D5 (a): delete `usableArt`, the atlas/file branches of `placeItem`, the art half of `dress` (it becomes `texture:SetColorTexture(tint.r, tint.g, tint.b, tint.a)` only — pooled textures only ever hold colours now), the art branch of `zoneItems`. Update the header comments of both files (APIs: drop `GetMapHighlightInfoAtPosition`, `SetAtlas`, `SetTexture`, `SetTexCoord`, `SetVertexColor`, `SetDesaturated`, `SetBlendMode`; add `debugprofilestop`, and that sampling runs in the provider's `OnUpdate`).

## UI
No new visuals; fills, colours, tooltip and banners as approved in plan 010 D1. Changed: strip edges step at about 0.3 % of the map; on the first open of a continent per session the fills appear after sampling finishes (D2: nothing before; estimate below). States: sampling in progress (nothing drawn, no tooltip), map closed mid-sampling (resumes on reopen), API missing/erroring (nothing, retried next open), no per-frame hook (sampled synchronously, as today).

Estimate (to confirm live): runs scale with rows, not columns. A continent with ~25 data zones spanning ~20 % of the height each at ~1.2 runs per row gives ~600 runs today and ~1,200 at 214 rows when every zone is tinted (fresh seed); fewer as zones unlock. The pool keeps its high-water mark of plain colour textures (reused, surplus hidden); placing 1,200 textures on a canvas resize is a short loop. 68,480 lookups at an unknown 1–5 µs each = 70–340 ms of work → 18–85 frames at 4 ms, i.e. roughly 0.3–1.5 s at 60 fps until the fills appear.

## Steps
1. `MapShapes.lua`: constants, `cache`/`jobs`, `clock`, `sampleRow`, `step`, `cached`, `reset`; delete `sampleRuns`, `forContinent`, `highlightArt`, `probePoint` (D5 a); header comment.
2. `MapOverlay.lua`: `view` sampling state, `OnAdded` flag, `RemoveAllData`, `RefreshAllData`, `OnUpdate` per Interfaces; delete the art path (D5 a); header comment.
3. `Style.lua`: delete `MAP_SHAPE_SOURCE` and its comment (D5 a).
4. `.luacheckrc`: `debugprofilestop`.
5. Specs per Tests; stub cleanup in `wow_stub.lua` (D5 a).
6. `README.md` note: grid 320 x 214, about 68,000 calls per continent and session, spread over frames (`FRAME_BUDGET_MS`, provider `OnUpdate`) with `debugprofilestop` (checked against 12.1.5, unconfirmed for Forever); remove the `GetMapHighlightInfoAtPosition`/texture-method/`MAP_SHAPE_SOURCE` sentences and replace with one line "the highlight art was removed after the 1.60.1 check (plan 013)" (D5 a); open points: time until fills appear, smoothness while sampling, edges, coastal water fills (known, out of scope).
7. `CHANGELOG.md` `[Unreleased]`: `### Changed` — "World map overlay: zone fills follow borders twice as finely and are sampled over several frames, so opening a continent map does not stutter; fills appear once sampling finishes (first open per session)." With D5 (a) `### Removed` — "The unused zone highlight art option of the map overlay (`Style.MAP_SHAPE_SOURCE`); strips are the only shape source."
8. `luacheck addon`, `bash scripts/ci.sh`.
9. Manual (programmer, live client 1.60.1 / 16001): open Eastern Kingdoms and Kalimdor with a slot that has locked, unlocked and other-faction zones; check (a) no hitch or frame drop on the first open, (b) time until fills appear, (c) edges visibly finer and still no overlap, (d) close the map mid-sampling and reopen — fills appear, no error, (e) switch continents mid-sampling, (f) tooltip after sampling. Record in README "Unconfirmed". If (a) fails, lower `FRAME_BUDGET_MS`; if (b) is too slow, raise it — constants only.

## Tests
`map_shapes_spec.lua` (keep the fake lookup; `after_each` sets `_G.debugprofilestop = nil`):
- `step(id)` without budget → `"done"`; `cached(id)` has one run per row and zone (ROWS - 2 rows of Elwynn, `{ 2, 1, COLUMNS / 2 }` etc. — the existing `sampleRuns` assertions moved onto `cached`), none for city or continent; the split-row case with columns 1–96 / 129–320 at the new grid (`x` gap 0.3–0.4).
- Constants: `COLUMNS == 320`, `ROWS == 214`.
- Time budget: fake `debugprofilestop` returning 1, 2, 3, … per call; `step(id, 4)` → `"pending"` after exactly 4 rows (`calls.info == 4 * COLUMNS`); repeated steps reach `"done"` and the result equals a synchronous run's.
- Fallback budget: `debugprofilestop` nil, and one returning a string → `step(id, 4)` samples `FALLBACK_ROWS_PER_STEP` rows per call.
- At least one row per call even when the budget is already spent (clock jumps by 100 per call).
- Resume: two pending steps, `reset` not called, a new step continues at the next row (no row sampled twice: total calls after `"done"` == `COLUMNS * ROWS`).
- Two continents' jobs are independent (second continent id in the fake lookup accepted).
- `step` on a cached continent makes no API call and returns `"done"`; empty-but-completed result is cached (`cached(id)` is `{}`, second `step` makes no call).
- API missing → `"failed"`, nothing cached; first call erroring → `"failed"` after exactly 1 call, job dropped, a later step with a working API starts at row 1 and finishes; an error on a later cell leaves that cell empty and the job continues.
- `zoneAt` cases unchanged. Remove the `highlightArt` and probe-point cases (D5 a).

`map_overlay_spec.lua`:
- Helper `finishSampling()`: calls `provider():OnUpdate()` until `provider().sampling == nil` (fail after 1,000 iterations). `strips(id)` reads `ns.MapShapes.cached(CONTINENT)[id].runs`. Existing drawing, pool, toggle and tooltip cases call `finishSampling()` after the first `RefreshAllData()` on the continent.
- First `RefreshAllData` on an uncached continent draws nothing (`shownTextures()` empty, `provider().zones` nil, `provider().sampling == CONTINENT`); after `finishSampling()` the strips are drawn; a second `RefreshAllData` draws at once (cached).
- With a fake clock giving a small budget, the first `OnUpdate` leaves `sampling` set and nothing drawn; no tooltip while sampling.
- Map change mid-sampling (`map.mapId = DUN_MOROGH; RefreshAllData()`) clears `sampling`, shows the banner; back to the continent and `finishSampling()` completes without resampling finished rows.
- Map closes mid-sampling (`OnHide`, then `RefreshAllData()` as on show) → resumes and draws.
- No per-frame hook (`map.RegisterDataProviderOnUpdate = nil` before `install()`) → `RefreshAllData` samples synchronously and draws at once.
- Failing API: `GetMapInfoAtPosition` errors → after one `OnUpdate`, `sampling` nil, nothing drawn, `game.errors` empty; restoring the API and `RefreshAllData()` + `finishSampling()` draws.
- `view` on an uncached continent → `{ kind = "sampling" }`; the "missing API" case adjusts (with `C_Map = {}` view is "sampling" and the overlay draws nothing).
- D5 (a): delete the art cases (`:275`, `:298`, `:333`) and the `arts` table/`GetMapHighlightInfoAtPosition` fake; keep the default-style case (`:319`) reworded as "draws plain colour strips" asserting every item is `"run"` and the textures carry only `color`.
`style_spec.lua`: drop the `MAP_SHAPE_SOURCE` line (D5 a).

## Decisions for the programmer
- **D1 Grid size.** (a) 320 × 214 — 2×, ~68,000 calls, ~2× textures (up to ~1,200 per continent). (b) 240 × 160 — 1.5×, ~38,000 calls, ~1.5× textures, steps still visible. (c) 480 × 321 — 3×, ~154,000 calls, ~3× textures, 2–4 s until fills appear. **Recommend (a)**: the requested doubling; steps of ~3 px on a 1,000 px canvas.
- **D2 What the map shows while sampling (first open per continent and session).** (a) Nothing until done, then all fills at once. (b) Partial: draw rows as they finish (fills grow top to bottom; needs redraw per frame and texture churn). (c) Old cache — there is none in a fresh session, and sampling the coarse grid first is the 17,000-call hitch we remove. **Recommend (a)**: simplest, no flicker, under ~1.5 s by the estimate.
- **D3 Frame budget.** (a) Time budget `FRAME_BUDGET_MS = 4` per frame via `debugprofilestop`, checked after each row (320 calls), at least one row; fixed 4 rows when the clock is missing. (b) Count only: fixed 4 rows (1,280 calls) per frame. **Recommend (a)**: adapts to the unknown per-call cost on Forever hardware; (b) is simpler but may hitch on slow machines or be needlessly slow on fast ones.
- **D4 Frame driver.** (a) The map's data-provider `OnUpdate` (already registered; runs only while the map is shown, so a closed map pauses for free; synchronous fallback when the hook is missing). (b) `C_Timer.NewTicker(0, …)` (documented in 12.1.5 `UITimerDocumentation.lua:22`) — runs while the map is closed too, needs cancel on hide/map change and its own guard. **Recommend (a)**: no new API, invalidation comes from the canvas.
- **D5 Remove the unused "art" path here.** (a) Yes, in this plan: `Style.MAP_SHAPE_SOURCE`, `usableArt`, atlas/file drawing, `MapShapes.highlightArt`/`probePoint`, their specs and README note. (b) Keep it; separate plan later. **Recommend (a)**: this plan rewrites `forContinent` and the sampling anyway — keeping art means carrying the probe-point lookup into the async job and testing both paths again for a path proven not to work on 1.60.1 (hotfix 012: additive art over black cannot produce the dark/red fills). Deleting it makes every pooled texture a plain colour strip. It deletes a (developer-only, non-user-facing) feature, hence asking.
- **D6 Version impact.** (a) minor (0.3.0 on release) — "notable performance or internal improvement" plus a removal, fine in 0.x. (b) hotfix (ships as 0.2.1 with 012) — treats the finer grid as a visual fix; the art removal sits awkwardly in a fixes-only release. **Recommend (a)**.

## Risks / follow-ups
- Per-call cost of `GetMapInfoAtPosition` on Forever is unknown; the budget constants may need tuning after the live check (no code change).
- ~1,200 colour textures in the worst case; if canvas zoom/pan shows a cost, merging vertically identical runs into one rectangle is a separate follow-up (not planned here).
- Spec runtime grows (~68,000 fake lookups per overlay case that samples); acceptable, watch `scripts/ci.sh` time.
- Coastal water fills and city/sub-zone holes remain (out of scope).
