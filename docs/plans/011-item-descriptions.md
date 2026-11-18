# 011 — Item descriptions generated from the game data

Status: draft
Type: feature
Version impact: minor — user-visible addition (item descriptions, a new guide section), no gameplay, logic, slot-data, inbox or item-id change. No release without the programmer's word.

## Goal
Every item of the world gets a short, player-facing English description: what it lets you do under the honor rules and where it sits in the progression (level range, rank, skill cap, trainer level, logic level, self-found materials). The descriptions are (1) Archipelago's built-in item info `WoWForeverWeb.item_descriptions` and (2) a generated "Item reference" section of the game guide `apworld/wow_forever/docs/en_World of Warcraft Forever.md`, kept in sync by the existing generator `--check` in CI and in `tools/build.py`. Everything is generated from `data/*.csv`; no per-item hand-written text. Text says no more than the data does (rows are provisional, README "Unconfirmed"), and it is seed-independent (options such as `goal_level` and `faction` are named, never assumed).
English only: the Archipelago site and the guide are English.
Out of scope: descriptions in the in-game addon tooltips; location descriptions (`WebWorld.location_descriptions`); item groups (`item_name_groups`, see D2); German text; showing descriptions in the AP client (see D1).

## Reuse
- `data_loader.GameData` / `load_game_data()` — every fact comes from it (zones, professions, tiers, brackets, profession_materials, instances, encounters, misc_items, releases).
- `items.ITEM_NAME_TO_ID` — the set of names that must be described (test compares against it).
- `tools/gen_addon_data.py` (`expected_outputs`, `main --check`, `display_path`) — already run by `scripts/ci.sh` and checked by `tools/build.py ensure_generated_data_is_current`; the guide becomes one more expected output (D4).
- `locations.allowed_tiers` — its tier/bracket level rule is moved into a pure helper so the descriptions and the seed use the same rule (no duplicated logic).
- `tools/_apworld.apworld_module` — the generator imports the new pure module without Archipelago.
- New: `apworld/wow_forever/descriptions.py` — no existing pure module builds player-facing text from data; `items.py` imports `BaseClasses`, which the generator must not need.

## Code layout
- `apworld/wow_forever/descriptions.py` (new, pure: imports only `data_loader`) — item description texts and the guide fragments' facts.
- `apworld/wow_forever/data_loader.py` — add `tier_logic_level`.
- `apworld/wow_forever/locations.py` — `allowed_tiers` uses `tier_logic_level` (same behaviour).
- `apworld/wow_forever/__init__.py` — `WoWForeverWeb.item_descriptions = build_item_descriptions(load_game_data())`.
- `tools/gen_addon_data.py` — builds the guide's generated section and splices it between markers; `GUIDE_FILE` in `expected_outputs`.
- `tools/build.py` — turn a marker error into `BuildError`.
- `apworld/wow_forever/docs/en_World of Warcraft Forever.md` — new heading and markers (once by hand), generated content, one pointer sentence in the "Items" bullet.
- `README.md` — the generator also writes the guide's item reference.
- `CHANGELOG.md` — `[Unreleased]` → `### Added`.
- `tests/test_descriptions.py` (new), `tests/test_gen_addon_data.py`, `tests/test_build.py`, `tests/test_goal_level.py` (only if needed) — tests.

## Data
None (no CSV column or file change).

## Interfaces

### `data_loader.tier_logic_level(data: GameData, tier: ProfessionTier) -> int | None`
`max(tier.required_level, bracket.required_level)` for the first bracket (sorted by `max_skill`) with `tier.max_skill <= bracket.max_skill`; `None` when no bracket covers it. Docstring: the lowest goal level that keeps the tier, and the level the logic needs at the top of the tier.
`locations.allowed_tiers` becomes: per released tier in order, `level = tier_logic_level(data, tier)`; `if level is None or level > goal_level: break`. Shipped values: Apprentice 5, Journeyman 15, Expert 30, Artisan 45.

### `descriptions.py`
Constants:
- `FACTION_LABELS = {"alliance": "Alliance", "horde": "Horde", "both": "both factions"}`
- `SELF_FOUND = "With the Auction House, trading, mail and shared banks all off"`
- `SOURCE_WORDS = {"drops": "loot", "vendor": "vendors"}`

Public functions (all pure, deterministic, ordered by CSV order unless stated):
- `join_words(words: Sequence[str], last: str = "and") -> str` — `"a"`, `"a and b"`, `"a, b and c"` (`last="or"` for alternatives).
- `release_note(data, release: int) -> str` — `""` for the lowest release id in `data.releases`, else `f", from the {label} release"`. Used inside the parentheses below; with today's single release it adds nothing.
- `zone_instances(data, zone) -> list[Instance]` — instances with `entrance_ui_map_id == zone.ui_map_id`, sorted by `(min_level, name)`.
- `material_parts(data, profession) -> tuple[list[str], bool]` — from `data.profession_materials` rows with `crafting_skill_line_id == profession.skill_line_id` (all releases): distinct gatherer names (professions.csv order) then distinct `SOURCE_WORDS` (in `MATERIAL_SOURCES` order); the bool is "every row is a gather row".
- `supplied_professions(data, profession) -> list[Profession]` — crafting professions with a gather row whose `gather_skill_line_id` is this profession (professions.csv order).
- `materials_summary(data, profession) -> str` — guide cell: `join_words(parts, "or")` when it has rows; else `"supplies " + join_words(names)` when it supplies others; else `"-"`.
- `zone_description(data, zone) -> str`
- `profession_description(data, profession) -> str`
- `misc_item_description(data, item: MiscItem) -> str` — by `item.kind`; a kind without a text raises `KeyError` (test pins that both `MISC_KINDS` have one).
- `build_item_descriptions(data) -> dict[str, str]` — item name → description for every zone, profession and misc item; keys equal `build_item_table(data)` keys.

Text templates (exact; `{...}` from data, sentences joined with one space):

**Zone** (`Zone: <name>`):
1. `Unlocks {name} ({faction label}, levels {min}-{max}{release_note}).`
2. `Once it has arrived you may quest, kill for experience, gather and loot there; before that, only travel through it.`
3. `The logic counts it for levels {min}-{max}, and the quest and area discovery checks in {name} need it.`
4. only if `zone_instances` non-empty: `Group finder teleports into {join_words(instance names)} are allowed only once it has arrived.`
5. only if any of those instances has an encounter row: `Boss checks in {join_words(names of instances with encounters)} need it too.`
6. only if `is_start`: `It can be the start zone of a seed, which is unlocked from the beginning.`
7. only if `min_level > 1`: `Left out of seeds whose goal_level is below {min}.`

Example (Westfall, shipped data): "Unlocks Westfall (Alliance, levels 10-20). Once it has arrived you may quest, kill for experience, gather and loot there; before that, only travel through it. The logic counts it for levels 10-20, and the quest and area discovery checks in Westfall need it. Group finder teleports into The Deadmines are allowed only once it has arrived. Left out of seeds whose goal_level is below 10."

**Profession** (`Progressive <name>`), tiers in `tier` order, all releases:
1. `Each copy unlocks the next {name} rank you may train: {join_words([f"{rank} (skill {max_skill}, trainer level {required_level}{release_note})" ...])}.`
2. `Do not train a rank before its copy has arrived.`
3. `In the logic, {name} skill checks up to a rank's cap need that rank and character level {join_words(logic levels)} for the ranks in order; a seed whose goal_level is below a rank's level leaves that rank and every later one out.`
4. primary: `{name} is a primary profession: it is in the seed when listed in professions, and profession_mode solo or team can limit the primaries.` / secondary: `{name} is a secondary profession: it is in the seed when listed in professions, and profession_mode never limits it.`
5. materials (one of):
   - rows, all gather: `{SELF_FOUND}, its materials come from {join_words(parts, "or")}, which must be in the seed with the rank that reaches them.`
   - rows, none gather: `{SELF_FOUND}, its materials come from {join_words(parts, "or")}, so the character level is enough.`
   - rows, mixed: `{SELF_FOUND}, its materials come from {join_words(parts, "or")}.`
   - no rows, supplies others: `{SELF_FOUND}, it supplies the materials of {join_words(names)}.`
   - neither: no sentence.

Example (Alchemy): "... Apprentice (skill 75, trainer level 5), Journeyman (skill 150, trainer level 10), Expert (skill 225, trainer level 20) and Artisan (skill 300, trainer level 35). ... character level 5, 15, 30 and 45 for the ranks in order; ... With the Auction House, trading, mail and shared banks all off, its materials come from Herbalism, which must be in the seed with the rank that reaches them."

**Misc items** (`kind`):
- `care_package`: `Allows one pull from a main character: up to care_package_gold gold or care_package_stacks stacks of materials, as set in your options (care_packages sets how many are in the pool). The logic never needs it. In the game, /wfap care counts the ones received and used; the tool moves no gold or items.`
- `filler`: `Filler: it unlocks nothing. It fills the locations left over after the unlocks and the {care_package.name} items.`

### `tools/gen_addon_data.py`
- `GUIDE_FILE = ROOT / "apworld" / "wow_forever" / "docs" / "en_World of Warcraft Forever.md"`
- `GUIDE_BEGIN = "<!-- BEGIN GENERATED: item reference (python tools/gen_addon_data.py). Do not edit by hand. -->"`, `GUIDE_END = "<!-- END GENERATED: item reference -->"` (HTML comments: the WebHost renders markdown with `escape=False`, so they stay invisible).
- `class GuideMarkerError(ValueError)` — markers missing, not exactly once each, or END before BEGIN; message names the file.
- `build_guide_section(data) -> str` — markdown below; `_cell(text)` escapes `|` as `\|`.
- `splice_guide(current: str, section: str) -> str` — everything up to and including the BEGIN line, `"\n" + section + "\n"`, then from the END line on; text outside the markers is byte-identical.
- `expected_outputs()` adds `GUIDE_FILE: splice_guide(<current GUIDE_FILE text>, build_guide_section(data))`; a missing guide file raises `GuideMarkerError`.
- `main` catches `GuideMarkerError`: prints `error: <message>` to stderr, returns 1.
- Module docstring: list the guide section under Outputs.

Generated section (inside the markers):
```
Generated from the game data, like the item descriptions of this world. The data is provisional (see "Unconfirmed content").

### Zones

Each zone is one item, `Zone: <zone>`. Once it has arrived you may quest, kill for experience, gather and loot in the zone; before that, only travel through it.

| Item | Faction | Levels | Start zone | Dungeons | Release |
|---|---|---|---|---|---|
| Zone: Elwynn Forest | Alliance | 1-10 | yes |  | Launch |
...(zones.csv order; Start zone "yes" or empty; Dungeons = join_words of zone_instances names or empty)

### Professions

Each profession is one item, `Progressive <profession>`, with one copy per rank. Do not train a rank before its copy has arrived. Every profession has the same ranks:

| Copies | Rank | Skill cap | Trainer level | Logic level | Release |
|---|---|---|---|---|---|
| 1 | Apprentice | 75 | 5 | 5 | Launch |
...

The logic level is the character level the logic needs for skill checks up to the rank's cap. A seed whose goal_level is below it leaves that rank and every later one out.

| Item | Kind | Self-found materials |
|---|---|---|
| Progressive Alchemy | primary | Herbalism |
...(professions.csv order; materials_summary)

"Self-found" means the Auction House, trading, mail and shared banks are all off.

### Other items

| Item | Description |
|---|---|
| Care Package | <misc_item_description> |
| Traveler's Tale | <misc_item_description> |
```
(misc_items.csv order.)

### `tools/build.py`
`ensure_generated_data_is_current`: wrap `gen_addon_data.expected_outputs()` in `try/except gen_addon_data.GuideMarkerError as error: raise BuildError(str(error)) from None`. The stale-check message stays as is (it now also lists the guide).

## Security and user data
None.

## UI
Guide page only (markdown table + text, existing guide style: `##`/`###` headings, `|---|` tables, option names in backticks). No addon or client UI.

## Steps
1. `data_loader.tier_logic_level`; switch `locations.allowed_tiers` to it. Run `pytest tests/test_goal_level.py` — unchanged results.
2. `descriptions.py` with the constants, helpers and templates above.
3. `__init__.py`: import `build_item_descriptions` and `load_game_data` (already imported); in `WoWForeverWeb` add `item_descriptions = build_item_descriptions(load_game_data())`.
4. Guide by hand: add `## Item reference` directly before `## Unconfirmed content`, containing only `GUIDE_BEGIN` and `GUIDE_END` on their own lines. In the "Items" bullet of "What does randomization do to this game?" append: `The item reference below describes every item.`
5. `tools/gen_addon_data.py`: `GUIDE_FILE`, markers, `GuideMarkerError`, `build_guide_section`, `splice_guide`, `expected_outputs`, `main`, docstring.
6. `tools/build.py`: marker error → `BuildError`.
7. Run `python tools/gen_addon_data.py`; commit the regenerated guide (only the guide should change; `Generated.lua` and fixtures unchanged).
8. `README.md` line "`addon/WoWForeverAP/Data/Generated.lua` is generated…": add that the same tool writes the guide's item reference between its markers; never edit that part by hand.
9. `CHANGELOG.md` `[Unreleased]` → `### Added`: "Item descriptions (plan 011): every item has a short description generated from the game data, as the world's item descriptions and as an "Item reference" section of the game guide, kept in sync by `tools/gen_addon_data.py --check`."
10. Tests below; then `pytest`, `ruff check .`, `bash scripts/ci.sh`.

## Tests
`tests/test_descriptions.py` (new):
- `build_item_descriptions(load_game_data())` keys == `set(ITEM_NAME_TO_ID)`; every value non-empty, no leading/trailing whitespace, no newline.
- `WoWForeverWorld.web.item_descriptions == build_item_descriptions(load_game_data())`; every key is in `WoWForeverWorld.item_names` (mirrors AP's `test_item_descriptions_have_valid_names`).
- Westfall description equals the exact example string above (pins the template).
- Elwynn Forest contains the start-zone sentence and no "goal_level is below"; Westfall/Feralas contain no start-zone sentence; Feralas contains "Dire Maul"; a zone without instances (e.g. Darkshore) has no "Group finder" sentence.
- Boss sentence: no shipped zone has it; with an added encounter row for The Deadmines (via `parse_game_data(read_shipped_files() + row)`, as `test_generated_boss_table_follows_instances_and_encounters`) Westfall gets `Boss checks in The Deadmines need it too.`
- Alchemy: ranks in order with "trainer level 5" … "trainer level 35", "5, 15, 30 and 45", "Herbalism", "which must be in the seed"; Enchanting: "loot", "so the character level is enough"; Herbalism: "supplies the materials of Alchemy"; Mining: "Blacksmithing and Engineering"; Fishing: "secondary", no `SELF_FOUND` sentence.
- Drift: change Artisan `required_level` 35→40 and Westfall `max_level` 20→22 in the CSV texts → descriptions change accordingly ("trainer level 40", "levels 10-22").
- Release note: add release `2,later,Later,2027-01-01` and a zone with release 2 → its description contains ", from the Later release)"; release-1 rows unchanged.
- `misc_item_description` for both kinds; filler text names the care package item; unknown kind → `KeyError`.
- `join_words`: 1, 2, 3 words; `last="or"`.
- `tier_logic_level`: shipped tiers → 5, 15, 30, 45; a tier above every bracket (GameData built directly) → `None`.
- Determinism: two builds are equal.

`tests/test_gen_addon_data.py`:
- `output_paths` fixture: also redirect `GUIDE_FILE` to a tmp copy of the real guide.
- `test_shipped_generated_files_are_up_to_date` covers the guide (no change needed).
- `build_guide_section` contains every item name of `ITEM_NAME_TO_ID`, the rank table rows `| 1 | Apprentice | 75 | 5 | 5 | Launch |`, and `| Progressive Alchemy | primary | Herbalism |`.
- `splice_guide`: replaces only between markers (prefix and suffix byte-identical); idempotent; missing BEGIN, missing END, END before BEGIN, a marker twice → `GuideMarkerError`.
- `main(["--check"])` with a guide copy whose markers were removed → returns 1, `error:` on stderr, file unchanged.
- CSV change (zone rename, as the existing stale test) → `--check` fails naming the guide; `main([])` rewrites only the section; then `--check` passes.
- `_cell` escapes `|` (a zone named with `|` via modified CSV).

`tests/test_build.py`:
- Guide without markers (monkeypatched `GUIDE_FILE`) → `BuildError` naming the file.

## Decisions for the programmer
- **D1 — Built-in item info is not shown anywhere in Archipelago 0.6.8.** `WebWorld.item_descriptions` exists, but no WebHost page, launcher or client of 0.6.8 displays it (only some worlds' own clients do; core only tests the names). Options: (a) ship it anyway as planned — cheap, the standard field, ready for tools/future AP versions; the guide is the visible copy; (b) drop it and only do the guide; (c) also show descriptions in our AP client (e.g. a command) — a new feature, not requested. Recommendation: (a).
- **D2 — Per-item descriptions vs item groups.** The world defines no `item_name_groups`. Adding groups ("Zones", "Professions") would allow group descriptions but adds public names players can use in YAML (`start_inventory`, `local_items`, hints) — a public-interface change. Options: (a) per-item only, no groups; (b) add groups plus group descriptions. Recommendation: (a).
- **D3 — Where the guide content lives.** Options: (a) new `## Item reference` section before "Unconfirmed content" with generated tables (zones, ranks, professions, other items) plus a pointer sentence in the Items bullet; (b) tables inside "What does randomization do to this game?" (a 41-row zone table in the middle of the rules); (c) the full per-item description texts as a list (long, repetitive). Recommendation: (a).
- **D4 — Generator placement.** Options: (a) extend `tools/gen_addon_data.py` (already in `scripts/ci.sh --check` and in the build's stale check; the name becomes slightly broader than "addon data"); (b) new `tools/gen_docs.py` with its own `--check`, plus a new line in `scripts/ci.sh` and a second check in `tools/build.py`. Recommendation: (a).
- **D5 — Detail in the item info.** Options: (a) as specified: honor rule, ranks with skill cap and trainer level, logic levels, goal_level cut, profession_mode, self-found materials (professions about 5 sentences); (b) short: ranks, caps and trainer levels only, logic and self-found details only in the guide. Recommendation: (a) — the request asks where each item sits in the progression.

## Risks / follow-ups
- Descriptions are seed-independent: they cannot say whether an item is in a given seed (faction, goal_level, professions, profession_mode). They name the option instead.
- The level ranges, tiers and material rows are provisional; the text only restates them and the guide section points to "Unconfirmed content". Wording of the honor rule mirrors the existing "The honor system" section; if that section changes, the template in `descriptions.py` must change with it (not caught by `--check`).
- Material sentences use rows of all releases; once a later release adds rows, a description could name a source that only exists in that release. Revisit when a second release is added.
