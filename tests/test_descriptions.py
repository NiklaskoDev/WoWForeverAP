import dataclasses

import pytest
from worlds.wow_forever import WoWForeverWorld
from worlds.wow_forever import descriptions as desc
from worlds.wow_forever.data_loader import (
    MISC_KINDS,
    MiscItem,
    load_game_data,
    parse_game_data,
    read_shipped_files,
    tier_logic_level,
)
from worlds.wow_forever.items import ITEM_NAME_TO_ID

WESTFALL = (
    "Unlocks Westfall (Alliance, levels 10-20). Once it has arrived you may quest, kill for experience, gather and "
    "loot there; before that, only travel through it. The logic counts it for levels 10-20, and the quest and area "
    "discovery checks in Westfall need it. Group finder teleports into The Deadmines are allowed only once it has "
    "arrived. Left out of seeds whose goal_level is below 10."
)
START_SENTENCE = "It can be the start zone of a seed"
GROUP_FINDER = "Group finder teleports into"


@pytest.fixture(scope="module")
def data():
    return load_game_data()


@pytest.fixture(scope="module")
def texts(data):
    return desc.build_item_descriptions(data)


def changed_data(**replacements):
    """The shipped data with ``old -> new`` replaced in the named CSV texts: ``{"zones.csv": (old, new)}``."""
    files = read_shipped_files()
    for name, (old, new) in replacements.items():
        file = name.replace("_csv", ".csv")
        assert old in files[file], f"fixture drift: {old}"
        files[file] = files[file].replace(old, new, 1)
    return parse_game_data(files)


def test_every_item_of_the_world_has_one_clean_description(texts):
    assert set(texts) == set(ITEM_NAME_TO_ID)
    for name, text in texts.items():
        assert text and text == text.strip() and "\n" not in text, name


def test_the_world_ships_the_generated_descriptions(data):
    assert WoWForeverWorld.web.item_descriptions == desc.build_item_descriptions(data)
    assert set(WoWForeverWorld.web.item_descriptions) <= set(WoWForeverWorld.item_names)


def test_building_twice_gives_the_same_text(data):
    assert desc.build_item_descriptions(data) == desc.build_item_descriptions(load_game_data())


def test_westfall_text_is_pinned(texts):
    assert texts["Zone: Westfall"] == WESTFALL


def test_start_zones_and_level_cut_sentences(texts):
    assert START_SENTENCE in texts["Zone: Elwynn Forest"]
    assert "goal_level is below" not in texts["Zone: Elwynn Forest"]
    for name in ("Zone: Westfall", "Zone: Feralas"):
        assert START_SENTENCE not in texts[name]
    assert "Dire Maul" in texts["Zone: Feralas"]
    assert GROUP_FINDER not in texts["Zone: Darkshore"]
    assert texts["Zone: Darkshore"].endswith("Left out of seeds whose goal_level is below 10.")


def test_several_dungeons_of_one_zone_are_joined_by_level(texts):
    assert ("Group finder teleports into Wailing Caverns, Razorfen Kraul and Razorfen Downs are allowed"
            in texts["Zone: The Barrens"])


def test_boss_sentence_only_exists_with_an_encounter_row(data, texts):
    assert not [name for name, text in texts.items() if "Boss checks" in text]
    files = read_shipped_files()
    files["encounters.csv"] += "9001,Boss A,36,1\n"
    with_boss = desc.build_item_descriptions(parse_game_data(files))
    assert "Boss checks in The Deadmines need it too." in with_boss["Zone: Westfall"]
    assert "Boss checks" not in with_boss["Zone: Darkshore"]


def test_alchemy_names_ranks_logic_levels_and_its_gatherer(texts):
    text = texts["Progressive Alchemy"]
    ranks = ["Apprentice (skill 75, trainer level 5)", "Journeyman (skill 150, trainer level 10)",
             "Expert (skill 225, trainer level 20)", "Artisan (skill 300, trainer level 35)"]
    positions = [text.index(rank) for rank in ranks]
    assert positions == sorted(positions)
    assert "character level 5, 15, 30 and 45 for the ranks in order" in text
    assert "Alchemy is a primary profession" in text
    assert (f"{desc.SELF_FOUND}, its materials come from Herbalism, which must be in the seed with the rank that "
            "reaches them.") in text


def test_material_sentences_per_source_kind(texts):
    assert "come from loot, so the character level is enough." in texts["Progressive Enchanting"]
    assert "it supplies the materials of Alchemy." in texts["Progressive Herbalism"]
    assert "it supplies the materials of Blacksmithing and Engineering." in texts["Progressive Mining"]
    fishing = texts["Progressive Fishing"]
    assert "Fishing is a secondary profession" in fishing and "profession_mode never limits it" in fishing
    assert desc.SELF_FOUND not in fishing


def test_mixed_material_sources_name_both_and_add_no_claim():
    files = read_shipped_files()
    files["profession_materials.csv"] += "171,75,vendor,,0,1,1\n"
    mixed = parse_game_data(files)
    text = desc.profession_description(mixed, mixed.professions_by_id[171])
    assert text.endswith("its materials come from Herbalism or vendors.")


def test_a_csv_change_changes_the_text(texts):
    changed = desc.build_item_descriptions(changed_data(
        profession_tiers_csv=("4,Artisan,300,35,1", "4,Artisan,300,40,1"),
        zones_csv=("1436,Westfall,10,20,", "1436,Westfall,10,22,")))
    assert "Artisan (skill 300, trainer level 40)" in changed["Progressive Alchemy"]
    assert "Artisan (skill 300, trainer level 35)" in texts["Progressive Alchemy"]
    assert "levels 10-22" in changed["Zone: Westfall"] and "levels 10-20" not in changed["Zone: Westfall"]


def test_rows_of_a_later_release_name_it_and_the_first_release_stays_silent(data):
    files = read_shipped_files()
    files["releases.csv"] += "2,later,Later,2027-01-01\n"
    files["zones.csv"] += "9999,Later Land,60,60,both,0,2\n"
    later = parse_game_data(files)
    texts = desc.build_item_descriptions(later)
    assert texts["Zone: Later Land"].startswith("Unlocks Later Land (both factions, levels 60-60, from the Later "
                                                "release).")
    assert texts["Zone: Westfall"] == WESTFALL
    assert desc.release_note(later, 1) == "" and desc.release_note(data, 1) == ""


def test_misc_item_texts(data):
    by_kind = {item.kind: item for item in data.misc_items}
    assert set(by_kind) == set(MISC_KINDS)
    care = desc.misc_item_description(data, by_kind["care_package"])
    assert care.startswith("Allows one pull from a main character: up to care_package_gold gold or "
                           "care_package_stacks stacks of materials")
    assert "The logic never needs it." in care and "moves no gold or items" in care
    filler = desc.misc_item_description(data, by_kind["filler"])
    assert filler == ("Filler: it unlocks nothing. It fills the locations left over after the unlocks and the "
                      "Care Package items.")
    with pytest.raises(KeyError):
        desc.misc_item_description(data, MiscItem(1, "mystery", "Mystery", 1))


@pytest.mark.parametrize("words, last, expected", [
    ([], "and", ""),
    (["a"], "and", "a"),
    (["a", "b"], "and", "a and b"),
    (["a", "b", "c"], "and", "a, b and c"),
    (["a", "b", "c"], "or", "a, b or c"),
])
def test_join_words(words, last, expected):
    assert desc.join_words(words, last) == expected


def test_tier_logic_level_takes_the_higher_of_trainer_and_bracket_level(data):
    assert [tier_logic_level(data, tier) for tier in data.profession_tiers] == [5, 15, 30, 45]


def test_a_tier_above_every_bracket_has_no_logic_level(data):
    assert tier_logic_level(dataclasses.replace(data, material_brackets=()), data.profession_tiers[0]) is None
    tall = dataclasses.replace(data.profession_tiers[0], max_skill=data.material_brackets[-1].max_skill + 1)
    assert tier_logic_level(data, tall) is None
