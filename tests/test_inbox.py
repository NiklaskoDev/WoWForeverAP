import os
from collections import namedtuple
from pathlib import Path

import pytest
from worlds.wow_forever.client import inbox
from worlds.wow_forever.client.lua_table import parse_assignments

Item = namedtuple("Item", "item location player")
ECONOMY = {
    "auctionHouse": True, "trading": True, "mail": False, "sharedBanks": False, "mainBoosts": False,
    "carePackages": 5, "carePackageGold": 50, "carePackageStacks": 5,
}
CATEGORIES = {"boss": True, "discovery": True, "reputation": False, "pvp": False}
SLOT_DATA = {
    "schema": 1, "world_version": "0.1.0", "faction": "alliance", "start_zone": 1429, "content_release": 1,
    "goal_level": 60, "professions": [171, 186], "level_step": 1, "profession_step": 25, "economy": ECONOMY,
    "categories": CATEGORIES,
}
NAMES = {1: "Me", 2: "Friend"}


def make_wow(tmp_path: Path, with_addon: bool = True) -> Path:
    if with_addon:
        (tmp_path / "Interface" / "AddOns" / "WoWForeverAP_Inbox").mkdir(parents=True)
    return tmp_path


def build(seed="seed1", slot="Me", **overrides):
    arguments = dict(
        slot_key=f"{seed}:{slot}", seed=seed, slot=slot, slot_data=SLOT_DATA,
        server_locations=[5110000783, 5120000002, 5130171025], checked=[5120000002],
        received_items=[Item(5110001429, 5110000783, 2), Item(5110001436, 5120000002, 1)], names=NAMES,
        hints=[inbox.hint_entry("Progressive Alchemy", 5120000171, "Quest 7", "Friend", "Me", False, True)],
    )
    arguments.update(overrides)
    return inbox.build(**arguments)


def read_inbox(wow_path: Path) -> dict:
    text = (wow_path / "Interface/AddOns/WoWForeverAP_Inbox/Inbox.lua").read_text(encoding="utf-8")
    return parse_assignments(text)["WoWForeverAP_Inbox"]


def test_build_follows_the_inbox_schema():
    slot = build()
    assert slot == {
        "seed": "seed1", "slot": "Me", "worldVersion": "0.1.0",
        "options": {"faction": "alliance", "startZone": 1429, "contentRelease": 1, "goalLevel": 60,
                    "professions": [171, 186], "levelStep": 1, "professionStep": 25,
                    "economy": ECONOMY, "categories": CATEGORIES},
        "locations": {5110000783: True, 5120000002: True, 5130171025: True},
        "checked": {5120000002: True},
        "items": [{"id": 5110001429, "sender": "Friend", "loc": 5110000783},
                  {"id": 5110001436, "sender": "Me", "loc": 5120000002}],
        "hints": [{"item": "Progressive Alchemy", "itemId": 5120000171, "location": "Quest 7",
                   "finder": "Friend", "receiver": "Me", "found": False, "ourItem": True}],
    }


def test_build_keeps_received_order_and_names_unknown_senders():
    slot = build(received_items=[Item(2, 1, 9), Item(1, 1, 1)])
    assert [item["id"] for item in slot["items"]] == [2, 1]
    assert slot["items"][0]["sender"] == inbox.UNKNOWN_SENDER


def test_build_rejects_slot_data_from_an_incompatible_apworld():
    incomplete = {key: value for key, value in SLOT_DATA.items() if key != "start_zone"}
    with pytest.raises(inbox.InboxError, match="start_zone"):
        build(slot_data=incomplete)


def test_build_requires_the_economy_rules():
    without_economy = {key: value for key, value in SLOT_DATA.items() if key != "economy"}
    with pytest.raises(inbox.InboxError, match="economy"):
        build(slot_data=without_economy)


def test_write_creates_the_file_in_the_inbox_addon_only(tmp_path):
    wow = make_wow(tmp_path)
    path = inbox.write(wow, "seed1:Me", build(), now=lambda: 1763380000)
    assert path == (wow / "Interface/AddOns/WoWForeverAP_Inbox/Inbox.lua").resolve()
    data = read_inbox(wow)
    assert data["schema"] == 1 and data["written"] == 1763380000
    assert data["slots"]["seed1:Me"] == build()
    written = {p.relative_to(wow).as_posix() for p in wow.rglob("*") if p.is_file()}
    assert written == {"Interface/AddOns/WoWForeverAP_Inbox/Inbox.lua"}


def test_write_keeps_other_slots_and_replaces_its_own(tmp_path):
    wow = make_wow(tmp_path)
    inbox.write(wow, "seed1:Me", build())
    inbox.write(wow, "seed2:Other", build(seed="seed2", slot="Other"))
    inbox.write(wow, "seed1:Me", build(checked=[5110000783]))
    slots = read_inbox(wow)["slots"]
    assert set(slots) == {"seed1:Me", "seed2:Other"}
    assert slots["seed1:Me"]["checked"] == {5110000783: True}
    assert slots["seed2:Other"] == build(seed="seed2", slot="Other")


def test_atomic_write_leaves_no_temp_file(tmp_path):
    wow = make_wow(tmp_path)
    inbox.write(wow, "seed1:Me", build())
    inbox.write(wow, "seed1:Me", build())
    assert [p.name for p in (wow / "Interface/AddOns/WoWForeverAP_Inbox").iterdir()] == ["Inbox.lua"]


def test_failed_write_leaves_the_old_file_and_no_temp_file(tmp_path, monkeypatch):
    wow = make_wow(tmp_path)
    inbox.write(wow, "seed1:Me", build())
    before = read_inbox(wow)

    def boom(*_):
        raise OSError("disk full")

    monkeypatch.setattr(os, "replace", boom)
    with pytest.raises(OSError):
        inbox.write(wow, "seed1:Me", build(checked=[5110000783]))
    assert read_inbox(wow) == before
    assert [p.name for p in (wow / "Interface/AddOns/WoWForeverAP_Inbox").iterdir()] == ["Inbox.lua"]


def test_corrupt_existing_inbox_is_replaced(tmp_path):
    wow = make_wow(tmp_path)
    (wow / "Interface/AddOns/WoWForeverAP_Inbox/Inbox.lua").write_text("WoWForeverAP_Inbox = { slots = {")
    inbox.write(wow, "seed1:Me", build())
    assert set(read_inbox(wow)["slots"]) == {"seed1:Me"}


def test_placeholder_inbox_shipped_with_the_addon_is_accepted(tmp_path):
    wow = make_wow(tmp_path)
    (wow / "Interface/AddOns/WoWForeverAP_Inbox/Inbox.lua").write_text(
        "WoWForeverAP_Inbox = { schema = 1, slots = {} }\n")
    inbox.write(wow, "seed1:Me", build())
    assert set(read_inbox(wow)["slots"]) == {"seed1:Me"}


def test_missing_inbox_addon_folder_is_a_clear_error(tmp_path):
    wow = make_wow(tmp_path, with_addon=False)
    with pytest.raises(inbox.InboxError, match="install the WoWForeverAP_Inbox addon"):
        inbox.write(wow, "seed1:Me", build())
    assert not (wow / "Interface").exists()


def test_inbox_file_resolving_outside_the_wow_path_is_refused(tmp_path):
    wow = make_wow(tmp_path / "wow")
    outside = tmp_path / "elsewhere"
    outside.mkdir()
    target = outside / "Inbox.lua"
    target.write_text("untouched")
    (wow / "Interface/AddOns/WoWForeverAP_Inbox/Inbox.lua").symlink_to(target)
    with pytest.raises(inbox.InboxError, match="outside the WoW folder"):
        inbox.write(wow, "seed1:Me", build())
    assert target.read_text() == "untouched"


def test_addon_folder_symlinked_outside_the_wow_path_is_refused(tmp_path):
    wow = tmp_path / "wow"
    (wow / "Interface" / "AddOns").mkdir(parents=True)
    outside = tmp_path / "elsewhere"
    outside.mkdir()
    (wow / "Interface/AddOns/WoWForeverAP_Inbox").symlink_to(outside, target_is_directory=True)
    with pytest.raises(inbox.InboxError, match="outside the WoW folder"):
        inbox.write(wow, "seed1:Me", build())
    assert list(outside.iterdir()) == []


def test_hostile_player_names_stay_inert_strings(tmp_path):
    wow = make_wow(tmp_path)
    hostile = '"]] end os.exit() --' + "x" * 500
    slot = build(received_items=[Item(1, 1, 2)], names={2: hostile})
    inbox.write(wow, "seed1:Me", slot)
    sender = read_inbox(wow)["slots"]["seed1:Me"]["items"][0]["sender"]
    assert sender == hostile[:200]


# --- hints ---------------------------------------------------------------------------------

def hint(item="Progressive Alchemy", location="Quest 7", found=False, our_item=True, **overrides):
    entry = inbox.hint_entry(item=item, item_id=5120000171, location=location, finder="Friend", receiver="Me",
                             found=found, our_item=our_item)
    entry.update(overrides)
    return entry


def test_build_without_hints_writes_an_empty_list():
    assert build(hints=[])["hints"] == []
    assert inbox.build("k", "seed", "Me", SLOT_DATA, [], [], [], NAMES)["hints"] == []


def test_hints_are_capped_and_found_ones_are_dropped_first():
    many = [hint(location=f"Location {number:04d}", found=number % 2 == 0) for number in range(inbox.MAX_HINTS + 50)]
    kept = build(hints=many)["hints"]
    assert len(kept) == inbox.MAX_HINTS
    assert not any(entry["found"] for entry in kept[:inbox.MAX_HINTS // 2])
    assert [entry["found"] for entry in kept] == sorted(entry["found"] for entry in kept)
    assert inbox.MAX_HINTS == 200


def test_hint_order_is_stable_whatever_order_the_server_sent():
    first = [hint(location="B"), hint(location="A", found=True), hint(location="C")]
    assert build(hints=first)["hints"] == build(hints=list(reversed(first)))["hints"]
    assert [entry["location"] for entry in build(hints=first)["hints"]] == ["B", "C", "A"]


def test_malformed_hints_are_dropped():
    broken = [
        hint(item=5), hint(location=None), hint(found="yes"), hint(our_item=1), hint(itemId="7"),
        hint(itemId=True), "not a hint", None, {"item": "x"},
    ]
    assert build(hints=[*broken, hint()])["hints"] == [hint()]


def test_hostile_hint_strings_stay_inert_strings(tmp_path):
    wow = make_wow(tmp_path)
    hostile = '"]] end os.exit() --' + "x" * 500
    slot = build(hints=[hint(item=hostile, location=hostile, finder=hostile, receiver=hostile)])
    inbox.write(wow, "seed1:Me", slot)
    written = read_inbox(wow)["slots"]["seed1:Me"]["hints"][0]
    for key in ("item", "location", "finder", "receiver"):
        assert written[key] == hostile[:200]
    assert written["found"] is False and written["ourItem"] is True
