import logging
import shutil
from pathlib import Path

from worlds.wow_forever.client import savedvars

FIXTURES = Path(__file__).parent / "fixtures"
SLOT = 'AP_1234:Wow"Slot'
OTHER_SLOT = "OTHER_SEED:Other"


def install(wow_path: Path, account: str, fixture: str) -> Path:
    target = wow_path / "WTF" / "Account" / account / "SavedVariables" / "WoWForeverAP.lua"
    target.parent.mkdir(parents=True)
    shutil.copy(FIXTURES / fixture, target)
    return target


def test_find_files_lists_every_account_in_stable_order(tmp_path):
    second = install(tmp_path, "ACCOUNT2", "WoWForeverAP_other_account.lua")
    first = install(tmp_path, "ACCOUNT1", "WoWForeverAP_two_chars.lua")
    (tmp_path / "WTF" / "Account" / "ACCOUNT1" / "SavedVariables" / "Other.lua").write_text("X = 1")
    assert savedvars.find_files(tmp_path) == [first, second]


def test_find_files_without_wtf_folder_is_empty(tmp_path):
    assert savedvars.find_files(tmp_path) == []


def test_two_accounts_are_merged(tmp_path):
    install(tmp_path, "ACCOUNT1", "WoWForeverAP_two_chars.lua")
    install(tmp_path, "ACCOUNT2", "WoWForeverAP_other_account.lua")
    state = savedvars.read_all(tmp_path)
    assert state.outbox_ids(SLOT) == {5110000783, 5120000002, 5110000007}  # 783 reported by both, counted once
    assert state.linked_count(SLOT) == 2  # one character per account; the unlinked character is not counted
    assert state.goal_reached(SLOT) is True


def test_only_the_requested_slot_key_is_returned(tmp_path):
    install(tmp_path, "ACCOUNT1", "WoWForeverAP_two_chars.lua")
    install(tmp_path, "ACCOUNT2", "WoWForeverAP_other_account.lua")
    state = savedvars.read_all(tmp_path)
    assert state.outbox_ids(OTHER_SLOT) == {5110000999}
    assert state.linked_count(OTHER_SLOT) == 1
    assert state.goal_reached(OTHER_SLOT) is False
    assert state.outbox_ids("unknown:slot") == set()
    assert state.linked_count("unknown:slot") == 0
    assert state.goal_reached("unknown:slot") is False


def test_unparseable_file_is_skipped_with_a_warning(tmp_path, caplog):
    install(tmp_path, "ACCOUNT1", "WoWForeverAP_two_chars.lua")
    broken = install(tmp_path, "ACCOUNT2", "WoWForeverAP_broken.lua")
    with caplog.at_level(logging.WARNING, logger=savedvars.LOGGER.name):
        state = savedvars.read_all(tmp_path)
    assert state.outbox_ids(SLOT) == {5110000783, 5120000002}
    assert any(str(broken) in record.getMessage() for record in caplog.records)


def test_non_check_entries_and_malformed_values_are_ignored(tmp_path):
    target = tmp_path / "WTF" / "Account" / "A" / "SavedVariables" / "WoWForeverAP.lua"
    target.parent.mkdir(parents=True)
    target.write_text(
        'WoWForeverAP_DB = { slots = { s = { outbox = { { kind = "death", id = 5 }, { kind = "check", id = "x" },'
        ' { kind = "check", id = true }, "junk", { kind = "check", id = 7 } }, goal = "nope" } },'
        ' characters = { a = "junk", b = { slotKey = "s" } } }'
    )
    state = savedvars.read_all(tmp_path)
    assert state.outbox_ids("s") == {7}
    assert state.goal_reached("s") is False
    assert state.linked_count("s") == 1


def test_file_without_the_database_variable_reads_as_empty(tmp_path):
    target = tmp_path / "WTF" / "Account" / "A" / "SavedVariables" / "WoWForeverAP.lua"
    target.parent.mkdir(parents=True)
    target.write_text("SomethingElse = {}")
    assert savedvars.read_all(tmp_path).outbox_ids("s") == set()
