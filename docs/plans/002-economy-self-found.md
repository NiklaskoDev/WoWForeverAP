# 002 — Economy and self-found rules

Status: implemented
Type: feature
Version impact: none until release — part of the first release together with 001, 003 and 004 (expected `0.1.0`). Must land before the first release, because it changes profession logic and adds an item category.

## Goal
Options for the Auction House, trading, mail, shared banks (guild and account/warband bank) and boosts from mains. Profession logic follows them, from strict self-found to an alt funded by a main. "Care Package" items each allow one honor-system pull of a set amount of gold or materials from a main. The addon warns when a disallowed economy window opens and tracks care packages that have been used. (Scout feature #5.)
Out of scope: everything declined in 001 (#7–#10); no new UI windows (003 shows these rules in its panel).

## Reuse
- 001: `rules.has_material_access` (the seam this plan extends), `profession_tiers.csv`, `material_brackets.csv`, `ids.ItemCat` (category 4 is reserved for care packages), `items.build_pool`, `fill_slot_data`, inbox `options`, `UI/Notify.lua`, `Locales/*`, `Core/DB.lua` slot table, `Commands.lua`.
- New: `profession_materials.csv`. 001's `material_brackets.csv` only knows levels, not which profession supplies a crafting profession.

## Code layout
- `apworld/wow_forever/data/profession_materials.csv` — new: material sources per crafting profession.
- `apworld/wow_forever/data/misc_items.csv` — add care package row (`kind=care_package`).
- `apworld/wow_forever/data_loader.py` — load and validate `profession_materials.csv`; `kind` accepts `care_package`.
- `apworld/wow_forever/options.py` — new options (below).
- `apworld/wow_forever/rules.py` — extend `has_material_access`; add `has_market_access`.
- `apworld/wow_forever/items.py` — add care packages to the pool.
- `apworld/wow_forever/__init__.py` — `generate_early` validation; `fill_slot_data` adds `economy`.
- `apworld/wow_forever/client/inbox.py` — copy `economy` into inbox `options`.
- `tools/gen_addon_data.py` — add `carePackageItemId`.
- `addon/WoWForeverAP/Rules/Economy.lua` — new: interaction warnings and care package counter.
- `addon/WoWForeverAP/Core/DB.lua` — `slots[k].carePackagesUsed`.
- `addon/WoWForeverAP/Commands.lua` — `/wfap rules`, `/wfap care`, `/wfap care use`.
- `addon/WoWForeverAP/Locales/enUS.lua`, `deDE.lua` — strings.
- `apworld/wow_forever/docs/*.md` — explain the economy rules.
- Tests: `tests/test_economy_rules.py`, `tests/test_world.py` (extend), `addon/spec/economy_spec.lua`.

## Data
- `profession_materials.csv`: `crafting_skill_line_id:int` (FK professions), `max_skill:int` (bracket upper bound), `source:gather|drops|vendor`, `gather_skill_line_id:int` (empty unless `source=gather`; several rows = any of them), `gather_skill:int` (gathering skill needed), `required_level:int`, `release:int`. PK (`crafting_skill_line_id`, `max_skill`, `source`, `gather_skill_line_id`).
- `misc_items.csv`: row `1,care_package,Care Package,1` → item id `ids.item_id(ItemCat.CARE_PACKAGE, 1)`; the loader maps `kind=care_package` to category 4.
- SV: `slots[slotKey].carePackagesUsed = <int>` (schema stays 1; missing field = 0).
- Slot data / inbox `options.economy = { auctionHouse=bool, trading=bool, mail=bool, sharedBanks=bool, mainBoosts=bool, carePackages=int, carePackageGold=int, carePackageStacks=int }`.

## Interfaces
Options (defaults in brackets):
- `AllowAuctionHouse(DefaultOnToggle)` [on]; `AllowTrading(DefaultOnToggle)` [on]; `AllowMail(DefaultOnToggle)` [on]; `AllowSharedBanks(Toggle)` [off]; `AllowMainBoosts(Toggle)` [off] (dungeon carries and power levelling by a main; honor only, no logic effect).
- `CarePackages(Range 0–20)` [5]; `CarePackageGold(Range 0–10000)` [50]; `CarePackageStacks(Range 0–20)` [5].

Rules:
- `has_market_access(world) -> bool` = any of AH, trading, mail, shared banks.
- `has_material_access(state, world, line, skill)`:
  - market → 001 behaviour (`can_reach_level(bracket.required_level)`).
  - otherwise use the `profession_materials` rows of the bracket that covers `skill`: true if any row is satisfied — `drops`/`vendor`: `can_reach_level(required_level)`; `gather`: gathering profession selected, `state.count("Progressive <gather>") >= tier_for(gather_skill)` and `can_reach_level(required_level)`.
  - professions without rows (gathering professions themselves) → 001 behaviour.
- Care packages are not counted in logic (convenience only).
- `generate_early`: when there is no market access and a selected crafting profession has a bracket whose only sources are gathering professions that are not selected → `OptionError` naming the profession and the missing gathering professions.
- Item pool: `CarePackages` copies of `Care Package` (classification `useful`), placed before filler; still subject to 001's "more items than locations" check (care packages are removed first, then `OptionError`).

Addon:
- `Rules/Economy.lua`: on `PLAYER_INTERACTION_MANAGER_FRAME_SHOW(type)` warn when the type maps to a disallowed rule — `Enum.PlayerInteractionType.Auctioneer` → AH, `MailInfo` → mail, `TradePartner` → trading, `GuildBanker`/`AccountBanker` → shared banks (verify enum names in the live client, D2 of 001). Warning = `UIErrorsFrame:AddMessage` + chat line; with mail disallowed and care packages left, the line adds "a Care Package allows one pull from your main".
- Care packages: available = received `Care Package` count (inbox items) − `carePackagesUsed`. `/wfap care` shows it; `/wfap care use` asks via `StaticPopup` and increments. Never below 0.
- `/wfap rules` prints the active economy rules for the linked slot.

## Security and user data
None. Care packages are honor-system permissions; the tool never moves gold or items.

## UI
Chat lines, `UIErrorsFrame` warnings, one confirmation `StaticPopup`. Same prefix and colour as 001.

## Steps
1. Add the CSV and the misc item row; extend `data_loader` + validation tests.
2. Options and `fill_slot_data`; inbox `economy`.
3. Rules: `has_market_access`, extended `has_material_access`, `generate_early` validation.
4. Item pool with care packages.
5. Python tests.
6. Regenerate `Generated.lua`; addon `Rules/Economy.lua`, DB field, commands, locales; TOC file list.
7. busted specs.
8. Docs, `CHANGELOG.md` `[Unreleased]`.

## Tests
- Market on → Blacksmithing 200 needs only levels; all market options off → Blacksmithing 200 needs Mining at the right tier.
- Self-found, Blacksmithing selected without Mining → `OptionError` naming Mining.
- Tailoring (drops) in self-found needs only level.
- `CarePackages=5` → five `Care Package` items in the pool; too few locations → care packages dropped before `OptionError`.
- Default options still beatable; slot data contains `economy` with every key.
- Lua: interaction warnings fire only for disallowed types; available count = received − used, never negative; `use` with 0 available refuses.

## Decisions for the programmer
Resolved 2026-11-17: the programmer accepted every recommendation below.
- **Care packages in logic?** (a) Not in logic (convenience only). (b) Each package counts as material access for one bracket. **Recommend (a)**: simpler and never forces a pull.
- **Default strictness.** (a) Market allowed, banks and boosts off (above). (b) Strict self-found by default. **Recommend (a)**: friendlier for levelling alts, which is the project's purpose.

## Risks / follow-ups
- Material source data (`profession_materials.csv`) is hand-curated like 001's data (001 D1).
- `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` and the enum names must exist in Forever's API (001 D2); otherwise fall back to `AUCTION_HOUSE_SHOW`, `MAIL_SHOW`, `TRADE_SHOW`, `GUILDBANKFRAME_OPENED`.
