# 014 — hotfix: quest names in the Checks tab

Status: draft
Version: 0.3.0 → 0.3.1
Gate (fix only · no API/format change · no migration or new dependency · ≤ 3 source files · no critical decision): holds (2 source files; no data-format, SavedVariables or generated-data change)

Symptom: since 0.1.0 (plan 001), seen live on client 1.60.1 with the released 0.3.0 addon. The window's Checks tab lists open quests as "Quest 784", "Quest 788", … instead of their localised titles, e.g. under "Durotar - start zone (19 open)".
Repro: `/wfap` → Checks tab → any zone with open quests the character has never had in its quest log.
Cause: `addon/WoWForeverAP/Core/Names.lua:35-36`. `C_QuestLog.GetTitleForQuestID` only answers for quests the client has cached. Nothing ever asks for uncached quests, so the call returns nil and the `L.QUEST_FMT` fallback is shown for good. (Confirmed by code reading of the 12.1.5 UI source. `Blizzard_ObjectAPI/Mainline/AsyncCallbackSystem.lua:17,30-53` pairs `C_QuestLog.RequestLoadQuestByID` with `QUEST_DATA_LOAD_RESULT(questID, success)`. `Blizzard_ObjectAPI/Mainline/Quest.lua:12-13` and `Blizzard_FrameXML/QuestSession.lua:870-871` read `QuestUtils_GetQuestName` → `GetTitleForQuestID` only inside that load callback. API: `Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua:1186` (RequestLoadQuestByID(questID)) and `:1303-1311` (event payload questID, success).)
Fix:
- `addon/WoWForeverAP/Core/Names.lua:34-37`: when the title is missing, request the quest data once per quest id per session. Add `Names.isRequested(questId)`.
- `addon/WoWForeverAP/UI/Panel.lua:513-535` + end of file: when a quest we asked for loads, redraw the open window, at most once per 0.25 s, keeping the scroll position. Register `QUEST_DATA_LOAD_RESULT` via `ns.Events.tryRegister`.

Fix detail (exact):
1. Names.lua: add `local requested = {}` (quest id → true, this session only; it is not saved).
   - Add `local function requestQuestData(questId)`. If `requested[questId]` is set, return. Otherwise set `requested[questId] = true`, then call `if C_QuestLog then tryCall(C_QuestLog.RequestLoadQuestByID, questId) end`. `tryCall` already covers a missing function and errors.
   - `Names.quest(questId)`: keep the title lookup. If there is no title, call `requestQuestData(questId)` and return `ns.L.QUEST_FMT:format(questId)` as before.
   - Add `function Names.isRequested(questId) return requested[questId] == true end` with a `---` doc line.
   - A failed load (`success == false`) is not retried this session. That is on purpose: it prevents request loops.
2. Panel.lua:
   - Turn the body of `Panel.refresh` into `local function redraw(retainScroll)`. `Panel.refresh()` calls `redraw(false)`. Do not add a parameter to `Panel.refresh`, because the `OnShow` script passes the frame as its first argument.
   - `showRows(snapshot, retainScroll)` calls `frame.List:SetDataProvider(CreateDataProvider(...), retainScroll == true)`. `ScrollBoxListMixin:SetDataProvider(dataProvider, retainScrollPosition)` scrolls to the top unless the second argument is true (`Blizzard_SharedXML/Shared/Scroll/ScrollBox.lua:703-714`). A name refresh must not move the list while the player scrolls.
   - Add `local NAME_REFRESH_DELAY = 0.25 * SECOND` and `local nameRefreshPending = false`.
   - Add `local function refreshNames() nameRefreshPending = false; redraw(true) end`.
   - Add `function Panel.onQuestDataLoaded(questId, success)`. Return early when any of these holds: `success ~= true`, `not ns.Names.isRequested(questId)` (loads that Blizzard UI asked for are ignored), the window is not open (the next `OnShow` redraws anyway), or `nameRefreshPending` is set.
   - Inside `onQuestDataLoaded`, if `type(C_Timer) == "table" and type(C_Timer.After) == "function"`, set `nameRefreshPending = true` and call `C_Timer.After(NAME_REFRESH_DELAY, refreshNames)`. Otherwise call `refreshNames()` directly.
   - At the end of the file, add `ns.Events.tryRegister("QUEST_DATA_LOAD_RESULT", Panel.onQuestDataLoaded)`. This is the same pattern as `Detect/PvP.lua:128-130`. Main.lua does not change.
3. `CHANGELOG.md` `[Unreleased]` → `### Fixed`: "Checks tab shows quest names instead of 'Quest <id>' for quests the character has never seen; names appear once the game has loaded them."

Regression test: `addon/spec/names_spec.lua`, in "quests". `GetTitleForQuestID` returns nil and `RequestLoadQuestByID` counts its calls. Calling `ns.Names.quest(784)` twice returns "Quest 784" both times, and the request count is exactly 1 (fails today: 0 requests). `addon/spec/panel_spec.lua`, in "window". Link with open quest 784 and open the window with `ns.Panel.toggle()`; the row text is "Quest 784". Then make `GetTitleForQuestID(784)` return "Lazy Peons" and call `ns.Events.dispatch("QUEST_DATA_LOAD_RESULT", 784, true)`. With `C_Timer` stubbed to run the callback immediately, the shown rows contain "Lazy Peons" (fails today: no handler, the text stays "Quest 784").

Affected — changed symbols, their direct callers/readers, shared data they write:
| Part | Covered by |
|---|---|
| `Names.quest` (request on miss, once per id; fallback while loading and without the API) | `addon/spec/names_spec.lua` "quests": update the existing case (no `RequestLoadQuestByID` → still "Quest 5", no error) + add the regression case + `RequestLoadQuestByID` raising an error → fallback, no error |
| `Names.isRequested` (new) | `addon/spec/names_spec.lua`: false before a miss, true after; false for an id whose title was found |
| `Names.location` quest branch → `Tracker.lua:55` CHECK_RECORDED chat line | `addon/spec/names_spec.lua:58` (existing) |
| `Panel.zoneRows` / `Panel.rows` (Checks tab quest rows) | `addon/spec/panel_spec.lua` "Checks tab" (existing) |
| `Panel.refresh` → `redraw` (OnShow, `selectTab`, link button, `toggle`) | `addon/spec/panel_spec.lua` "window" (existing) + add: `Panel.refresh()` passes retain = false |
| `showRows` scroll retention | `addon/spec/panel_spec.lua`: the load-triggered redraw passes retain = true. In `addon/spec/helpers/wow_stub.lua` `Frame:SetDataProvider`, also record the second argument |
| `Panel.onQuestDataLoaded` + registration | `addon/spec/panel_spec.lua`: regression case. Also: `success = false` → no redraw. An id never requested → no redraw. Window closed → no redraw and no timer. Three loads in one burst → one `C_Timer.After`, one redraw. No `C_Timer` → immediate redraw |
| `Events.tryRegister("QUEST_DATA_LOAD_RESULT")` when the client rejects the event | `addon/spec/detect_spec.lua` "tryRegister" (existing, generic) |
| `addon/spec/helpers/wow_stub.lua` `FAKE_GLOBALS` | add `"C_Timer"` and `"ScrollBoxConstants"` (if used) so stubs do not leak between specs |
| In-game behaviour | manual: on a fresh character, open `/wfap` → Checks. The quest names replace "Quest <id>" within about a second, and the list does not jump to the top while scrolling. A German client shows German titles. No Lua errors with `/console scriptErrors 1` |

Decisions for the programmer: none
Follow-ups:
- English fallback names from the shipped data (`quests.csv` names into `Data/Generated.lua`), so names show even before the client loads them. This changes the generated data format and needs a normal plan.
- Requests are sent eagerly for every open quest the Checks tab builds: at most one per quest id per session. Blizzard's own `QuestEventListener` users do the same without a throttle. If testing shows server throttling for slots with hundreds of open quests, a normal plan could request only for rows the ScrollBox actually shows (`initRow`).
