# 008 — Goal level option (level cap slider)

Status: approved
Type: feature
Version impact: minor — new option, backward compatible (default keeps today's seeds); together with 009 and 010 the next release would be 0.2.0. No release without the programmer's word.

## Goal
A `goal_level` Range option (a slider in Archipelago's options creator) sets the level that wins the game. Everything the logic would need above that level leaves the seed: zones, quests, level milestones, profession tiers and skill checks, bosses, reputations and PvP milestones.
Out of scope: the rest of scout suggestion #8 (it was declined; only the level cap was asked for). No change to location or item ids.

## Reuse
- `goal_level` already goes from slot data to the inbox (`client/inbox.py` `_OPTION_KEYS` → `goalLevel`), and the addon already reads it (`Detect/Level.lua` `Level.goalLevel`). The slot-data and inbox formats stay the same.
- The selection filters in `locations.select_locations` / `_extra_category_specs` and the rules in `rules.py` get a `goal_level` parameter. No new module.
- The static location table (`build_location_name_to_id`) keeps levels 2..60, so ids do not change.

## Code layout
- `apworld/wow_forever/data_loader.py` — rename `GOAL_LEVEL` to `MAX_GOAL_LEVEL` (still 60: the highest goal, used to validate the data and as the option's upper bound). Update every import of it (`locations.py`, `rules.py`, `__init__.py`, `tools/gen_addon_data.py`, tests).
- `apworld/wow_forever/options.py` — new `GoalLevel(Range)`; field `goal_level` in `WoWForeverOptions`, right after `content_release`; fix the `LevelMilestoneStep` docstring ("the goal level is always a check").
- `apworld/wow_forever/locations.py` — new `allowed_tiers(data, content_release, goal_level)`; `milestone_levels(step, goal_level)`; `select_locations(..., goal_level=MAX_GOAL_LEVEL)` (keyword, last); `_extra_category_specs` gets `goal_level`.
- `apworld/wow_forever/rules.py` — `compute_bracket_zone_ids(zones, goal_level)`; `_boss_rule` and the goal rule in `set_rules` use `world.goal_level`.
- `apworld/wow_forever/__init__.py` — `self.goal_level`; zone and tier filtering; `fill_slot_data` sends `self.goal_level`; class docstring "Reach the goal level to win".
- `addon/WoWForeverAP/Core/Checks.lua` — `zoneState`: a zone whose `min` is above the slot's `goalLevel` is `"unavailable"`.
- `apworld/wow_forever/docs/en_World of Warcraft Forever.md` — the lines saying "level 60" (goal, level checks, raids) now refer to the goal level; list the option.
- `CHANGELOG.md` — `[Unreleased]` → Added.

## Data
None. No CSV change. Slot data and inbox keep their format and `schema` 1 (`goal_level` / `goalLevel` already exist; v0.1.0 seeds carry 60).

## Interfaces
- Option `goal_level` (`GoalLevel(Range)`): display name "Goal Level"; docstring: "Character level that wins the game. Zones that start above it, and quests, profession ranks, bosses, reputations and PvP checks that need a higher level, are left out of the seed."; `range_start`, `range_end`, `default` per decision D1 (proposal 10 / 60 / 60).
- `locations.allowed_tiers(data: GameData, content_release: int, goal_level: int) -> tuple[ProfessionTier, ...]` — the longest prefix (ordered by `tier`) of the tiers with `release <= content_release` for which both hold: `tier.required_level <= goal_level`, and the material bracket covering `tier.max_skill` (first row of `data.material_brackets` with `skill <= max_skill`) exists and has `required_level <= goal_level`. Stop at the first tier that fails: the addon maps "n tier items received" to "the first n tiers", so allowed tiers must be a prefix.
- `locations.milestone_levels(step: int, goal_level: int) -> list[int]` — `range(1 + step, goal_level + 1, step)` plus `goal_level`.
- `locations.select_locations(..., goal_level: int = MAX_GOAL_LEVEL)` — additionally: quests need `quest.effective_level <= goal_level`; `top_skill = max((t.max_skill for t in allowed_tiers(data, content_release, goal_level)), default=0)` replaces `max_tier_skill(data, content_release)` there (keep `max_tier_skill` for `build_location_name_to_id`).
- `_extra_category_specs(..., goal_level)` — bosses need `instance.min_level <= goal_level`; reputations `required_level <= goal_level`; PvP `required_level <= goal_level`; discoveries unchanged (the zone filter already covers them).
- `rules.compute_bracket_zone_ids(zones, goal_level)` — brackets `range(1, goal_level, LEVEL_BRACKET_SIZE)`.
- `rules._boss_rule` — raids: `max(instance.min_level, world.goal_level)`; `set_rules` goal: `can_reach_level(state, world, world.goal_level)`.
- `WoWForeverWorld.generate_early` — `self.goal_level = self.options.goal_level.value`; `allowed_zones` also needs `zone.min_level <= self.goal_level`; `self.allowed_tiers = locations.allowed_tiers(self.data, self.content_release, self.goal_level)`; pass `self.goal_level` to `compute_bracket_zone_ids` and `select_locations`. Do not change the order of `self.random` calls (same seed + default options must still give the same result).
- Addon `Checks.zoneState(slot, uiMapId)` — after the faction/release test: `local goal = options.goalLevel`; when `type(goal) == "number" and zone.min > goal` → `"unavailable"`. The start zone check stays first.

## Security and user data
None.

## UI
- Archipelago options creator: one more slider (Range), no custom UI.
- Addon: zones above the goal show as "not in your seed" (tooltip label, panel order, map tint) and give no "locked zone" warning (D3). No new strings.

## Steps
1. Rename `GOAL_LEVEL` → `MAX_GOAL_LEVEL` everywhere; run `pytest` (green, no behaviour change).
2. Add `GoalLevel` and the `goal_level` field to `options.py`; fix the `LevelMilestoneStep` docstring.
3. `locations.py`: `allowed_tiers`, `milestone_levels(step, goal_level)`, the `goal_level` keyword of `select_locations` and `_extra_category_specs`.
4. `rules.py`: `compute_bracket_zone_ids` parameter, `_boss_rule`, goal rule.
5. `__init__.py`: `self.goal_level`, zone filter, `allowed_tiers`, pass it on, slot data, docstring.
6. Addon `Checks.zoneState` change.
7. Docs, `CHANGELOG.md` (`[Unreleased]` → Added: "Option `goal_level` (slider, 10–60, default 60) …" with the values D1 settles).
8. Tests (below); `python tools/gen_addon_data.py --check`, `pytest`, `bash scripts/ci.sh`, `ruff check .`, `luacheck addon`.

## Tests
- `tests/test_world.py`: default options → `goal_level` 60 and the same locations/items as before (compare against a seed generated with the old defaults, e.g. location count and names for a fixed seed).
- `goal_level` 30: no zone with `min_level > 30` in `allowed_zones` or the item pool; no quest location with `effective_level > 30`; highest "Reach Level" location is 30; slot data `goal_level == 30`; generation succeeds for both factions (full fill, `test_world` style).
- `goal_level` at `range_start` (10): generation succeeds for both factions with default options.
- `allowed_tiers`: 60 → 4 tiers; 40 → 3 (Artisan needs bracket 45); 20 → 2 (bracket 150 needs 15, tier 3 bracket needs 30); 10 → 1; a tier that fails stops the prefix even if a later one would pass (synthetic `GameData`).
- Progressive profession items per selected profession == `len(allowed_tiers)`; no profession skill location above the top allowed tier's `max_skill`.
- `milestone_levels(10, 25)` → `[11, 21, 25]`; `milestone_levels(1, 10)` → `2..10`.
- Extra categories at `goal_level` 30: no boss of an instance with `min_level > 30`, no reputation/PvP with `required_level > 30`.
- Rules: goal location needs exactly the brackets below the goal level (`can_reach_level(world.goal_level)`).
- `addon/spec/checks_spec.lua`: zone with `min` 30, `goalLevel` 20 → `"unavailable"` even when its item was received; `goalLevel` missing → old behaviour; start zone stays `"start"`.

## Decisions for the programmer
Resolved 2026-11-18: the programmer accepted every recommendation below (D1 range 10–60, default 60; D2 drop all content above the cap (tiers whose trainer or material level is above it included), zones spanning the cap stay; D3 zones above the cap show as "not in your seed").
- **D1 Range and default.** (a) 10–60, default 60: old YAMLs without the key behave exactly as in v0.1.0. (b) 10–60, default 40: shorter runs by default, but an old YAML silently gets a different game. (c) A higher lower bound (e.g. 20) for more varied seeds at the bottom end. **Recommend (a)**; people who want a shorter run move the slider.
- **D2 Content above the cap.** (a) Leave out everything whose level need is above the goal: zones with `min_level > goal`, quests with `effective_level > goal`, tiers whose trainer level or material bracket is above the goal (longest prefix), bosses/reputations/PvP above it. Zones that span the goal stay, with their low quests. (b) As (a), but clamp material-bracket levels to the goal instead of dropping those tiers (more profession checks, but the logic would expect level-45 materials at level 40). **Recommend (a)**: the logic stays honest.
- **D3 Zones above the cap in the addon.** (a) "Not in your seed": no warning when entering, dark map tint (they are not in the seed). (b) "Locked": warnings and red tint, although no item will ever unlock them. **Recommend (a)**.

## Risks / follow-ups
- Low caps on a small faction set may leave few locations; `items.build_pool` already raises a clear `OptionError` when items do not fit. The range-start test guards it.
- The addon's Data still lists all four tiers; it only ever indexes the first n received, so a capped seed simply never reaches Artisan. The panel shows no "x of 4" tier total today; if it ever does, it must use the slot's tier count.
