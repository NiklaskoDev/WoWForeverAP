"""Archipelago client for World of Warcraft: Forever.

Talks to the game only through files: it reads the addon's SavedVariables (written by the game on
/reload, logout or exit) and writes the inbox addon file (loaded by the game on the next /reload or login).
It never touches the game process, its memory, its network traffic or its input.
"""
import asyncio
import logging
from collections.abc import Iterable
from pathlib import Path
from typing import Any

import Utils
from CommonClient import (
    ClientCommandProcessor,
    CommonContext,
    get_base_parser,
    gui_enabled,
    handle_url_arg,
    server_loop,
)
from MultiServer import mark_raw
from NetUtils import ClientStatus

from ..items import GAME_NAME
from . import inbox, savedvars

LOGGER = logging.getLogger("Client")
POLL_SECONDS = 2.0
INBOX_DEBOUNCE_SECONDS = 1.0
SETTINGS_KEY = "wow_forever_options"


def pending_checks(outbox: Iterable[int], checked: Iterable[int], server_locations: Iterable[int]) -> set[int]:
    """Locations the addon recorded that the server knows and has not marked as checked yet."""
    return (set(outbox) & set(server_locations)) - set(checked)


def goal_to_send(goal_reached: bool, goal_already_sent: bool) -> bool:
    """The goal status is sent once, when a linked character reached the goal."""
    return goal_reached and not goal_already_sent


def slot_key_for(seed_name: str, slot_name: str) -> str:
    """Key under which the addon stores a slot: the seed name makes it unique across multiworlds."""
    return f"{seed_name}:{slot_name}"


def _file_signature(paths: Iterable[Path]) -> tuple:
    signature = []
    for path in paths:
        try:
            stat = path.stat()
        except OSError:
            continue
        signature.append((str(path), stat.st_mtime_ns, stat.st_size))
    return tuple(signature)


def _settings_group() -> Any:
    from settings import get_settings

    return get_settings()[SETTINGS_KEY]


def load_wow_path() -> Path | None:
    """The configured game folder from host.yaml, or None while unset."""
    configured = str(_settings_group().wow_path).strip()
    return Path(configured) if configured else None


def store_wow_path(path: Path) -> None:
    """Persist the game folder to host.yaml."""
    from settings import get_settings

    group = _settings_group()
    group.wow_path = type(group.wow_path)(str(path))
    get_settings().save()


class WoWForeverCommandProcessor(ClientCommandProcessor):
    @mark_raw
    def _cmd_wowpath(self, path: str = "") -> bool:
        """Show or set the World of Warcraft: Forever game folder (the one containing Interface and WTF)."""
        ctx: WoWForeverContext = self.ctx
        if path.strip():
            new_path = Path(path.strip().strip('"'))
            if not new_path.is_dir():
                self.output(f"{new_path} is not a folder.")
                return False
            ctx.wow_path = new_path
            store_wow_path(new_path)
            ctx.request_sync()
            self.output(f"WoW path set to {new_path}")
        else:
            self.output(f"WoW path: {ctx.wow_path or 'not set, use /wowpath <folder>'}")
        return True

    def _cmd_sync(self) -> bool:
        """Re-read the addon's SavedVariables and rewrite the inbox now."""
        ctx: WoWForeverContext = self.ctx
        ctx.request_sync()
        self.output("Syncing with the addon files.")
        return True

    def _cmd_status(self) -> bool:
        """Show linked characters, checks waiting to be sent and the inbox path."""
        ctx: WoWForeverContext = self.ctx
        for line in ctx.status_lines():
            self.output(line)
        return True


class WoWForeverContext(CommonContext):
    command_processor = WoWForeverCommandProcessor
    game = GAME_NAME
    items_handling = 0b111  # the server sends every item, including those found by this slot itself
    want_slot_data = True

    def __init__(self, server_address: str | None, password: str | None):
        super().__init__(server_address, password)
        self.wow_path: Path | None = load_wow_path()
        self.slot_data: dict[str, Any] = {}
        self.saved_state = savedvars.SavedState()
        self.sync_requested = True
        self.inbox_dirty = asyncio.Event()
        self.last_inbox_error = ""
        self.background_tasks: list[asyncio.Task] = []

    # -- identity -------------------------------------------------------------------------------

    @property
    def slot_key(self) -> str | None:
        if not (self.server_seed_name and self.auth and self.slot is not None and self.slot_data):
            return None
        return slot_key_for(self.server_seed_name, self.auth)

    # -- Archipelago hooks ----------------------------------------------------------------------

    async def server_auth(self, password_requested: bool = False) -> None:
        if password_requested and not self.password:
            await super().server_auth(password_requested)
        await self.get_username()
        await self.send_connect()

    def on_package(self, cmd: str, args: dict) -> None:
        if cmd == "Connected":
            self.slot_data = dict(args.get("slot_data") or {})
            self.request_sync()
        elif cmd == "ReceivedItems" or (cmd == "RoomUpdate" and "checked_locations" in args):
            self.inbox_dirty.set()

    def make_gui(self):
        ui_class = super().make_gui()

        class WoWForeverManager(ui_class):
            base_title = "Archipelago World of Warcraft Forever Client"

        return WoWForeverManager

    async def shutdown(self) -> None:
        for task in self.background_tasks:
            task.cancel()
        await super().shutdown()

    # -- sync -----------------------------------------------------------------------------------

    def request_sync(self) -> None:
        """Ask the watch loop to re-read the SavedVariables and rewrite the inbox."""
        self.sync_requested = True
        self.inbox_dirty.set()

    async def sync_from_savedvars(self) -> None:
        """Read the SavedVariables and send new checks and the goal to the server."""
        if self.wow_path is None:
            return
        self.saved_state = await asyncio.to_thread(savedvars.read_all, self.wow_path)
        slot_key = self.slot_key
        if slot_key is None:
            return
        new_checks = pending_checks(self.saved_state.outbox_ids(slot_key), self.checked_locations,
                                    self.server_locations)
        if new_checks:
            await self.check_locations(new_checks)
            LOGGER.info("Sent %d new checks.", len(new_checks))
        if goal_to_send(self.saved_state.goal_reached(slot_key), self.finished_game):
            self.finished_game = True  # CommonClient resends the status after a reconnect
            await self.send_msgs([{"cmd": "StatusUpdate", "status": ClientStatus.CLIENT_GOAL}])
            LOGGER.info("Goal reached: sent to the server.")

    async def write_inbox(self) -> None:
        """Write this slot's inbox table; problems are logged once, not on every update."""
        slot_key = self.slot_key
        if slot_key is None:
            return
        if self.wow_path is None:
            self._report_inbox_error("WoW path not set: use /wowpath <folder>")
            return
        try:
            slot_dict = inbox.build(slot_key, self.server_seed_name, self.auth, self.slot_data,
                                    self.server_locations, self.checked_locations, self.items_received,
                                    self.player_names)
            await asyncio.to_thread(inbox.write, self.wow_path, slot_key, slot_dict)
        except (inbox.InboxError, OSError) as error:
            self._report_inbox_error(str(error))
        else:
            self.last_inbox_error = ""

    def _report_inbox_error(self, message: str) -> None:
        if message != self.last_inbox_error:
            LOGGER.error("Cannot write the inbox: %s", message)
            self.last_inbox_error = message

    def status_lines(self) -> list[str]:
        slot_key = self.slot_key
        lines = [f"WoW path: {self.wow_path or 'not set'}"]
        if slot_key is None:
            return [*lines, "Not connected to a slot."]
        pending = pending_checks(self.saved_state.outbox_ids(slot_key), self.checked_locations, self.server_locations)
        lines += [
            f"Linked characters: {self.saved_state.linked_count(slot_key)}",
            f"Checks waiting to be sent: {len(pending)}",
        ]
        if self.wow_path is not None:
            try:
                lines.append(f"Inbox file: {inbox.inbox_path(self.wow_path)}")
            except inbox.InboxError as error:
                lines.append(str(error))
        return lines


async def sv_watch_loop(ctx: WoWForeverContext) -> None:
    """Poll the SavedVariables files by modification time; the game only writes them on /reload or logout."""
    last_signature: tuple = ()
    while not ctx.exit_event.is_set():
        await asyncio.sleep(POLL_SECONDS)
        if ctx.wow_path is None:
            continue
        signature = _file_signature(savedvars.find_files(ctx.wow_path))
        if signature == last_signature and not ctx.sync_requested:
            continue
        ctx.sync_requested = False
        try:
            await ctx.sync_from_savedvars()
        except OSError as error:
            LOGGER.warning("Could not sync with the addon files: %s", error)
        except Exception:  # noqa: BLE001 - the watcher must outlive any single failed round
            LOGGER.exception("Unexpected error while syncing with the addon files")
        last_signature = signature


async def inbox_writer_loop(ctx: WoWForeverContext) -> None:
    """Rewrite the inbox after changes, waiting a moment so bursts of updates cause one write."""
    while not ctx.exit_event.is_set():
        await ctx.inbox_dirty.wait()
        await asyncio.sleep(INBOX_DEBOUNCE_SECONDS)
        ctx.inbox_dirty.clear()
        await ctx.write_inbox()


async def main(args) -> None:
    ctx = WoWForeverContext(args.connect, args.password)
    ctx.auth = args.name
    ctx.server_task = asyncio.create_task(server_loop(ctx), name="server loop")
    ctx.background_tasks = [
        asyncio.create_task(sv_watch_loop(ctx), name="SavedVariables watcher"),
        asyncio.create_task(inbox_writer_loop(ctx), name="Inbox writer"),
    ]
    if gui_enabled:
        ctx.run_gui()
    ctx.run_cli()
    await ctx.exit_event.wait()
    await ctx.shutdown()


def launch_client(*launch_args: str) -> None:
    """Entry point of the launcher component."""
    Utils.init_logging("WoWForeverClient", exception_logger="Client")
    parser = get_base_parser(description="World of Warcraft: Forever Archipelago client.")
    parser.add_argument("--name", default=None, help="Slot name to connect as.")
    parser.add_argument("url", nargs="?", help="Archipelago connection url")
    args = handle_url_arg(parser.parse_args(launch_args), parser=parser)

    import colorama

    colorama.just_fix_windows_console()
    asyncio.run(main(args))
    colorama.deinit()
