import asyncio
import shutil
from pathlib import Path

from worlds.wow_forever.client import wow_client
from worlds.wow_forever.client.lua_table import parse_assignments
from worlds.wow_forever.client.wow_client import goal_to_send, pending_checks, slot_key_for

FIXTURES = Path(__file__).parent / "fixtures"
SEED = "AP_1234"
SLOT_NAME = 'Wow"Slot'


# --- pure decisions -------------------------------------------------------------------------

def test_pending_is_outbox_intersect_server_minus_checked():
    assert pending_checks({1, 2, 3, 4}, {2}, {1, 2, 3}) == {1, 3}


def test_locations_unknown_to_the_server_are_never_sent():
    assert pending_checks({10, 11}, set(), {11}) == {11}


def test_nothing_pending_when_everything_is_checked_or_outbox_is_empty():
    assert pending_checks({1, 2}, {1, 2}, {1, 2}) == set()
    assert pending_checks(set(), set(), {1}) == set()


def test_pending_accepts_any_iterable():
    assert pending_checks([1, 1, 2], (2,), iter([1, 2])) == {1}


def test_goal_is_sent_once():
    assert goal_to_send(True, False) is True
    assert goal_to_send(True, True) is False
    assert goal_to_send(False, False) is False
    assert goal_to_send(False, True) is False


def test_slot_key_combines_seed_and_slot_name():
    assert slot_key_for("seed", "Slot") == "seed:Slot"


# --- context against fixture files ---------------------------------------------------------

def make_wow(tmp_path: Path) -> Path:
    save = tmp_path / "WTF" / "Account" / "A" / "SavedVariables"
    save.mkdir(parents=True)
    shutil.copy(FIXTURES / "WoWForeverAP_two_chars.lua", save / "WoWForeverAP.lua")
    (tmp_path / "Interface" / "AddOns" / "WoWForeverAP_Inbox").mkdir(parents=True)
    return tmp_path


class RecordingContext(wow_client.WoWForeverContext):
    def __init__(self):
        super().__init__(None, None)
        self.sent: list[dict] = []

    async def send_msgs(self, msgs):
        self.sent.extend(msgs)


def connected_context(wow_path: Path) -> RecordingContext:
    ctx = RecordingContext()
    ctx.wow_path = wow_path
    ctx.server_seed_name = SEED
    ctx.auth = SLOT_NAME
    ctx.slot = 1
    ctx.slot_data = {
        "schema": 1, "world_version": "0.1.0", "faction": "alliance", "start_zone": 1429, "content_release": 1,
        "goal_level": 60, "professions": [171], "level_step": 1, "profession_step": 25,
        "economy": {"auctionHouse": True, "trading": True, "mail": True, "sharedBanks": False, "mainBoosts": False,
                    "carePackages": 5, "carePackageGold": 50, "carePackageStacks": 5},
    }
    ctx.server_locations = {5110000783, 5120000002, 5110000007}
    ctx.missing_locations = set(ctx.server_locations)
    ctx.checked_locations = set()
    return ctx


def run_with_context(wow_path: Path, scenario):
    async def runner():
        ctx = connected_context(wow_path)
        try:
            await scenario(ctx)
        finally:
            ctx.keep_alive_task.cancel()
        return ctx

    return asyncio.run(runner())


def test_sync_sends_pending_checks_and_the_goal(tmp_path):
    wow = make_wow(tmp_path)

    async def scenario(ctx):
        await ctx.sync_from_savedvars()

    ctx = run_with_context(wow, scenario)
    check_messages = [m for m in ctx.sent if m["cmd"] == "LocationChecks"]
    assert len(check_messages) == 1
    assert set(check_messages[0]["locations"]) == {5110000783, 5120000002}  # 5110000007 is not in the outbox
    assert {"cmd": "StatusUpdate", "status": 30} in ctx.sent  # ClientStatus.CLIENT_GOAL
    assert ctx.finished_game is True


def test_second_sync_sends_nothing_new_and_goal_only_once(tmp_path):
    wow = make_wow(tmp_path)

    async def scenario(ctx):
        await ctx.sync_from_savedvars()
        ctx.checked_locations |= {5110000783, 5120000002}
        ctx.missing_locations -= ctx.checked_locations
        ctx.sent.clear()
        await ctx.sync_from_savedvars()

    ctx = run_with_context(wow, scenario)
    assert ctx.sent == []


def test_sync_does_not_send_for_another_slot(tmp_path):
    wow = make_wow(tmp_path)

    async def scenario(ctx):
        ctx.auth = "SomeoneElse"
        await ctx.sync_from_savedvars()

    assert run_with_context(wow, scenario).sent == []


def test_sync_without_connection_or_path_sends_nothing(tmp_path):
    wow = make_wow(tmp_path)

    async def scenario(ctx):
        ctx.slot_data = {}
        await ctx.sync_from_savedvars()
        ctx.wow_path = None
        await ctx.sync_from_savedvars()

    assert run_with_context(wow, scenario).sent == []


def test_write_inbox_publishes_the_server_view(tmp_path):
    wow = make_wow(tmp_path)

    async def scenario(ctx):
        ctx.checked_locations = {5120000002}
        await ctx.write_inbox()

    run_with_context(wow, scenario)
    text = (wow / "Interface/AddOns/WoWForeverAP_Inbox/Inbox.lua").read_text(encoding="utf-8")
    slot = parse_assignments(text)["WoWForeverAP_Inbox"]["slots"][f"{SEED}:{SLOT_NAME}"]
    assert slot["checked"] == {5120000002: True}
    assert slot["options"]["startZone"] == 1429


def test_write_inbox_reports_a_missing_addon_once(tmp_path, caplog):
    wow = make_wow(tmp_path)
    shutil.rmtree(wow / "Interface")

    async def scenario(ctx):
        await ctx.write_inbox()
        await ctx.write_inbox()

    with caplog.at_level("ERROR", logger="Client"):
        run_with_context(wow, scenario)
    messages = [r.getMessage() for r in caplog.records if "install the WoWForeverAP_Inbox addon" in r.getMessage()]
    assert len(messages) == 1


def test_status_lines_report_linked_characters_and_pending_checks(tmp_path):
    wow = make_wow(tmp_path)
    lines: list[str] = []

    async def scenario(ctx):
        await ctx.sync_from_savedvars()
        ctx.checked_locations = set()
        lines.extend(ctx.status_lines())

    run_with_context(wow, scenario)
    text = "\n".join(lines)
    assert "Linked characters: 1" in text
    assert "Checks waiting to be sent: 2" in text
    assert "Inbox.lua" in text


# --- commands ------------------------------------------------------------------------------

def run_commands(wow_path: Path, commands: list[str], monkeypatch):
    stored: list[Path] = []
    monkeypatch.setattr(wow_client, "store_wow_path", stored.append)
    outputs: list[str] = []

    async def scenario(ctx):
        processor = ctx.command_processor(ctx)
        processor.output = outputs.append
        for command in commands:
            processor(command)

    ctx = run_with_context(wow_path, scenario)
    return ctx, stored, outputs


def test_wowpath_sets_and_stores_an_existing_folder_with_spaces(tmp_path, monkeypatch):
    target = tmp_path / "World of Warcraft" / "_forever_"
    target.mkdir(parents=True)
    ctx, stored, outputs = run_commands(tmp_path, [f"/wowpath {target}"], monkeypatch)
    assert ctx.wow_path == target
    assert stored == [target]
    assert any("WoW path set" in line for line in outputs)


def test_wowpath_rejects_a_missing_folder(tmp_path, monkeypatch):
    ctx, stored, outputs = run_commands(tmp_path, [f"/wowpath {tmp_path / 'nope'}"], monkeypatch)
    assert ctx.wow_path == tmp_path
    assert stored == []
    assert any("is not a folder" in line for line in outputs)


def test_wowpath_without_argument_shows_the_current_path(tmp_path, monkeypatch):
    _, stored, outputs = run_commands(tmp_path, ["/wowpath"], monkeypatch)
    assert stored == []
    assert outputs == [f"WoW path: {tmp_path}"]


def test_sync_command_requests_a_resync(tmp_path, monkeypatch):
    async def scenario(ctx):
        ctx.sync_requested = False
        ctx.command_processor(ctx)("/sync")
        assert ctx.sync_requested is True
        assert ctx.inbox_dirty.is_set()

    run_with_context(tmp_path, scenario)


# --- watcher loop --------------------------------------------------------------------------

def test_watch_loop_survives_an_unexpected_error_and_keeps_syncing(tmp_path, monkeypatch, caplog):
    wow = make_wow(tmp_path)
    monkeypatch.setattr(wow_client, "POLL_SECONDS", 0.01)
    calls = []

    async def scenario(ctx):
        async def flaky_sync():
            calls.append(len(calls) + 1)
            if len(calls) == 1:
                ctx.sync_requested = True  # force another round without touching the files
                raise RuntimeError("boom")
            ctx.exit_event.set()

        ctx.sync_from_savedvars = flaky_sync
        await asyncio.wait_for(wow_client.sv_watch_loop(ctx), timeout=5)

    with caplog.at_level("ERROR", logger="Client"):
        run_with_context(wow, scenario)
    assert calls == [1, 2]
    assert any("Unexpected error while syncing" in r.getMessage() and r.exc_info for r in caplog.records)


def test_inbox_writer_loop_survives_an_unexpected_error_and_keeps_writing(tmp_path, monkeypatch, caplog):
    monkeypatch.setattr(wow_client, "INBOX_DEBOUNCE_SECONDS", 0.01)
    calls = []

    async def scenario(ctx):
        async def flaky_write():
            calls.append(len(calls) + 1)
            if len(calls) == 1:
                ctx.inbox_dirty.set()  # ask for another round
                raise RuntimeError("boom")
            ctx.exit_event.set()

        ctx.write_inbox = flaky_write
        ctx.inbox_dirty.set()
        await asyncio.wait_for(wow_client.inbox_writer_loop(ctx), timeout=5)

    with caplog.at_level("ERROR", logger="Client"):
        run_with_context(tmp_path, scenario)
    assert calls == [1, 2]
    assert any("Unexpected error while writing the inbox" in r.getMessage() and r.exc_info for r in caplog.records)
