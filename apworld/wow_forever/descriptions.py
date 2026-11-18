"""Player-facing item descriptions, generated from the game data.

Pure module (imports only ``data_loader``) so ``tools/gen_addon_data.py`` can use it without Archipelago. The texts
only restate what the data files say: the rows are provisional, and a description is seed-independent, so options
such as ``goal_level`` and ``faction`` are named, never assumed.
"""
from collections.abc import Sequence

from .data_loader import (
    MATERIAL_SOURCES,
    GameData,
    Instance,
    MiscItem,
    Profession,
    Zone,
    tier_logic_level,
)

FACTION_LABELS = {"alliance": "Alliance", "horde": "Horde", "both": "both factions"}
SELF_FOUND = "With the Auction House, trading, mail and shared banks all off"
SOURCE_WORDS = {"drops": "loot", "vendor": "vendors"}


def join_words(words: Sequence[str], last: str = "and") -> str:
    """``a``, ``a and b``, ``a, b and c``; ``last="or"`` for alternatives."""
    if len(words) <= 1:
        return "".join(words)
    return f"{', '.join(words[:-1])} {last} {words[-1]}"


def release_note(data: GameData, release: int) -> str:
    """Names the release of a row inside parentheses; empty for the first release, which needs no mention."""
    if release == min(r.id for r in data.releases):
        return ""
    return f", from the {data.releases_by_id[release].label} release"


def zone_instances(data: GameData, zone: Zone) -> list[Instance]:
    """The instances whose entrance is in ``zone``, lowest level first."""
    return sorted((i for i in data.instances if i.entrance_ui_map_id == zone.ui_map_id),
                  key=lambda i: (i.min_level, i.name))


def material_parts(data: GameData, profession: Profession) -> tuple[list[str], bool]:
    """Where the profession's main material comes from: the gathering professions, then the other sources. The flag
    says that every row is a gathering row."""
    rows = [m for m in data.profession_materials if m.crafting_skill_line_id == profession.skill_line_id]
    gatherer_ids = {m.gather_skill_line_id for m in rows if m.source == "gather"}
    parts = [p.name for p in data.professions if p.skill_line_id in gatherer_ids]
    sources = {m.source for m in rows}
    parts += [SOURCE_WORDS[source] for source in MATERIAL_SOURCES if source in sources and source in SOURCE_WORDS]
    return parts, all(m.source == "gather" for m in rows)


def supplied_professions(data: GameData, profession: Profession) -> list[Profession]:
    """The crafting professions whose material this (gathering) profession supplies."""
    crafting_ids = {m.crafting_skill_line_id for m in data.profession_materials
                    if m.source == "gather" and m.gather_skill_line_id == profession.skill_line_id}
    return [p for p in data.professions if p.skill_line_id in crafting_ids]


def materials_summary(data: GameData, profession: Profession) -> str:
    """The guide table cell for the self-found materials of a profession."""
    parts, _ = material_parts(data, profession)
    if parts:
        return join_words(parts, "or")
    supplied = supplied_professions(data, profession)
    if supplied:
        return "supplies " + join_words([p.name for p in supplied])
    return "-"


def zone_description(data: GameData, zone: Zone) -> str:
    span = f"{zone.min_level}-{zone.max_level}"
    instances = zone_instances(data, zone)
    boss_instances = [i for i in instances if any(e.instance_id == i.instance_id for e in data.encounters)]
    sentences = [
        f"Unlocks {zone.name} ({FACTION_LABELS[zone.faction]}, levels {span}{release_note(data, zone.release)}).",
        "Once it has arrived you may quest, kill for experience, gather and loot there; before that, only travel "
        "through it.",
        f"The logic counts it for levels {span}, and the quest and area discovery checks in {zone.name} need it.",
    ]
    if instances:
        sentences.append("Group finder teleports into "
                         f"{join_words([i.name for i in instances])} are allowed only once it has arrived.")
    if boss_instances:
        sentences.append(f"Boss checks in {join_words([i.name for i in boss_instances])} need it too.")
    if zone.is_start:
        sentences.append("It can be the start zone of a seed, which is unlocked from the beginning.")
    if zone.min_level > 1:
        sentences.append(f"Left out of seeds whose goal_level is below {zone.min_level}.")
    return " ".join(sentences)


def _material_sentence(data: GameData, profession: Profession) -> str | None:
    parts, all_gather = material_parts(data, profession)
    if parts:
        sources = join_words(parts, "or")
        rows = [m for m in data.profession_materials if m.crafting_skill_line_id == profession.skill_line_id]
        if all_gather:
            ending = ", which must be in the seed with the rank that reaches them"
        elif all(m.source != "gather" for m in rows):
            ending = ", so the character level is enough"
        else:
            ending = ""
        return f"{SELF_FOUND}, its materials come from {sources}{ending}."
    supplied = supplied_professions(data, profession)
    if supplied:
        return f"{SELF_FOUND}, it supplies the materials of {join_words([p.name for p in supplied])}."
    return None


def profession_description(data: GameData, profession: Profession) -> str:
    tiers = sorted(data.profession_tiers, key=lambda t: t.tier)
    ranks = [f"{t.name} (skill {t.max_skill}, trainer level {t.required_level}{release_note(data, t.release)})"
             for t in tiers]
    levels = [str(level) for level in (tier_logic_level(data, t) for t in tiers) if level is not None]
    if profession.kind == "primary":
        kind = (f"{profession.name} is a primary profession: it is in the seed when listed in professions, and "
                "profession_mode solo or team can limit the primaries.")
    else:
        kind = (f"{profession.name} is a secondary profession: it is in the seed when listed in professions, and "
                "profession_mode never limits it.")
    sentences = [
        f"Each copy unlocks the next {profession.name} rank you may train: {join_words(ranks)}.",
        "Do not train a rank before its copy has arrived.",
        f"In the logic, {profession.name} skill checks up to a rank's cap need that rank and character level "
        f"{join_words(levels)} for the ranks in order; a seed whose goal_level is below a rank's level leaves that "
        "rank and every later one out.",
        kind,
    ]
    materials = _material_sentence(data, profession)
    if materials:
        sentences.append(materials)
    return " ".join(sentences)


def misc_item_description(data: GameData, item: MiscItem) -> str:
    """Text by item kind; a kind without a text raises ``KeyError``."""
    texts = {
        "care_package": (
            "Allows one pull from a main character: up to care_package_gold gold or care_package_stacks stacks of "
            "materials, as set in your options (care_packages sets how many are in the pool). The logic never "
            "needs it. In the game, /wfap care counts the ones received and used; the tool moves no gold or items."),
        "filler": (
            f"Filler: it unlocks nothing. It fills the locations left over after the unlocks and the "
            f"{data.care_package.name} items."),
    }
    return texts[item.kind]


def build_item_descriptions(data: GameData) -> dict[str, str]:
    """Item name -> description for every zone, profession and misc item (the keys of the world's item table)."""
    descriptions = {zone.item_name: zone_description(data, zone) for zone in data.zones}
    descriptions.update({p.item_name: profession_description(data, p) for p in data.professions})
    descriptions.update({item.name: misc_item_description(data, item) for item in data.misc_items})
    return descriptions
