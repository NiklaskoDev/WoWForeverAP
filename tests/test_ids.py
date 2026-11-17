import pytest
from worlds.wow_forever import ids
from worlds.wow_forever.ids import BASE, CATEGORY_SIZE, ItemCat, LocCat


@pytest.mark.parametrize("category", list(LocCat))
def test_location_id_round_trips_for_every_category(category):
    for native in (0, 1, 12345, CATEGORY_SIZE - 1):
        assert ids.decode(ids.location_id(category, native)) == (category, native)


@pytest.mark.parametrize("category", list(ItemCat))
def test_item_id_round_trips_for_every_category(category):
    for native in (0, 1, 12345, CATEGORY_SIZE - 1):
        assert ids.decode(ids.item_id(category, native)) == (category, native)


def test_known_values_are_stable():
    # These are published to players: a change here breaks existing multiworlds.
    assert BASE == 5_100_000_000
    assert ids.location_id(LocCat.QUEST, 783) == 5_110_000_783
    assert ids.location_id(LocCat.LEVEL, 60) == 5_120_000_060
    assert ids.item_id(ItemCat.ZONE, 1429) == 5_110_001_429


def test_category_numbers_are_permanent():
    assert [int(c) for c in LocCat] == [1, 2, 3, 4, 5, 6, 7, 8]
    assert [int(c) for c in ItemCat] == [1, 2, 3, 4, 5]
    assert (LocCat.QUEST, LocCat.LEVEL, LocCat.PROFESSION_SKILL) == (1, 2, 3)
    assert (ItemCat.ZONE, ItemCat.PROFESSION_TIER, ItemCat.FILLER) == (1, 2, 3)


@pytest.mark.parametrize("native", [-1, CATEGORY_SIZE, CATEGORY_SIZE + 5])
def test_native_out_of_range_is_rejected(native):
    with pytest.raises(ValueError):
        ids.location_id(LocCat.QUEST, native)
    with pytest.raises(ValueError):
        ids.item_id(ItemCat.ZONE, native)


@pytest.mark.parametrize("category", [0, 9, 99, -1])
def test_unknown_category_is_rejected(category):
    with pytest.raises(ValueError):
        ids.location_id(category, 1)
    with pytest.raises(ValueError):
        ids.item_id(category, 1)


def test_item_and_location_category_tables_are_separate():
    # Item category 5 is valid; location category 5 is a different, reserved meaning.
    assert ids.item_id(ItemCat.DUNGEON_ACCESS, 1) == BASE + 5 * CATEGORY_SIZE + 1
    assert ids.location_id(LocCat.AREA_DISCOVERY, 1) == BASE + 5 * CATEGORY_SIZE + 1
    with pytest.raises(ValueError):
        ids.item_id(6, 1)


def test_decode_rejects_ids_below_base():
    with pytest.raises(ValueError):
        ids.decode(BASE - 1)


def test_profession_skill_native_combines_line_and_skill():
    assert ids.profession_skill_native(171, 75) == 171_075
    assert ids.decode(ids.location_id(LocCat.PROFESSION_SKILL, ids.profession_skill_native(171, 75))) == (3, 171_075)
    with pytest.raises(ValueError):
        ids.profession_skill_native(171, 1000)
    with pytest.raises(ValueError):
        ids.profession_skill_native(171, -1)
